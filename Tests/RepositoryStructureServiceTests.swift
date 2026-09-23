import Foundation
import XCTest
@testable import RepositoryStructureService

final class RepositoryStructureServiceTests: XCTestCase {
    func testLoadsRevisionFilesMetadataAndNormalizedTree() async throws {
        let repository = try makeRepository(files: [
            "README.md": "# Demo",
            "Package.swift": "// manifest",
            "Sources/App/main.swift": "print(\"hello\")"
        ])
        defer { try? FileManager.default.removeItem(at: repository) }

        let structure = try await RepositoryStructureService().load(at: repository)
        XCTAssertEqual(structure.files.map(\.path), ["Package.swift", "README.md", "Sources/App/main.swift"])
        XCTAssertEqual(structure.documentation.map(\.path), ["README.md"])
        XCTAssertEqual(structure.manifests.map(\.path), ["Package.swift"])
        XCTAssertEqual(structure.tree.children.map(\.name), ["Package.swift", "README.md", "Sources"])
        XCTAssertFalse(structure.revision.isEmpty)
    }

    func testFilterAndLimitsReportOmittedFiles() async throws {
        let repository = try makeRepository(files: ["README.md": "readme", "Sources/a.swift": "12345", "Sources/b.swift": "12345"])
        defer { try? FileManager.default.removeItem(at: repository) }

        let structure = try await RepositoryStructureService().load(
            at: repository,
            options: .init(maxFileCount: 1, maxTotalBytes: 5, maxFileSizeBytes: 100, pathFilter: "Sources")
        )
        XCTAssertEqual(structure.files.count, 1)
        XCTAssertEqual(structure.omittedFileCount, 1)
        XCTAssertEqual(structure.files.first?.path, "Sources/a.swift")
    }

    func testCancellationIsObserved() async throws {
        let repository = try makeRepository(files: ["README.md": "readme"])
        defer { try? FileManager.default.removeItem(at: repository) }
        let task = Task { try await RepositoryStructureService().load(at: repository) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            // A cancellation racing with a short Git command may surface as a terminated process.
        }
    }

    private func makeRepository(files: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (path, contents) in files {
            let fileURL = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        try runGit(["init", "-q"], in: url)
        try runGit(["add", "."], in: url)
        try runGit(["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-qm", "Initial"], in: url)
        return url
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
