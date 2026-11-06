import AgentUsageCore
import SwiftUI

struct MenuBarStatus: View {
    let snapshot: AgentUsageSnapshot
    let mode: UsageMetricMode

    private let providerOrder: [ProviderID] = [.codex, .claude, .grok]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(providerOrder) { providerID in
                HStack(spacing: 2) {
                    ProviderMark(provider: providerID, size: 14, plate: false)
                    Text(value(for: providerID))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent Usage weekly limits")
        .accessibilityValue(accessibilityValue)
    }

    private func value(for providerID: ProviderID) -> String {
        snapshot.provider(providerID)?.statusValue(mode: mode) ?? "—"
    }

    private var accessibilityValue: String {
        providerOrder.map { providerID in
            "\(providerID.name) \(value(for: providerID)) \(mode.rawValue)"
        }.joined(separator: ", ")
    }
}
