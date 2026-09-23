import Foundation
#if SWIFT_PACKAGE
import GitMenuArchitecture
#endif

struct RepositoryStructureServiceOptions: Sendable, Hashable {
    var maxFileCount: Int = 10_000
    var maxTotalBytes: Int64 = 50 * 1024 * 1024
    var maxFileSizeBytes: Int64 = 5 * 1024 * 1024
    var pathFilter: String?

    init(
        maxFileCount: Int = 10_000,
        maxTotalBytes: Int64 = 50 * 1024 * 1024,
        maxFileSizeBytes: Int64 = 5 * 1024 * 1024,
        pathFilter: String? = nil
    ) {
        self.maxFileCount = max(0, maxFileCount)
        self.maxTotalBytes = max(0, maxTotalBytes)
        self.maxFileSizeBytes = max(0, maxFileSizeBytes)
        self.pathFilter = pathFilter?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RepositoryStructureServiceError: LocalizedError, Equatable {
    case notARepository(URL)
    case invalidOptions
    case gitFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .notARepository(url): return "Not a Git repository: \(url.path)"
        case .invalidOptions: return "Repository structure limits are invalid."
        case let .gitFailed(command, message): return "Git command failed (\(command)): \(message)"
        }
    }
}

protocol RepositoryStructureServiceProtocol: Sendable {
    func load(at url: URL, options: RepositoryStructureServiceOptions) async throws -> RepositoryStructure
}

struct RepositoryStructureService: RepositoryStructureServiceProtocol, Sendable {
    init() {}

    func load(at url: URL, options: RepositoryStructureServiceOptions = .init()) async throws -> RepositoryStructure {
        guard options.maxFileCount >= 0, options.maxTotalBytes >= 0, options.maxFileSizeBytes >= 0 else {
            throw RepositoryStructureServiceError.invalidOptions
        }

        let root = try await git(["rev-parse", "--show-toplevel"], in: url)
        let rootURL = URL(fileURLWithPath: root.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
        let revision = try await git(["rev-parse", "HEAD"], in: rootURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let output = try await git(["ls-files", "-z"], in: rootURL)
        let paths = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)

        var files: [RepositoryFile] = []
        var omittedFileCount = 0
        var omittedByteCount: Int64 = 0
        var totalBytes: Int64 = 0

        for path in paths {
            try Task.checkCancellation()
            if let filter = options.pathFilter, !filter.isEmpty,
               !path.localizedCaseInsensitiveContains(filter) { continue }

            let fileURL = rootURL.appendingPathComponent(path)
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let accepted = files.count < options.maxFileCount
                && size <= options.maxFileSizeBytes
                && totalBytes <= options.maxTotalBytes - size
            guard accepted else {
                omittedFileCount += 1
                omittedByteCount += size
                continue
            }

            let documentation = Self.isDocumentation(path)
            let manifest = Self.isManifest(path)
            files.append(RepositoryFile(path: path, size: size, isDocumentation: documentation, isManifest: manifest))
            totalBytes += size
        }

        let tree = Self.makeTree(files)
        return RepositoryStructure(
            rootURL: rootURL,
            revision: revision,
            files: files,
            documentation: files.filter(\.isDocumentation),
            manifests: files.filter(\.isManifest),
            tree: tree,
            omittedFileCount: omittedFileCount,
            omittedByteCount: omittedByteCount
        )
    }

    private func git(_ arguments: [String], in directory: URL) async throws -> String {
        try Task.checkCancellation()
        let processBox = ProcessCancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                processBox.process = process
                let stdout = Pipe()
                let stderr = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + arguments
                process.currentDirectoryURL = directory
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: RepositoryStructureServiceError.gitFailed(command: arguments.joined(separator: " "), message: errorText.trimmingCharacters(in: .whitespacesAndNewlines)))
                        return
                    }
                    continuation.resume(returning: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.terminate()
        }
    }

    private static func isDocumentation(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return name == "readme" || name.hasPrefix("readme.") || name == "changelog" || name.hasPrefix("changelog.") || name == "license" || name.hasPrefix("license.") || ["md", "mdx", "rst", "txt", "adoc"].contains(URL(fileURLWithPath: name).pathExtension)
    }

    private static func isManifest(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "cargo.toml", "cargo.lock", "podfile", "podfile.lock", "cartfile", "project.yml", "project.json", "dockerfile", "docker-compose.yml", "docker-compose.yaml", "makefile", "package.swift"].contains(name) || name.hasSuffix(".xcodeproj")
    }

    private static func makeTree(_ files: [RepositoryFile]) -> RepositoryTreeNode {
        final class MutableNode {
            let name: String
            let path: String
            let kind: RepositoryTreeNode.Kind
            var size: Int64?
            var children: [String: MutableNode] = [:]
            init(name: String, path: String, kind: RepositoryTreeNode.Kind, size: Int64? = nil) { self.name = name; self.path = path; self.kind = kind; self.size = size }
        }
        let root = MutableNode(name: "", path: "", kind: .directory)
        for file in files {
            var parent = root
            var currentPath = ""
            let components = file.path.split(separator: "/").map(String.init)
            for (index, component) in components.enumerated() {
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
                let kind: RepositoryTreeNode.Kind = index == components.count - 1 ? .file : .directory
                let node = parent.children[component] ?? MutableNode(name: component, path: currentPath, kind: kind, size: kind == .file ? file.size : nil)
                parent.children[component] = node
                parent = node
            }
        }
        func freeze(_ node: MutableNode) -> RepositoryTreeNode {
            RepositoryTreeNode(name: node.name, path: node.path, kind: node.kind, size: node.size, children: node.children.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(freeze))
        }
        return freeze(root)
    }
}

private final class ProcessCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Process?

    var process: Process? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }

    func terminate() {
        process?.terminate()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }; return body()
    }
}
