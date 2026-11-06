import Foundation

public enum SnapshotStoreError: LocalizedError {
    case applicationSupportUnavailable

    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "The Application Support directory is unavailable."
        }
    }
}

public struct SnapshotStore {
    public static let filename = "usage-snapshot.json"

    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.filename, isDirectory: false)
    }

    public static func local(fileManager: FileManager = .default) throws -> SnapshotStore {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SnapshotStoreError.applicationSupportUnavailable
        }

        return SnapshotStore(
            directory: applicationSupport.appendingPathComponent("Agent Usage Menu Bar", isDirectory: true)
        )
    }

    public func write(_ snapshot: AgentUsageSnapshot, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
    }

    public func read() throws -> AgentUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentUsageSnapshot.self, from: Data(contentsOf: fileURL))
    }
}
