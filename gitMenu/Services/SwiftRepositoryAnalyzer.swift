import Foundation
#if SWIFT_PACKAGE
import GitMenuArchitecture
#endif

public protocol RepositoryAnalyzer: Sendable { func analyze(at url: URL, options: RepositoryAnalysisOptions) async throws -> RepositoryAnalysis }
public struct SwiftRepositoryAnalyzer: RepositoryAnalyzer, Sendable {
    public init() {}
    public func analyze(at url: URL, options: RepositoryAnalysisOptions = .init()) async throws -> RepositoryAnalysis {
        let root=url.resolvingSymlinksInPath().standardizedFileURL; var files:[RepositoryAnalysisFile]=[]; var omitted=0; var failed=0; var total:Int64=0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let e=FileManager.default.enumerator(at: root, includingPropertiesForKeys:keys, options:[.skipsHiddenFiles,.skipsPackageDescendants])
        while let item=e?.nextObject() as? URL {
            try Task.checkCancellation()
            let v=try? item.resourceValues(forKeys:Set(keys))
            if v?.isDirectory == true {
                if Self.excludedDirectoryNames.contains(item.lastPathComponent.lowercased()) { e?.skipDescendants() }
                continue
            }
            guard v?.isRegularFile==true else {continue}; let path=item.pathComponents.suffix(e?.level ?? 1).joined(separator:"/"); let ext=item.pathExtension.lowercased(); guard options.extensions.contains(ext) else {continue}; let size=Int64(v?.fileSize ?? 0); guard files.count<options.maxFileCount,size<=options.maxFileSizeBytes,total<=options.maxTotalBytes-size else {omitted += 1; continue}; total += size; do { files.append(Self.parse(path:path,text:try String(contentsOf:item,encoding:.utf8),ext:ext,maxReferences:options.maxReferencesPerFile)) } catch { failed += 1; files.append(RepositoryAnalysisFile(path:path,language:ext,error:error.localizedDescription)) }
        }
        return RepositoryAnalysis(rootURL:root,files:files.sorted{$0.path<$1.path},failedFileCount:failed,omittedFileCount:omitted)
    }
    private static let excludedDirectoryNames: Set<String> = ["build", "deriveddata", "node_modules", "pods"]
    private static func parse(path:String,text:String,ext:String,maxReferences:Int)->RepositoryAnalysisFile {
        let lines=text.components(separatedBy:.newlines); var symbols:[RepositorySymbol]=[]; var imports:[RepositoryImport]=[]; var refs:[RepositoryReference]=[]
        let decl=try! NSRegularExpression(pattern:#"\b(class|struct|enum|protocol|actor|func|extension)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([^\{]+))?"#); let imp=try! NSRegularExpression(pattern:#"^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)"#); let qual=try! NSRegularExpression(pattern:#"\b([A-Z][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)"#)
        for (i,line) in lines.enumerated() { let r=NSRange(line.startIndex..<line.endIndex,in:line); if let m=decl.firstMatch(in:line,range:r),let kr=Range(m.range(at:1),in:line),let nr=Range(m.range(at:2),in:line) { let kind=RepositorySymbol.Kind(rawValue:String(line[kr])) ?? .unknown; let name=String(line[nr]); let conformances=m.range(at:3).location == NSNotFound ? [] : (Range(m.range(at:3),in:line).map{String(line[$0]).split(separator:",").map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}} ?? []); symbols.append(RepositorySymbol(id:"\(path):\(kind.rawValue):\(name):\(i+1)",name:name,kind:kind,path:path,conformances:conformances,evidence:AnalysisEvidence(line:i+1,text:line.trimmingCharacters(in:.whitespaces),confidence:0.92))) }; if let m=imp.firstMatch(in:line,range:r),let nr=Range(m.range(at:1),in:line) { let n=String(line[nr]); imports.append(RepositoryImport(name:n,path:path,evidence:AnalysisEvidence(line:i+1,text:line.trimmingCharacters(in:.whitespaces),confidence:0.99))) }; if refs.count<maxReferences { for m in qual.matches(in:line,range:r) { if let a=Range(m.range(at:1),in:line),let b=Range(m.range(at:2),in:line) { refs.append(RepositoryReference(name:"\(line[a]).\(line[b])",path:path,evidence:AnalysisEvidence(line:i+1,text:line.trimmingCharacters(in:.whitespaces),confidence:0.65))) } } } }
        return RepositoryAnalysisFile(path:path,language:ext,symbols:symbols,imports:imports,references:refs)
    }
}
