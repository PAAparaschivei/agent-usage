import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case grok

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }

}

public enum ProviderState: String, Codable, Sendable {
    case fresh
    case stale
    case unavailable
}

public enum UsageMetricMode: String, Codable, CaseIterable, Sendable {
    case used
    case left

    public func value(for usedPercent: Double) -> Double {
        let clamped = min(100, max(0, usedPercent))
        return self == .used ? clamped : 100 - clamped
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }
}

public struct ProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let provider: ProviderID
    public let capturedAt: Date
    public let state: ProviderState
    public let source: String
    public let plan: String?
    public let message: String?
    public let windows: [UsageWindow]

    public var id: ProviderID { provider }
    public var primaryWindow: UsageWindow? { windows.first }
    public var weeklyWindow: UsageWindow? {
        windows.first { window in
            window.id.lowercased() == "7d"
                || window.id.lowercased() == "weekly"
                || window.label.localizedCaseInsensitiveCompare("Weekly") == .orderedSame
        }
    }

    public func isCurrent(now: Date = .now) -> Bool {
        state == .fresh && now.timeIntervalSince(capturedAt) < 15 * 60
            && capturedAt <= now.addingTimeInterval(60)
    }

    public func currentWindow(_ window: UsageWindow?, now: Date = .now) -> UsageWindow? {
        guard isCurrent(now: now), let window,
              window.resetsAt.map({ $0 > now }) ?? true else { return nil }
        return window
    }

    public func statusValue(mode: UsageMetricMode, now: Date = .now) -> String {
        guard let window = currentWindow(weeklyWindow ?? primaryWindow, now: now) else { return "—" }
        return UsageText.percent(mode.value(for: window.usedPercent))
    }

    public func aged(now: Date, force: Bool = false) -> ProviderSnapshot {
        guard state == .fresh,
              force || !isCurrent(now: now) || windows.contains(where: { ($0.resetsAt ?? .distantFuture) <= now })
        else { return self }
        return ProviderSnapshot(provider: provider, capturedAt: capturedAt, state: .stale,
                                source: source, plan: plan,
                                message: force ? "Refreshing usage" : "Waiting for fresh usage",
                                windows: windows)
    }

    public init(
        provider: ProviderID,
        capturedAt: Date,
        state: ProviderState,
        source: String,
        plan: String?,
        message: String? = nil,
        windows: [UsageWindow]
    ) {
        self.provider = provider
        self.capturedAt = capturedAt
        self.state = state
        self.source = source
        self.plan = plan
        self.message = message
        self.windows = windows
    }
}

public struct AgentUsageSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let providers: [ProviderSnapshot]

    public init(capturedAt: Date, providers: [ProviderSnapshot]) {
        self.capturedAt = capturedAt
        self.providers = providers
    }

    public static func unavailable(now: Date = .now) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            capturedAt: now,
            providers: ProviderID.allCases.map { provider in
                ProviderSnapshot(
                    provider: provider,
                    capturedAt: now,
                    state: .unavailable,
                    source: "Unavailable",
                    plan: nil,
                    message: "Waiting for first refresh",
                    windows: []
                )
            }
        )
    }

    public func provider(_ id: ProviderID) -> ProviderSnapshot? {
        providers.first { $0.provider == id }
    }

    public func aged(now: Date = .now, force: Bool = false) -> AgentUsageSnapshot {
        AgentUsageSnapshot(capturedAt: capturedAt, providers: providers.map { $0.aged(now: now, force: force) })
    }

    public var mostConstrained: ProviderSnapshot? {
        providers
            .filter { $0.currentWindow($0.primaryWindow) != nil }
            .compactMap { provider -> (ProviderSnapshot, Double)? in
                guard let used = provider.primaryWindow?.usedPercent else { return nil }
                return (provider, 100 - used)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}

public enum UsageText {
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func age(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Updated now" }
        if seconds < 3_600 { return "Updated \(seconds / 60)m ago" }
        return "Updated \(seconds / 3_600)h ago"
    }

    public static func reset(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Reset unavailable" }
        guard date > now else { return "Update needed" }

        let seconds = Int(date.timeIntervalSince(now))
        if seconds < 3_600 {
            return "Resets in \(max(1, seconds / 60))m"
        }
        if seconds < 86_400 {
            let hours = seconds / 3_600
            let minutes = seconds % 3_600 / 60
            return minutes == 0 ? "Resets in \(hours)h" : "Resets in \(hours)h \(minutes)m"
        }

        return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
