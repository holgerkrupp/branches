import Foundation
#if SWIFT_PACKAGE
import GitMenuArchitecture
#endif

public struct RepositoryArchitectureOptions: Sendable, Hashable { public var maxComponents:Int; public var maxRelationships:Int; public init(maxComponents:Int=200,maxRelationships:Int=500){self.maxComponents=max(1,maxComponents);self.maxRelationships=max(0,maxRelationships)} }
public protocol RepositoryArchitectureServiceProtocol: Sendable { func build(from analysis:RepositoryAnalysis, options:RepositoryArchitectureOptions) async throws -> RepositoryArchitecture }
public struct DeterministicRepositoryArchitectureService: RepositoryArchitectureServiceProtocol, Sendable {
    public init() {}
    public func build(from analysis:RepositoryAnalysis, options:RepositoryArchitectureOptions = .init()) async throws -> RepositoryArchitecture {
        try Task.checkCancellation(); var components:[ArchitectureComponent]=[]; var lookup:[String:String]=[:]
        for file in analysis.files.sorted(by:{$0.path<$1.path}) { for symbol in file.symbols.sorted(by:{$0.id<$1.id}) { let id="component:\(symbol.path):\(symbol.name)"; let kind=ArchitectureComponentKind(rawValue:symbol.kind.rawValue) ?? (symbol.kind == .protocol ? .module : .unknown); components.append(.init(id:id,name:symbol.name,kind:kind,sourcePaths:[symbol.path],layer:layer(path:symbol.path,kind:symbol.kind.rawValue))); lookup[symbol.name]=id } }
        if components.isEmpty { components=[.init(id:"component:repository",name:"Repository",kind:.group,sourcePaths:analysis.files.map(\.path).sorted(),layer:"unknown")] }
        var relationships:[ArchitectureRelationship]=[]; var seen=Set<String>()
        for file in analysis.files { guard let source=file.symbols.first.map({"component:\($0.path):\($0.name)"}) else {continue}; for ref in file.references { let name=String(ref.name.split(separator:".").first ?? ""); guard let target=lookup[name], target != source else {continue}; let id="relationship:\(source)->\(target):references"; if seen.insert(id).inserted { relationships.append(.init(id:id,sourceID:source,targetID:target,kind:.references,explanation:ref.evidence.text,evidencePaths:[ref.path])) } } }
        let cs=components.sorted{$0.id<$1.id}, rs=relationships.sorted{$0.id<$1.id}; let c=Array(cs.prefix(options.maxComponents)), r=Array(rs.prefix(options.maxRelationships)); return RepositoryArchitecture(repositoryID:analysis.rootURL.path,revision:"",summary:"Deterministic source analysis",components:c,relationships:r)
    }
    private func layer(path:String,kind:String)->String { let p=path.lowercased(); if p.contains("test")||p.contains("spec"){return "test"}; if p.contains("view")||p.contains("ui"){return "presentation"}; if p.contains("model")||p.contains("domain"){return "domain"}; if p.contains("service")||p.contains("repository")||p.contains("client"){return "infrastructure"}; return kind=="protocol" ? "contract" : "application" }
}
public typealias RepositoryArchitectureService = DeterministicRepositoryArchitectureService
