import AgentUsageCore
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class RuntimeSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var limitAlerts: Bool
    @Published private(set) var message: String?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        limitAlerts = UserDefaults.standard.bool(forKey: "showLimitAlerts")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = launchAtLogin == enabled
                ? nil
                : "Approve Agent Usage in System Settings > Login Items."
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = "Launch at login could not be changed."
        }
    }

    func setLimitAlerts(_ enabled: Bool) {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: "showLimitAlerts")
            limitAlerts = false
            message = nil
            return
        }

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
                UserDefaults.standard.set(granted, forKey: "showLimitAlerts")
                limitAlerts = granted
                message = granted ? nil : "Notifications are disabled for Agent Usage."
            } catch {
                UserDefaults.standard.set(false, forKey: "showLimitAlerts")
                limitAlerts = false
                message = "Notification access could not be requested."
            }
        }
    }
}

@MainActor
struct UsageAlertManager {
    private let defaults = UserDefaults.standard

    func evaluate(_ snapshot: AgentUsageSnapshot) async {
        guard defaults.bool(forKey: "showLimitAlerts") else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        var sent = Set(defaults.stringArray(forKey: "sentUsageAlerts") ?? [])
        var currentTokens: Set<String> = []

        for provider in snapshot.providers {
            guard let window = provider.currentWindow(provider.primaryWindow) else { continue }
            let period = Int((window.resetsAt ?? provider.capturedAt).timeIntervalSince1970)
            let tokens = UsageAlertPolicy.thresholds.map {
                token(provider: provider.provider, window: window, period: period, threshold: $0)
            }
            currentTokens.formUnion(tokens)

            let left = Int((100 - window.usedPercent).rounded())
            let sentThresholds = Set(UsageAlertPolicy.thresholds.filter { threshold in
                sent.contains(token(
                    provider: provider.provider,
                    window: window,
                    period: period,
                    threshold: threshold
                ))
            })
            guard let threshold = UsageAlertPolicy.nextThreshold(
                leftPercent: left,
                alreadySent: sentThresholds
            ) else { continue }
            let pending = token(
                provider: provider.provider,
                window: window,
                period: period,
                threshold: threshold
            )
            guard !sent.contains(pending) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(provider.provider.name) has \(left)% left"
            content.body = "\(window.label) limit. \(UsageText.reset(window.resetsAt))."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: pending,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
            let crossed = UsageAlertPolicy.thresholds.filter { left <= $0 }
            sent.formUnion(crossed.map {
                token(
                    provider: provider.provider,
                    window: window,
                    period: period,
                    threshold: $0
                )
            })
        }

        sent.formIntersection(currentTokens)
        defaults.set(Array(sent).sorted(), forKey: "sentUsageAlerts")
    }

    private func token(
        provider: ProviderID,
        window: UsageWindow,
        period: Int,
        threshold: Int
    ) -> String {
        "\(provider.rawValue).\(window.id).\(period).\(threshold)"
    }
}
