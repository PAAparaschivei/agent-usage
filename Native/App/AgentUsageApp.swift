import SwiftUI

@main
struct AgentUsageApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self)
    private var statusItemController

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
