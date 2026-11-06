import AgentUsageCore
import Darwin
import Foundation

public struct CodexAdapter: ProviderAdapter {
    public let provider: ProviderID = .codex
    private let executableURL: URL?

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    public func load(now: Date) async throws -> ProviderSnapshot {
        let executable = try executableURL ?? Self.locateExecutable()
        return try await Task.detached(priority: .utility) {
            let data = try Self.readRateLimits(executable: executable)
            return try Self.decode(responseData: data, now: now)
        }.value
    }

    static func decode(responseData: Data, now: Date) throws -> ProviderSnapshot {
        guard let response = try? JSONDecoder().decode(
            RPCResponse<GetAccountRateLimitsResponse>.self,
            from: responseData
        ), response.error == nil, let result = response.result else {
            throw ProviderCollectionError.invalidResponse
        }

        let rateLimits = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits
        let windows = [
            Self.window(slot: "primary", value: rateLimits.primary),
            Self.window(slot: "secondary", value: rateLimits.secondary),
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            throw ProviderCollectionError.invalidResponse
        }

        return ProviderSnapshot(
            provider: .codex,
            capturedAt: now,
            state: .fresh,
            source: "Codex app-server",
            plan: Self.planName(rateLimits.planType),
            windows: windows
        )
    }

    private static func readRateLimits(executable: URL) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-c", "analytics.enabled=false", "app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        // Login items do not inherit the interactive shell PATH. npm's Codex
        // launcher uses /usr/bin/env node, so include standard Node locations
        // for this child process while preserving the inherited environment.
        var environment = ProcessInfo.processInfo.environment
        var paths = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        for path in ["/opt/homebrew/bin", "/usr/local/bin"] where !paths.contains(path) {
            paths.append(path)
        }
        environment["PATH"] = paths.joined(separator: ":")
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProviderCollectionError.sourceUnavailable
        }

        let initialize = #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"agent-usage","title":"Agent Usage","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#
        let request = #"{"id":2,"method":"account/rateLimits/read"}"#

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        let handle = output.fileHandleForReading
        var accumulated = Data()
        try input.fileHandleForWriting.write(contentsOf: Data("\(initialize)\n".utf8))
        _ = try Self.readResponse(
            id: 1,
            from: handle,
            accumulated: &accumulated,
            timeout: 4
        )
        let initialized = #"{"method":"initialized"}"#
        try input.fileHandleForWriting.write(contentsOf: Data("\(initialized)\n\(request)\n".utf8))
        return try Self.readResponse(
            id: 2,
            from: handle,
            accumulated: &accumulated,
            timeout: 8
        )
    }

    private static func readResponse(
        id: Int,
        from handle: FileHandle,
        accumulated: inout Data,
        timeout: TimeInterval
    ) throws -> Data {
        if let response = Self.responseLine(id: id, in: accumulated) {
            return response
        }

        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            var descriptor = pollfd(
                fd: handle.fileDescriptor,
                events: Int16(POLLIN),
                revents: 0
            )
            let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
            let status = Darwin.poll(&descriptor, 1, remaining)
            if status == 0 { throw ProviderCollectionError.timedOut }
            if status < 0 { throw ProviderCollectionError.sourceUnavailable }

            var buffer = [UInt8](repeating: 0, count: 8_192)
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if count <= 0 { throw ProviderCollectionError.sourceUnavailable }
            accumulated.append(contentsOf: buffer.prefix(count))

            if let response = Self.responseLine(id: id, in: accumulated) {
                return response
            }
        }

        throw ProviderCollectionError.invalidResponse
    }

    private static func responseLine(id: Int, in data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            guard line.contains("\"id\":\(id)"),
                  let candidate = line.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(RPCID.self, from: candidate),
                  envelope.id == id else { continue }
            return candidate
        }
        return nil
    }

    private static func locateExecutable() throws -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw ProviderCollectionError.notInstalled
        }
        return executable
    }

    private static func window(slot: String, value: RateLimitWindow?) -> UsageWindow? {
        guard let value else { return nil }
        let duration = value.windowDurationMins
        let label: String
        let id: String
        switch duration {
        case 300:
            label = "5-hour"
            id = "5h"
        case 10_080:
            label = "Weekly"
            id = "7d"
        case let minutes?:
            label = "\(minutes / 60)-hour"
            id = "\(slot)-\(minutes)m"
        case nil:
            label = slot.capitalized
            id = slot
        }

        return UsageWindow(
            id: id,
            label: label,
            usedPercent: Double(value.usedPercent),
            resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func planName(_ value: String?) -> String? {
        switch value?.lowercased() {
        case "prolite", "plus": "Plus"
        case "pro": "Pro"
        case "team": "Team"
        case "business": "Business"
        case "enterprise": "Enterprise"
        case let value?: value.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: nil
        }
    }
}

private struct RPCID: Decodable {
    let id: Int?
}

private struct RPCResponse<Result: Decodable>: Decodable {
    let id: Int
    let result: Result?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let code: Int?
}

private struct GetAccountRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

private struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?
}
