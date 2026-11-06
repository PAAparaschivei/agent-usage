import AgentUsageCore
import Foundation

public struct ClaudeStatusAdapter: ProviderAdapter {
    public let provider: ProviderID = .claude
    private let cacheURL: URL

    public init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/agent-usage-status.json")
    }

    public func load(now: Date) async throws -> ProviderSnapshot {
        let cacheURL = cacheURL
        return try await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: cacheURL) else {
                throw ProviderCollectionError.noSnapshot
            }
            return try Self.decode(data: data, now: now)
        }.value
    }

    static func decode(data: Data, now: Date) throws -> ProviderSnapshot {
        guard let payload = try? JSONDecoder().decode(CachePayload.self, from: data),
              let limits = payload.rateLimits else {
            throw ProviderCollectionError.invalidResponse
        }

        let capturedAt = Date(timeIntervalSince1970: TimeInterval(payload.capturedAt))
        let state: ProviderState = now.timeIntervalSince(capturedAt) <= 15 * 60
            ? .fresh
            : .stale

        let windows = [
            Self.window(id: "5h", label: "5-hour", value: limits.fiveHour),
            Self.window(id: "7d", label: "Weekly", value: limits.sevenDay),
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            throw ProviderCollectionError.invalidResponse
        }

        return ProviderSnapshot(
            provider: .claude,
            capturedAt: capturedAt,
            state: state,
            source: "Claude status line",
            plan: nil,
            message: state == .stale ? "Open Claude Code to refresh" : nil,
            windows: windows
        )
    }

    private static func window(
        id: String,
        label: String,
        value: LimitPayload?
    ) -> UsageWindow? {
        guard let value else { return nil }
        return UsageWindow(
            id: id,
            label: label,
            usedPercent: value.usedPercentage,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(value.resetsAt))
        )
    }
}

private struct CachePayload: Decodable {
    let capturedAt: Int64
    let rateLimits: RateLimitsPayload?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case rateLimits = "rate_limits"
    }
}

private struct RateLimitsPayload: Decodable {
    let fiveHour: LimitPayload?
    let sevenDay: LimitPayload?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct LimitPayload: Decodable {
    let usedPercentage: Double
    let resetsAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}
