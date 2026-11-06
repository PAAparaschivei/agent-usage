import AgentUsageCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate {
    private let model = AppModel(
        initialSnapshot: CommandLine.arguments.contains("--demo") ? MockSnapshot.make() : nil
    )
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !model.isDemo, CommandLine.arguments.contains("--diagnose") {
            // Exercise the installed app's real launch/refresh path without UI.
            model.$isRefreshing.dropFirst().filter { !$0 }.sink { [weak self] _ in
                guard let self else { return }
                for provider in self.model.snapshot.providers {
                    print("\(provider.provider.name): \(provider.state.rawValue); "
                          + "\(provider.statusValue(mode: .left)) left; "
                          + "\(provider.message ?? provider.source)")
                }
                print("Local cache: \(self.model.storageMessage ?? "OK")")
                print("Login item: \(RuntimeSettings().launchAtLogin ? "enabled" : "disabled")")
                fflush(stdout)
                NSApp.terminate(nil)
            }.store(in: &cancellables)
            return
        }
        let current = NSRunningApplication.current
        if let identity = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identity).contains(where: {
               $0.processIdentifier != current.processIdentifier && !$0.isTerminated
                   && ($0.launchDate ?? .distantPast) < (current.launchDate ?? .distantFuture)
           }) {
            NSApp.terminate(nil)
            return
        }
        #if DEBUG
        if model.isDemo, CommandLine.arguments.contains("--capture") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
        configurePopover()
        configureStatusItem()
        observeUsage()
        if model.isDemo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.togglePopover()
                #if DEBUG
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.captureDemoIfRequested()
                }
                #endif
            }
        }
    }

    #if DEBUG
    private func captureDemoIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--capture"),
              arguments.indices.contains(index + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do {
            guard statusItem?.button?.image != nil, popover.isShown,
                  let view = popover.contentViewController?.view else {
                throw CocoaError(.featureUnsupported)
            }
            try VisualCapture.writePopover(view, to: directory)
            print("Demo menu bar and popover verified")
            NSApp.terminate(nil)
        } catch {
            fputs("Demo capture failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
    #endif

    private func configurePopover() {
        let controller = NSHostingController(rootView: UsagePopover(model: model))
        controller.view.layoutSubtreeIfNeeded()

        popover.behavior = model.isDemo ? .applicationDefined : .transient
        popover.appearance = NSApp.appearance
        popover.animates = true
        popover.contentViewController = controller
        popover.contentSize = NSSize(
            width: 390,
            height: max(460, controller.view.fittingSize.height)
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.toolTip = "Agent Usage"
        button.setAccessibilityLabel("Agent Usage weekly limits")

        statusItem = item
        updateStatusItem(snapshot: model.snapshot, mode: model.mode)
    }

    private func observeUsage() {
        model.$snapshot
            .combineLatest(model.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, mode in
                self?.updateStatusItem(snapshot: snapshot, mode: mode)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(
        snapshot: AgentUsageSnapshot,
        mode: UsageMetricMode
    ) {
        guard let statusItem, let button = statusItem.button else { return }

        let content = MenuBarStatus(snapshot: snapshot, mode: mode)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 2)
            .frame(height: 18)
            .fixedSize()
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else { return }
        image.isTemplate = true
        button.image = image
        statusItem.length = ceil(image.size.width) + 4
        button.setAccessibilityValue(accessibilityValue(snapshot: snapshot, mode: mode))
    }

    private func accessibilityValue(
        snapshot: AgentUsageSnapshot,
        mode: UsageMetricMode
    ) -> String {
        [ProviderID.codex, .claude, .grok].map { providerID in
            let value = snapshot.provider(providerID)?.statusValue(mode: mode) ?? "Unavailable"
            return "\(providerID.name) \(value) \(mode.rawValue)"
        }.joined(separator: ", ")
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshIfNeeded()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}
