import AgentUsageCore
import Foundation

public struct UsageCollectionCoordinator: Sendable {
    private let adapters: [any ProviderAdapter]

    public init(adapters: [any ProviderAdapter]) {
        self.adapters = adapters
    }

    public static func live(grokLogEnabled: Bool = false) -> UsageCollectionCoordinator {
        var adapters: [any ProviderAdapter] = [ClaudeStatusAdapter(), CodexAdapter()]
        if grokLogEnabled { adapters.append(GrokAdapter()) }
        return UsageCollectionCoordinator(adapters: adapters)
    }

    public func collect(
        previous: AgentUsageSnapshot?,
        now: Date = .now,
        only: Set<ProviderID>? = nil
    ) async -> AgentUsageSnapshot {
        await withTaskGroup(of: ProviderSnapshot.self) { group in
            for adapter in adapters {
                if let only, !only.contains(adapter.provider) { continue }
                group.addTask {
                    do {
                        return try await adapter.load(now: now)
                    } catch let error as ProviderCollectionError {
                        return Self.failure(
                            provider: adapter.provider,
                            previous: previous,
                            now: now,
                            message: error.userMessage
                        )
                    } catch {
                        return Self.failure(
                            provider: adapter.provider,
                            previous: previous,
                            now: now,
                            message: ProviderCollectionError.sourceUnavailable.userMessage
                        )
                    }
                }
            }

            var loaded: [ProviderID: ProviderSnapshot] = [:]
            for await provider in group {
                loaded[provider.provider] = provider
            }

            let providers = ProviderID.allCases.map { provider in
                guard adapters.contains(where: { $0.provider == provider }) else {
                    return Self.failure(provider: provider, previous: nil, now: now, message: "Source disabled")
                }
                return loaded[provider] ?? (only != nil ? previous?.provider(provider) : nil) ?? Self.failure(
                    provider: provider,
                    previous: previous,
                    now: now,
                    message: ProviderCollectionError.sourceUnavailable.userMessage
                )
            }
            return AgentUsageSnapshot(capturedAt: now, providers: providers)
        }
    }

    private static func failure(
        provider: ProviderID,
        previous: AgentUsageSnapshot?,
        now: Date,
        message: String
    ) -> ProviderSnapshot {
        if let prior = previous?.provider(provider), !prior.windows.isEmpty {
            return ProviderSnapshot(
                provider: prior.provider,
                capturedAt: prior.capturedAt,
                state: .stale,
                source: prior.source,
                plan: prior.plan,
                message: message,
                windows: prior.windows
            )
        }

        return ProviderSnapshot(
            provider: provider,
            capturedAt: now,
            state: .unavailable,
            source: "Unavailable",
            plan: nil,
            message: message,
            windows: []
        )
    }
}
