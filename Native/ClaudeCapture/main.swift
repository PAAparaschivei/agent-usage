import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let now = Int64(Date().timeIntervalSince1970)

if let payload = try? JSONDecoder().decode(StatusPayload.self, from: input) {
    let reduced = ReducedCache(
        capturedAt: now,
        source: "statusline",
        rateLimits: payload.rateLimits
    )

    let cacheURL = ProcessInfo.processInfo.environment["AGENT_USAGE_CLAUDE_CACHE"]
        .map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/agent-usage-status.json")
    if let limits = reduced.rateLimits, limits.fiveHour != nil || limits.sevenDay != nil,
       let data = try? JSONEncoder.reduced.encode(reduced) {
        try? data.write(to: cacheURL, options: .atomic)
    }

    print(StatusText.render(payload))
} else {
    print("Claude Code")
}

private struct StatusPayload: Decodable {
    let model: Model?
    let contextWindow: ContextWindow?
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case model
        case contextWindow = "context_window"
        case rateLimits = "rate_limits"
    }
}

private struct Model: Decodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct ContextWindow: Decodable {
    let usedPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
    }
}

private struct RateLimits: Codable {
    let fiveHour: Limit?
    let sevenDay: Limit?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct Limit: Codable {
    let usedPercentage: Double
    let resetsAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

private struct ReducedCache: Encodable {
    let capturedAt: Int64
    let source: String
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
        case source
        case rateLimits = "rate_limits"
    }
}

private enum StatusText {
    static func render(_ payload: StatusPayload) -> String {
        var parts: [String] = []
        if let context = payload.contextWindow?.usedPercentage {
            parts.append("Context \(percent(context))")
        }
        if let fiveHour = payload.rateLimits?.fiveHour?.usedPercentage {
            parts.append("5h \(percent(fiveHour))")
        }
        if let sevenDay = payload.rateLimits?.sevenDay?.usedPercentage {
            parts.append("7d \(percent(sevenDay))")
        }
        if let model = payload.model?.displayName {
            parts.append(model)
        }
        return parts.isEmpty ? "Claude Code" : parts.joined(separator: " · ")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(min(100, max(0, value)).rounded()))%"
    }
}

private extension JSONEncoder {
    static var reduced: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
