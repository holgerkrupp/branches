// swift-tools-version: 5.9
// A small package target makes the layout engine independently testable from the
// app target, whose existing UI code is intentionally not part of this module.
import PackageDescription

let package = Package(
    name: "GitMenuArchitecture",
    platforms: [.macOS(.v13)],
    products: [.library(name: "GitMenuArchitecture", targets: ["GitMenuArchitecture"])],
    targets: [
        .target(name: "GitMenuArchitecture", path: "gitMenu/Models", sources: ["ArchitectureLayoutEngine.swift"]),
        .testTarget(name: "GitMenuArchitectureTests", dependencies: ["GitMenuArchitecture"], path: "Tests", sources: ["ArchitectureLayoutEngineTests.swift"])
    ]
)
