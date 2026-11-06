import AgentUsageCore
import AgentUsageCollectors
import Combine
import Foundation
import AppKit
import Network

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: AgentUsageSnapshot
    @Published var mode: UsageMetricMode {
        didSet {
            guard mode != oldValue, !isDemo else { return }
            UserDefaults.standard.set(mode.rawValue, forKey: "usageMetricMode")
        }
    }
    @Published var storageMessage: String?
    @Published var isRefreshing = false

    let isDemo: Bool
    private let store: SnapshotStore?
    private let coordinatorOverride: UsageCollectionCoordinator?
    private var refreshTimer: AnyCancellable?
    private var defaultsObserver: AnyCancellable?
    private var wakeObserver: AnyCancellable?
    private var ageTimer: AnyCancellable?
    private let networkMonitor = NWPathMonitor()
    private var networkWasAvailable: Bool?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var refreshPending = false
    private var configuredInterval: Int?

    init(
        initialSnapshot: AgentUsageSnapshot? = nil,
        coordinator: UsageCollectionCoordinator? = nil,
        autoRefresh: Bool = true,
        now: Date = .now
    ) {
        isDemo = initialSnapshot != nil
        store = isDemo ? nil : try? SnapshotStore.local()
        coordinatorOverride = coordinator
        mode = UsageMetricMode(
            rawValue: UserDefaults.standard.string(forKey: "usageMetricMode") ?? ""
        ) ?? .left
        snapshot = initialSnapshot
            ?? (try? store?.read().aged(now: now, force: true))
            ?? AgentUsageSnapshot.unavailable(now: now)

        if autoRefresh, initialSnapshot == nil {
            Task { [weak self] in
                await self?.refreshNow()
            }
            configurePeriodicRefresh()
            configureRecovery()
            defaultsObserver = NotificationCenter.default.publisher(
                for: UserDefaults.didChangeNotification
            ).sink { [weak self] _ in
                Task { @MainActor in
                    self?.configurePeriodicRefresh()
                    if let rawValue = UserDefaults.standard.string(forKey: "usageMetricMode"),
                       let mode = UsageMetricMode(rawValue: rawValue),
                       self?.mode != mode {
                        self?.mode = mode
                    }
                }
            }
        }
    }

    func refresh() {
        Task { [weak self] in
            await self?.refreshNow()
        }
    }

    func refreshForCapture() async {
        await refreshNow()
    }

    func refreshIfNeeded() {
        guard !isDemo else { return }
        let aged = snapshot.aged()
        if aged != snapshot { snapshot = aged; persist() }
        if snapshot.providers.contains(where: { !$0.isCurrent() }) { refresh() }
    }

    private func configureRecovery() {
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.snapshot = self.snapshot.aged(force: true)
                    self.persist()
                    await self.refreshNow()
                }
            }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let restored = self.networkWasAvailable == false && available
                self.networkWasAvailable = available
                if restored { await self.refreshNow() }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "AgentUsage.network"))
        ageTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let aged = self.snapshot.aged()
                if aged != self.snapshot {
                    self.snapshot = aged
                    self.persist()
                    self.refresh()
                }
            }
    }

    private func refreshNow(onlyMissing: Bool = false) async {
        guard !isDemo else { return }
        guard !isRefreshing else { refreshPending = true; return }
        if !onlyMissing {
            retryTask?.cancel()
            retryAttempt = 0
        }
        isRefreshing = true
        let coordinator = coordinatorOverride ?? .live(
            grokLogEnabled: UserDefaults.standard.bool(forKey: "readGrokBillingLog")
        )
        let missing = Set(snapshot.providers.filter {
            !$0.isCurrent() && $0.message != ProviderCollectionError.signedOut.userMessage && $0.message != "Source disabled"
        }.map(\.provider))
        let refreshed = await coordinator.collect(previous: snapshot, only: onlyMissing ? missing : nil)
        snapshot = refreshed
        persist()
        await UsageAlertManager().evaluate(refreshed)
        isRefreshing = false
        if refreshPending {
            refreshPending = false
            await refreshNow()
            return
        }
        let needsRetry = refreshed.providers.contains {
            !$0.isCurrent() && $0.message != ProviderCollectionError.signedOut.userMessage && $0.message != "Source disabled"
        }
        let delays: [UInt64] = [30, 120, 300]
        if needsRetry, retryAttempt < delays.count {
            let delay = delays[retryAttempt]
            retryAttempt += 1
            retryTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
                await self?.refreshNow(onlyMissing: true)
            }
        }
    }

    private func persist() {
        guard let store else {
            storageMessage = "Local cache unavailable"
            return
        }

        do {
            try store.write(snapshot)
            storageMessage = nil
        } catch {
            storageMessage = "Local cache unavailable"
        }
    }

    private func configurePeriodicRefresh() {
        let storedInterval = UserDefaults.standard.object(
            forKey: "refreshIntervalMinutes"
        ) as? Int
        let minutes = storedInterval ?? 5
        guard configuredInterval != minutes else { return }
        configuredInterval = minutes
        refreshTimer?.cancel()
        guard minutes > 0 else { return }

        refreshTimer = Timer.publish(
            every: TimeInterval(minutes * 60),
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.refresh()
        }
    }
}
