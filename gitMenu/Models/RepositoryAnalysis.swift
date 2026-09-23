import Foundation

public struct AnalysisEvidence: Codable, Hashable, Sendable {
    public let line: Int; public let text: String; public let confidence: Double
    public init(line: Int, text: String, confidence: Double) { self.line = max(1,line); self.text = text; self.confidence = min(1,max(0,confidence)) }
}
public struct RepositorySymbol: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case `class`, `struct`, `enum`, `protocol`, `actor`, `function`, `extension`, unknown }
    public let id: String; public let name: String; public let kind: Kind; public let path: String; public let conformances: [String]; public let evidence: AnalysisEvidence
    public init(id: String, name: String, kind: Kind, path: String, conformances: [String] = [], evidence: AnalysisEvidence) { self.id=id; self.name=name; self.kind=kind; self.path=path; self.conformances=conformances; self.evidence=evidence }
}
public struct RepositoryImport: Codable, Hashable, Sendable, Identifiable {
    public let id: String; public let name: String; public let path: String; public let evidence: AnalysisEvidence
    public init(name: String, path: String, evidence: AnalysisEvidence) { self.name=name; self.path=path; self.id="\(path):import:\(name):\(evidence.line)"; self.evidence=evidence }
}
public struct RepositoryReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String; public let name: String; public let path: String; public let evidence: AnalysisEvidence
    public init(name: String, path: String, evidence: AnalysisEvidence) { self.name=name; self.path=path; self.id="\(path):reference:\(name):\(evidence.line)"; self.evidence=evidence }
}
public struct RepositoryAnalysisFile: Codable, Hashable, Sendable, Identifiable {
    public let path: String; public let language: String; public let symbols: [RepositorySymbol]; public let imports: [RepositoryImport]; public let references: [RepositoryReference]; public let error: String?
    public var id: String { path }
    public init(path: String, language: String, symbols: [RepositorySymbol]=[], imports: [RepositoryImport]=[], references: [RepositoryReference]=[], error: String?=nil) { self.path=path; self.language=language; self.symbols=symbols; self.imports=imports; self.references=references; self.error=error }
}
public struct RepositoryAnalysis: Codable, Hashable, Sendable {
    public let rootURL: URL; public let files: [RepositoryAnalysisFile]; public let failedFileCount: Int; public let omittedFileCount: Int
    public init(rootURL: URL, files: [RepositoryAnalysisFile], failedFileCount: Int=0, omittedFileCount: Int=0) { self.rootURL=rootURL; self.files=files; self.failedFileCount=failedFileCount; self.omittedFileCount=omittedFileCount }
}
public struct RepositoryAnalysisOptions: Sendable, Hashable {
    public var maxFileCount: Int; public var maxFileSizeBytes: Int64; public var maxTotalBytes: Int64; public var extensions: Set<String>; public var maxReferencesPerFile: Int
    public init(maxFileCount: Int=2000, maxFileSizeBytes: Int64=2*1024*1024, maxTotalBytes: Int64=20*1024*1024, extensions: Set<String>=["swift","m","mm","h","c","cc","cpp","ts","tsx","js","jsx","kt","java","rs","go"], maxReferencesPerFile: Int=100) { self.maxFileCount=max(0,maxFileCount); self.maxFileSizeBytes=max(0,maxFileSizeBytes); self.maxTotalBytes=max(0,maxTotalBytes); self.extensions=Set(extensions.map{$0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn:"."))}); self.maxReferencesPerFile=max(0,maxReferencesPerFile) }
}
