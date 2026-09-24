import Foundation
import XCTest
@testable import GitMenuArchitecture
@testable import RepositoryStructureService

final class ArchitectureFoundationTests: XCTestCase {
    func testComparisonIsSortedAndSeparatesChanges() async throws {
        let a = ArchitectureComponent(id: "a", name: "A", kind: .module)
        let b = ArchitectureComponent(id: "b", name: "B", kind: .module)
        let changed = ArchitectureComponent(id: "a", name: "A2", kind: .service)
        let old = RepositoryArchitecture(repositoryID: "r", revision: "one", components: [b, a])
        let new = RepositoryArchitecture(repositoryID: "r", revision: "two", components: [changed, ArchitectureComponent(id: "c", name: "C", kind: .file)])
        let result = try await ArchitectureComparisonService().compare(from: old, to: new)
        XCTAssertEqual(result.addedComponents.map(\.id), ["c"])
        XCTAssertEqual(result.removedComponents.map(\.id), ["b"])
        XCTAssertEqual(result.changedComponents.map(\.id), ["a"])
    }

    func testCacheEvictsLeastRecentlyUsedAndRejectsStaleRevision() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ArchitectureCache(directory: directory, limits: .init(maxEntries: 1, maxBytes: 10_000))
        let first = RepositoryArchitecture(repositoryID: "r", revision: "one")
        let second = RepositoryArchitecture(repositoryID: "r", revision: "two")
        try await cache.insert(first, key: .init(revision: "one", analyzerKey: "test"))
        try await cache.insert(second, key: .init(revision: "two", analyzerKey: "test"))
        let evicted = try await cache.architecture(for: .init(revision: "one", analyzerKey: "test"))
        let stale = try await cache.architecture(for: .init(revision: "two", analyzerKey: "test"), currentRevision: "three")
        let current = try await cache.architecture(for: .init(revision: "two", analyzerKey: "test"))
        XCTAssertNil(evicted)
        XCTAssertNil(stale)
        XCTAssertEqual(current?.revision, "two")
    }

    func testHistoricalSnapshotDoesNotChangeCheckout() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let head = try shellGit(["rev-parse", "HEAD"], in: repository).trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = try await HistoricalRepositorySnapshotService().withSnapshot(at: repository, revision: head) { snapshot in
            try String(contentsOf: snapshot.repositoryURL.appendingPathComponent("README.md"), encoding: .utf8)
        }
        XCTAssertEqual(marker, "historical")
        XCTAssertEqual(try shellGit(["rev-parse", "HEAD"], in: repository).trimmingCharacters(in: .whitespacesAndNewlines), head)
    }

    func testAnalyzerSkipsGeneratedBuildDirectories() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Sources/App.swift")
        let generated = directory.appendingPathComponent("build/DerivedData/GeneratedAssetSymbols.swift")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct App {}".write(to: source, atomically: true, encoding: .utf8)
        try "extension AppKit.NSColor {}".write(to: generated, atomically: true, encoding: .utf8)

        let analysis = try await SwiftRepositoryAnalyzer().analyze(at: directory)

        XCTAssertEqual(analysis.files.map(\.path), ["Sources/App.swift"])
    }

    func testArchitectureBuilderCoalescesRepeatedDeclarations() async throws {
        let evidence = AnalysisEvidence(line: 1, text: "extension AppKit.NSImage", confidence: 1)
        let duplicate = RepositorySymbol(id: "one", name: "AppKit", kind: .extension, path: "Generated.swift", evidence: evidence)
        let analysis = RepositoryAnalysis(
            rootURL: URL(fileURLWithPath: "/tmp/repository"),
            files: [RepositoryAnalysisFile(path: "Generated.swift", language: "swift", symbols: [duplicate, RepositorySymbol(id: "two", name: "AppKit", kind: .extension, path: "Generated.swift", evidence: evidence)])]
        )

        let architecture = try await DeterministicRepositoryArchitectureService().build(from: analysis)

        XCTAssertEqual(architecture.components.map(\.id), ["component:Generated.swift:AppKit"])
    }

    private func makeRepository() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "historical".write(to: url.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        _ = try shellGit(["init", "-q"], in: url); _ = try shellGit(["add", "."], in: url)
        _ = try shellGit(["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "Initial"], in: url)
        return url
    }
    private func shellGit(_ args: [String], in directory: URL) throws -> String {
        let p = Process(); let out = Pipe(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env"); p.arguments = ["git"] + args; p.currentDirectoryURL = directory; p.standardOutput = out; try p.run(); p.waitUntilExit(); XCTAssertEqual(p.terminationStatus, 0); return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
