import Foundation
#if SWIFT_PACKAGE
import GitMenuArchitecture
#endif

public struct ArchitectureComparisonService: Sendable {
    public init() {}
    public func compare(from: RepositoryArchitecture, to: RepositoryArchitecture) async throws -> ArchitectureComparison {
        try Task.checkCancellation()
        return ArchitectureComparison(from: from, to: to)
    }
}

public struct ArchitectureCacheKey: Codable, Hashable, Sendable {
    public let revision: String
    public let schema: Int
    public let analyzerKey: String
    public init(revision: String, schema: Int = RepositoryArchitecture.schemaVersion, analyzerKey: String) {
        self.revision = revision; self.schema = schema; self.analyzerKey = analyzerKey
    }
}

public struct ArchitectureCacheLimits: Hashable, Sendable {
    public var maxEntries: Int
    public var maxBytes: Int64
    public init(maxEntries: Int = 20, maxBytes: Int64 = 50 * 1024 * 1024) { self.maxEntries = max(0, maxEntries); self.maxBytes = max(0, maxBytes) }
}

public actor ArchitectureCache {
    private struct Entry: Codable { let key: ArchitectureCacheKey; let architecture: RepositoryArchitecture; let byteCount: Int64; let lastAccess: Date }
    private let directory: URL
    private let limits: ArchitectureCacheLimits
    private var entries: [ArchitectureCacheKey: Entry] = [:]
    private var loaded = false

    public init(directory: URL, limits: ArchitectureCacheLimits = .init()) { self.directory = directory; self.limits = limits }

    public func architecture(for key: ArchitectureCacheKey, currentRevision: String? = nil) async throws -> RepositoryArchitecture? {
        try await loadIfNeeded()
        guard key.revision == currentRevision ?? key.revision, let entry = entries[key] else { return nil }
        entries[key] = Entry(key: entry.key, architecture: entry.architecture, byteCount: entry.byteCount, lastAccess: Date())
        return entry.architecture
    }

    public func insert(_ architecture: RepositoryArchitecture, key: ArchitectureCacheKey) async throws {
        try await loadIfNeeded()
        let data = try JSONEncoder().encode(architecture)
        entries[key] = Entry(key: key, architecture: architecture, byteCount: Int64(data.count), lastAccess: Date())
        try evictAndPersist()
    }

    public func removeAll() throws { entries.removeAll(); loaded = true; try persist() }
    public func count() async throws -> Int { try await loadIfNeeded(); return entries.count }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }; loaded = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("architecture-cache.json")
        guard let data = try? Data(contentsOf: url) else { return }
        entries = (try? JSONDecoder().decode([ArchitectureCacheKey: Entry].self, from: data)) ?? [:]
    }
    private func evictAndPersist() throws {
        while entries.count > limits.maxEntries || entries.values.reduce(Int64(0), { $0 + $1.byteCount }) > limits.maxBytes {
            guard let oldest = entries.values.min(by: { $0.lastAccess < $1.lastAccess }) else { break }
            entries.removeValue(forKey: oldest.key)
        }
        try persist()
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: directory.appendingPathComponent("architecture-cache.json"), options: .atomic)
    }
}
