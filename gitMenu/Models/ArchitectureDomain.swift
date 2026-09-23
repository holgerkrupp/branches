import Foundation

public struct RepositorySnapshot: Codable, Hashable, Sendable {
    public let repositoryID: String
    public let revision: String
    public let files: [RepositoryFile]
    public let tree: RepositoryTreeNode
    public let documentation: [RepositoryFile]
    public let manifests: [RepositoryFile]

    public init(repositoryID: String, revision: String, files: [RepositoryFile], tree: RepositoryTreeNode, documentation: [RepositoryFile] = [], manifests: [RepositoryFile] = []) {
        self.repositoryID = repositoryID
        self.revision = revision
        self.files = files
        self.tree = tree
        self.documentation = documentation
        self.manifests = manifests
    }
}

public enum ArchitectureComponentKind: String, Codable, Hashable, Sendable { case app, ui, state, service, domain, infrastructure, module, file, group, unknown }
public enum ArchitectureRelationshipKind: String, Codable, Hashable, Sendable { case imports, contains, conformsTo, dependsOn, references, inheritsFrom, unknown }

public struct ArchitectureComponent: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let kind: ArchitectureComponentKind
    public let summary: String
    public let sourcePaths: [String]
    public let parentID: String?
    public let layer: String
    public init(id: String, name: String, kind: ArchitectureComponentKind, summary: String = "", sourcePaths: [String] = [], parentID: String? = nil, layer: String = "unknown") { self.id = id; self.name = name; self.kind = kind; self.summary = summary; self.sourcePaths = sourcePaths; self.parentID = parentID; self.layer = layer }
}

public struct ArchitectureRelationship: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let sourceID: String
    public let targetID: String
    public let kind: ArchitectureRelationshipKind
    public let explanation: String?
    public let evidencePaths: [String]
    public init(id: String, sourceID: String, targetID: String, kind: ArchitectureRelationshipKind, explanation: String? = nil, evidencePaths: [String] = []) { self.id = id; self.sourceID = sourceID; self.targetID = targetID; self.kind = kind; self.explanation = explanation; self.evidencePaths = evidencePaths }
}

public struct RepositoryArchitecture: Codable, Hashable, Sendable {
    public static let schemaVersion = 1
    public let schema: Int
    public let repositoryID: String
    public let revision: String
    public let summary: String
    public let components: [ArchitectureComponent]
    public let relationships: [ArchitectureRelationship]
    public init(repositoryID: String, revision: String, summary: String = "", components: [ArchitectureComponent] = [], relationships: [ArchitectureRelationship] = [], schema: Int = RepositoryArchitecture.schemaVersion) { self.schema = schema; self.repositoryID = repositoryID; self.revision = revision; self.summary = summary; self.components = components; self.relationships = relationships }
}

public struct ArchitectureComponentChange: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let before: ArchitectureComponent?
    public let after: ArchitectureComponent?
    public init(id: String, before: ArchitectureComponent?, after: ArchitectureComponent?) { self.id = id; self.before = before; self.after = after }
}

public struct ArchitectureRelationshipChange: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let before: ArchitectureRelationship?
    public let after: ArchitectureRelationship?
    public init(id: String, before: ArchitectureRelationship?, after: ArchitectureRelationship?) { self.id = id; self.before = before; self.after = after }
}

public struct ArchitectureComparison: Codable, Hashable, Sendable {
    public let fromRevision: String
    public let toRevision: String
    public let addedComponents: [ArchitectureComponent]
    public let removedComponents: [ArchitectureComponent]
    public let changedComponents: [ArchitectureComponentChange]
    public let addedRelationships: [ArchitectureRelationship]
    public let removedRelationships: [ArchitectureRelationship]
    public let changedRelationships: [ArchitectureRelationshipChange]

    public init(from: RepositoryArchitecture, to: RepositoryArchitecture) {
        fromRevision = from.revision; toRevision = to.revision
        let oldComponents = Dictionary(uniqueKeysWithValues: from.components.map { ($0.id, $0) })
        let newComponents = Dictionary(uniqueKeysWithValues: to.components.map { ($0.id, $0) })
        let oldComponentIDs = Set(oldComponents.keys)
        let newComponentIDs = Set(newComponents.keys)
        addedComponents = newComponentIDs.subtracting(oldComponentIDs).sorted().compactMap { newComponents[$0] }
        removedComponents = oldComponentIDs.subtracting(newComponentIDs).sorted().compactMap { oldComponents[$0] }
        changedComponents = oldComponentIDs.intersection(newComponentIDs).sorted().compactMap { id in
            guard oldComponents[id] != newComponents[id] else { return nil }
            return ArchitectureComponentChange(id: id, before: oldComponents[id], after: newComponents[id])
        }
        let oldRelationships = Dictionary(uniqueKeysWithValues: from.relationships.map { ($0.id, $0) })
        let newRelationships = Dictionary(uniqueKeysWithValues: to.relationships.map { ($0.id, $0) })
        let oldRelationshipIDs = Set(oldRelationships.keys)
        let newRelationshipIDs = Set(newRelationships.keys)
        addedRelationships = newRelationshipIDs.subtracting(oldRelationshipIDs).sorted().compactMap { newRelationships[$0] }
        removedRelationships = oldRelationshipIDs.subtracting(newRelationshipIDs).sorted().compactMap { oldRelationships[$0] }
        changedRelationships = oldRelationshipIDs.intersection(newRelationshipIDs).sorted().compactMap { id in
            guard oldRelationships[id] != newRelationships[id] else { return nil }
            return ArchitectureRelationshipChange(id: id, before: oldRelationships[id], after: newRelationships[id])
        }
    }
}
