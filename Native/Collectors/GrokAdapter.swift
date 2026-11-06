import AgentUsageCore
import Foundation

public struct GrokAdapter: ProviderAdapter {
    public let provider: ProviderID = .grok
    private let logURL: URL

    public init(logURL: URL? = nil) {
        self.logURL = logURL ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".grok/logs/unified.jsonl")
    }

    public func load(now: Date) async throws -> ProviderSnapshot {
        try Self.loadLog(url: logURL, now: now)
    }

    static func loadLog(url: URL, now: Date) throws -> ProviderSnapshot {
        let eventData = try latestBillingEvent(in: url)
        guard let event = try? JSONDecoder().decode(BillingLogEvent.self, from: eventData),
              let capturedAt = parseDate(event.timestamp),
              let used = event.context.config.creditUsagePercent, (0...100).contains(used) else {
            throw ProviderCollectionError.invalidResponse
        }

        let state: ProviderState = now.timeIntervalSince(capturedAt) <= 15 * 60
            ? .fresh
            : .stale
        return Self.snapshot(
            usedPercent: used,
            resetText: event.context.config.currentPeriod?.end
                ?? event.context.config.billingPeriodEnd,
            periodType: event.context.config.currentPeriod?.type,
            plan: event.context.subscriptionTier,
            capturedAt: capturedAt,
            state: state,
            source: "Grok billing log"
        )
    }

    private static func latestBillingEvent(in url: URL) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ProviderCollectionError.noSnapshot
        }
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let limit: UInt64 = 8 * 1_024 * 1_024
        try handle.seek(toOffset: size > limit ? size - limit : 0)
        guard let data = try handle.read(upToCount: Int(limit)) else {
            throw ProviderCollectionError.noSnapshot
        }
        let text = String(decoding: data, as: UTF8.self)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed()
        where line.contains("billing: fetched credits config") {
            if let data = line.data(using: .utf8) { return data }
        }
        throw ProviderCollectionError.noSnapshot
    }

    private static func snapshot(
        usedPercent: Double,
        resetText: String?,
        periodType: String?,
        plan: String?,
        capturedAt: Date,
        state: ProviderState,
        source: String
    ) -> ProviderSnapshot {
        let label = periodType?.uppercased().contains("WEEK") == true
            ? "Weekly"
            : "Current period"
        let window = UsageWindow(
            id: "current",
            label: label,
            usedPercent: usedPercent,
            resetsAt: resetText.flatMap(parseDate)
        )
        return ProviderSnapshot(
            provider: .grok,
            capturedAt: capturedAt,
            state: state,
            source: source,
            plan: plan,
            windows: [window]
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct BillingPayload: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: BillingPeriod?
    let billingPeriodEnd: String?
    let subscriptionTier: String?
}

private struct BillingPeriod: Decodable {
    let type: String?
    let end: String?
}

private struct BillingLogEvent: Decodable {
    let timestamp: String
    let context: BillingLogContext

    enum CodingKeys: String, CodingKey {
        case timestamp = "ts"
        case context = "ctx"
    }
}

private struct BillingLogContext: Decodable {
    let config: BillingPayload
    let subscriptionTier: String?
}
