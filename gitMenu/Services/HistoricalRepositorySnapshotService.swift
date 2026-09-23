import Foundation

public struct HistoricalRepositorySnapshot: Sendable {
    public let repositoryURL: URL
    public let revision: String
    private let cleanup: @Sendable () -> Void
    fileprivate init(repositoryURL: URL, revision: String, cleanup: @escaping @Sendable () -> Void) { self.repositoryURL = repositoryURL; self.revision = revision; self.cleanup = cleanup }
    public func removeTemporaryFiles() { cleanup() }
}

public struct HistoricalRepositorySnapshotService: Sendable {
    public init() {}
    public func withSnapshot<T: Sendable>(at repository: URL, revision: String, operation: @Sendable (HistoricalRepositorySnapshot) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gitMenu-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try await runGit(["archive", "--format=tar", revision, "-o", directory.appendingPathComponent("snapshot.tar").path], in: repository)
            try await runProcess("/usr/bin/tar", ["-xf", directory.appendingPathComponent("snapshot.tar").path, "-C", directory.path], in: repository)
            let snapshot = HistoricalRepositorySnapshot(repositoryURL: directory, revision: revision) { try? FileManager.default.removeItem(at: directory) }
            let result = try await operation(snapshot)
            snapshot.removeTemporaryFiles()
            return result
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    private func runGit(_ args: [String], in directory: URL) async throws { try await runProcess("/usr/bin/env", ["git"] + args, in: directory) }
    private func runProcess(_ executable: String, _ args: [String], in directory: URL) async throws {
        try Task.checkCancellation()
        let box = SnapshotProcessBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process(); box.process = process
                let errorPipe = Pipe(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args; process.currentDirectoryURL = directory; process.standardError = errorPipe
                do { try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { let text = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""; throw NSError(domain: "HistoricalSnapshot", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: text.trimmingCharacters(in: .whitespacesAndNewlines)]) }; continuation.resume() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { box.terminate() }
    }
}

private final class SnapshotProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Process?
    var process: Process? { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    func terminate() { process?.terminate() }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T { lock(); defer { unlock() }; return body() }
}
