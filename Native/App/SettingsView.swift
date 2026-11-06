import AgentUsageCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshIntervalMinutes") private var refreshInterval = 5
    @AppStorage("usageMetricMode") private var usageMetricMode = UsageMetricMode.left.rawValue
    @AppStorage("readGrokBillingLog") private var readGrokBillingLog = false
    @StateObject private var runtime = RuntimeSettings()

    var body: some View {
        Form {
            Picker("Default display", selection: $usageMetricMode) {
                Text("Percentage left").tag(UsageMetricMode.left.rawValue)
                Text("Percentage used").tag(UsageMetricMode.used.rawValue)
            }

            Picker("Refresh", selection: $refreshInterval) {
                Text("Every 5 minutes").tag(5)
                Text("Every 15 minutes").tag(15)
                Text("No periodic refresh").tag(0)
            }

            Toggle(
                "Open at login",
                isOn: Binding(
                    get: { runtime.launchAtLogin },
                    set: { runtime.setLaunchAtLogin($0) }
                )
            )

            Toggle(
                "Limit alerts",
                isOn: Binding(
                    get: { runtime.limitAlerts },
                    set: { runtime.setLimitAlerts($0) }
                )
            )

            Toggle("Read Grok billing log", isOn: $readGrokBillingLog)

            Text("Shows the last billing event written by Grok CLI on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Data") {
                Text("Stored on this Mac")
                    .foregroundStyle(.secondary)
            }

            if let message = runtime.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}
