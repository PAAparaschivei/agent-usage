import Foundation

public enum ProviderCollectionError: Error, Equatable, Sendable {
    case notInstalled
    case signedOut
    case noSnapshot
    case invalidResponse
    case timedOut
    case sourceUnavailable

    public var userMessage: String {
        switch self {
        case .notInstalled: "CLI not found"
        case .signedOut: "Sign in required"
        case .noSnapshot: "No usage snapshot yet"
        case .invalidResponse: "Usage response changed"
        case .timedOut: "Refresh timed out"
        case .sourceUnavailable: "Usage source unavailable"
        }
    }
}
