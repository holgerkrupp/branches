import XCTest
@testable import GitMenuArchitecture

final class ArchitectureLayoutEngineTests: XCTestCase {
    private let engine = ArchitectureLayoutEngine(horizontalSpacing: 40, verticalSpacing: 30, canvasPadding: 12)

    func testCycleTerminatesAndIsLaidOut() {
        let graph = ArchitectureGraph(
            nodes: ["a", "b", "c"].map { ArchitectureNode(id: $0) },
            edges: [ArchitectureEdge(source: "a", destination: "b"), ArchitectureEdge(source: "b", destination: "c"), ArchitectureEdge(source: "c", destination: "a")]
        )
        let layout = engine.layout(graph)
        XCTAssertEqual(layout.nodes.count, 3)
        XCTAssertTrue(layout.bounds.width > 0 && layout.bounds.height > 0)
        XCTAssertTrue(layout.nodes.allSatisfy { layout.bounds.contains($0.frame) })
    }

    func testDisconnectedFanInAndFanOutProduceStableOutput() {
        let nodes = ["root", "left", "right", "join", "orphan"].map { ArchitectureNode(id: $0) }
        let edges = [
            ArchitectureEdge(source: "root", destination: "left"),
            ArchitectureEdge(source: "root", destination: "right"),
            ArchitectureEdge(source: "left", destination: "join"),
            ArchitectureEdge(source: "right", destination: "join")
        ]
        let graph = ArchitectureGraph(nodes: nodes, edges: edges)
        let first = engine.layout(graph)
        let second = engine.layout(ArchitectureGraph(nodes: nodes.reversed(), edges: edges.reversed()))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.nodes.count, 5)
        XCTAssertEqual(first.edges.count, 4)
        XCTAssertEqual(first.node("root")?.layer, 0)
        XCTAssertEqual(first.node("join")?.layer, 2)
    }

    func testNestedGroupsEncloseDescendants() {
        let graph = ArchitectureGraph(
            nodes: [ArchitectureNode(id: "a"), ArchitectureNode(id: "b")],
            groups: [
                ArchitectureGroup(id: "inner", nodeIDs: ["a"], padding: 5),
                ArchitectureGroup(id: "outer", groupIDs: ["inner"], nodeIDs: ["b"], padding: 10)
            ]
        )
        let layout = engine.layout(graph)
        let inner = try! XCTUnwrap(layout.group("inner"))
        let outer = try! XCTUnwrap(layout.group("outer"))
        XCTAssertTrue(outer.frame.contains(inner.frame))
        XCTAssertTrue(outer.frame.contains(try! XCTUnwrap(layout.node("b")).frame))
    }

    func testEdgesHaveReadableOrthogonalRoutesAndBoundsIncludeRoutes() {
        let graph = ArchitectureGraph(
            nodes: [ArchitectureNode(id: "a"), ArchitectureNode(id: "b")],
            edges: [ArchitectureEdge(id: "ab", source: "a", destination: "b")]
        )
        let layout = engine.layout(graph)
        let edge = try! XCTUnwrap(layout.edges.first)
        XCTAssertEqual(edge.points.count, 4)
        XCTAssertEqual(edge.points.first, layout.node("a")!.frame.bottomCenter)
        XCTAssertEqual(edge.points.last, layout.node("b")!.frame.topCenter)
        XCTAssertTrue(edge.points.allSatisfy { layout.bounds.insetBy(dx: 0, dy: 0).contains($0) })
    }
}

private extension CGRect {
    var topCenter: CGPoint { CGPoint(x: midX, y: minY) }
    var bottomCenter: CGPoint { CGPoint(x: midX, y: maxY) }
}
