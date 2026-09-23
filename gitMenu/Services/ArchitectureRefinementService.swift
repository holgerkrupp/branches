import Foundation

public protocol ArchitectureRefinementService: Sendable {
    func refine(_ architecture: RepositoryArchitecture) async throws -> RepositoryArchitecture
}

/// Safe baseline for machines without Apple Intelligence. It preserves the
/// deterministic graph and its source evidence exactly.
public struct NoOpArchitectureRefinementService: ArchitectureRefinementService, Sendable {
    public init() {}
    public func refine(_ architecture: RepositoryArchitecture) async throws -> RepositoryArchitecture { try Task.checkCancellation(); return architecture }
}

public struct ValidatingArchitectureRefinementService: ArchitectureRefinementService, Sendable {
    private let refinement: any ArchitectureRefinementService
    public init(refinement: any ArchitectureRefinementService) { self.refinement = refinement }
    public func refine(_ architecture: RepositoryArchitecture) async throws -> RepositoryArchitecture {
        do {
            let candidate = try await refinement.refine(architecture)
            let ids = Set(architecture.components.map(\.id))
            guard Set(candidate.components.map(\.id)).isSubset(of: ids) else { return architecture }
            guard candidate.relationships.allSatisfy({ ids.contains($0.sourceID) && ids.contains($0.targetID) }) else { return architecture }
            let paths = Set(architecture.components.flatMap(\.sourcePaths))
            guard candidate.components.allSatisfy({ Set($0.sourcePaths).isSubset(of: paths) }) else { return architecture }
            return candidate
        } catch { return architecture }
    }
}
