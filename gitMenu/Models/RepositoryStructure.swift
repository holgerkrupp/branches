import Foundation

public struct RepositoryFile: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public let size: Int64
    public let isDocumentation: Bool
    public let isManifest: Bool

    public init(path: String, size: Int64, isDocumentation: Bool, isManifest: Bool) {
        self.path = path; self.size = size; self.isDocumentation = isDocumentation; self.isManifest = isManifest
    }

    public var id: String { path }
}

public struct RepositoryTreeNode: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case directory, file }

    public let name: String
    public let path: String
    public let kind: Kind
    public let size: Int64?
    public var children: [RepositoryTreeNode]

    public init(name: String, path: String, kind: Kind, size: Int64?, children: [RepositoryTreeNode]) {
        self.name = name; self.path = path; self.kind = kind; self.size = size; self.children = children
    }

    public var id: String { path }
}

public struct RepositoryStructure: Codable, Hashable, Sendable {
    public let rootURL: URL
    public let revision: String
    public let files: [RepositoryFile]
    public let documentation: [RepositoryFile]
    public let manifests: [RepositoryFile]
    public let tree: RepositoryTreeNode
    public let omittedFileCount: Int
    public let omittedByteCount: Int64

    public init(rootURL: URL, revision: String, files: [RepositoryFile], documentation: [RepositoryFile], manifests: [RepositoryFile], tree: RepositoryTreeNode, omittedFileCount: Int, omittedByteCount: Int64) {
        self.rootURL = rootURL; self.revision = revision; self.files = files; self.documentation = documentation; self.manifests = manifests; self.tree = tree; self.omittedFileCount = omittedFileCount; self.omittedByteCount = omittedByteCount
    }
}

typealias TrackedRepositoryFile = RepositoryFile
typealias RepositoryStructureFile = RepositoryFile
