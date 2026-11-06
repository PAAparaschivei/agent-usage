import Foundation

public protocol ProviderAdapter: Sendable {
    var provider: ProviderID { get }
    func load(now: Date) async throws -> ProviderSnapshot
}
