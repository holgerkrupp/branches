// swift-tools-version: 5.9
// A small package target makes the layout engine independently testable from the
// app target, whose existing UI code is intentionally not part of this module.
import PackageDescription

let package = Package(
    name: "GitMenuArchitecture",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GitMenuArchitecture", targets: ["GitMenuArchitecture"])],
    targets: [
        .target(name: "GitMenuArchitecture", path: "gitMenu/Models", sources: ["ArchitectureLayoutEngine.swift", "RepositoryStructure.swift", "ArchitectureDomain.swift", "RepositoryAnalysis.swift"]),
        .target(name: "RepositoryStructureService", dependencies: ["GitMenuArchitecture"], path: "gitMenu/Services", sources: ["RepositoryStructureService.swift", "SwiftRepositoryAnalyzer.swift"]),
        .testTarget(name: "GitMenuArchitectureTests", dependencies: ["GitMenuArchitecture", "RepositoryStructureService"], path: "Tests")
    ]
)
