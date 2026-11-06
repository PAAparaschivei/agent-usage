import Foundation

public enum MockSnapshot {
    public static func make(now: Date = .now) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            capturedAt: now,
            providers: [
                ProviderSnapshot(
                    provider: .claude,
                    capturedAt: now,
                    state: .fresh,
                    source: "Claude Code",
                    plan: "Max 20x",
                    windows: [
                        UsageWindow(
                            id: "weekly",
                            label: "Weekly",
                            usedPercent: 32,
                            resetsAt: now.addingTimeInterval(3 * 86_400 + 9_000)
                        ),
                        UsageWindow(
                            id: "5-hour",
                            label: "5-hour",
                            usedPercent: 58,
                            resetsAt: now.addingTimeInterval(8_040)
                        ),
                    ]
                ),
                ProviderSnapshot(
                    provider: .codex,
                    capturedAt: now,
                    state: .fresh,
                    source: "Codex app server",
                    plan: "Plus",
                    windows: [
                        UsageWindow(
                            id: "weekly",
                            label: "Weekly",
                            usedPercent: 72,
                            resetsAt: now.addingTimeInterval(4 * 86_400 + 7_200)
                        ),
                    ]
                ),
                ProviderSnapshot(
                    provider: .grok,
                    capturedAt: now,
                    state: .fresh,
                    source: "Grok billing log",
                    plan: "SuperGrok",
                    windows: [
                        UsageWindow(
                            id: "weekly",
                            label: "Weekly",
                            usedPercent: 20,
                            resetsAt: now.addingTimeInterval(6 * 86_400 + 3_600)
                        ),
                    ]
                ),
            ]
        )
    }
}
