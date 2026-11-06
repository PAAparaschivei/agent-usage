import AgentUsageCore
import AppKit
import SwiftUI

struct UsagePopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Display", selection: $model.mode) {
                Text("Used").tag(UsageMetricMode.used)
                Text("Left").tag(UsageMetricMode.left)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(model.snapshot.providers.enumerated()), id: \.element.id) { index, provider in
                    ProviderRow(provider: provider, mode: model.mode)
                    if index < model.snapshot.providers.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.horizontal, 16)

            Divider()

            footer
        }
        .frame(width: 390)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage")
                    .font(.system(size: 17, weight: .semibold))
                Text(UsageText.age(model.snapshot.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Open settings")
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: model.storageMessage == nil ? "lock.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(model.isDemo ? "Sample data" : (model.storageMessage ?? "Cache stored on this Mac"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ProviderRow: View {
    let provider: ProviderSnapshot
    let mode: UsageMetricMode

    private var primary: UsageWindow? { provider.currentWindow(provider.primaryWindow) }

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                ProviderMark(provider: provider.provider)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.provider.name)
                        .font(.system(size: 13, weight: .semibold))
                    if provider.plan != nil || provider.state != .fresh {
                        HStack(spacing: 4) {
                            if let plan = provider.plan {
                                Text(plan)
                            }
                            if provider.plan != nil && provider.state != .fresh {
                                Text("·")
                            }
                            if provider.state != .fresh {
                                Text(provider.state == .stale ? "Stale" : "Unavailable")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let primary {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(UsageText.percent(mode.value(for: primary.usedPercent)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(mode.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("—")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(provider.message ?? "Unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let primary {
                UsageBar(value: mode.value(for: primary.usedPercent))

                HStack {
                    Text(primary.label)
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(UsageText.reset(primary.resetsAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if primary != nil, provider.windows.count > 1 {
                ForEach(provider.windows.dropFirst().filter { provider.currentWindow($0) != nil }) { window in
                    HStack(spacing: 8) {
                        Text(window.label)
                            .frame(width: 45, alignment: .leading)
                        UsageBar(value: mode.value(for: window.usedPercent), height: 3)
                        Text(UsageText.percent(mode.value(for: window.usedPercent)))
                            .monospacedDigit()
                        Text("·")
                        Text(UsageText.reset(window.resetsAt))
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            if primary == nil {
                Text("\(provider.message ?? "Waiting for fresh usage") · \(UsageText.age(provider.capturedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct UsageBar: View {
    let value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(value <= 20 ? Color.orange : Color.primary)
                    .frame(width: geometry.size.width * min(1, max(0, value / 100)))
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(UsageText.percent(value))")
    }
}
