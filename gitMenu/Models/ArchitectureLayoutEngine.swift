import Foundation
import CoreGraphics

/// A node used by `ArchitectureLayoutEngine`. These models intentionally contain
/// no view or rendering concerns; a renderer can translate the result to any UI.
public struct ArchitectureNode: Identifiable, Equatable {
    public let id: String
    public var size: CGSize
    public var layerHint: Int?

    public init(id: String, size: CGSize = CGSize(width: 120, height: 56), layerHint: Int? = nil) {
        self.id = id
        self.size = CGSize(width: max(1, size.width), height: max(1, size.height))
        self.layerHint = layerHint
    }
}

private func same(_ lhs: CGSize, _ rhs: CGSize) -> Bool { lhs.width == rhs.width && lhs.height == rhs.height }
private func same(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool { lhs.x == rhs.x && lhs.y == rhs.y }
private func same(_ lhs: CGRect, _ rhs: CGRect) -> Bool { same(lhs.origin, rhs.origin) && same(lhs.size, rhs.size) }

extension ArchitectureNode {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && same(lhs.size, rhs.size) && lhs.layerHint == rhs.layerHint }
}

public struct ArchitectureEdge: Identifiable, Equatable {
    public let id: String
    public let source: String
    public let destination: String

    public init(id: String? = nil, source: String, destination: String) {
        self.source = source
        self.destination = destination
        self.id = id ?? "\(source)->\(destination)"
    }
}

public struct ArchitectureGroup: Identifiable, Equatable {
    public let id: String
    public var nodeIDs: [String]
    public var groupIDs: [String]
    public var padding: CGFloat

    public init(id: String, groupIDs: [String] = [], nodeIDs: [String] = [], padding: CGFloat = 24) {
        self.id = id
        self.nodeIDs = nodeIDs
        self.groupIDs = groupIDs
        self.padding = max(0, padding)
    }
}

public struct ArchitectureGraph: Equatable {
    public var nodes: [ArchitectureNode]
    public var edges: [ArchitectureEdge]
    public var groups: [ArchitectureGroup]

    public init(nodes: [ArchitectureNode] = [], edges: [ArchitectureEdge] = [], groups: [ArchitectureGroup] = []) {
        self.nodes = nodes
        self.edges = edges
        self.groups = groups
    }
}

public struct ArchitectureNodeLayout: Identifiable, Equatable {
    public let id: String
    public let frame: CGRect
    public let layer: Int

    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && same(lhs.frame, rhs.frame) && lhs.layer == rhs.layer }
}

public struct ArchitectureGroupLayout: Identifiable, Equatable {
    public let id: String
    public let frame: CGRect

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && same(lhs.frame, rhs.frame) }
}

public struct ArchitectureEdgeLayout: Identifiable, Equatable {
    public let id: String
    public let source: String
    public let destination: String
    public let points: [CGPoint]

    public init(id: String, source: String, destination: String, points: [CGPoint]) {
        self.id = id
        self.source = source
        self.destination = destination
        self.points = points
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.destination == rhs.destination && lhs.points.count == rhs.points.count && zip(lhs.points, rhs.points).allSatisfy(same)
    }
}

public struct ArchitectureLayout: Equatable {
    public let nodes: [ArchitectureNodeLayout]
    public let groups: [ArchitectureGroupLayout]
    public let edges: [ArchitectureEdgeLayout]
    public let bounds: CGRect

    public init(nodes: [ArchitectureNodeLayout], groups: [ArchitectureGroupLayout], edges: [ArchitectureEdgeLayout], bounds: CGRect) {
        self.nodes = nodes
        self.groups = groups
        self.edges = edges
        self.bounds = bounds
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.nodes == rhs.nodes && lhs.groups == rhs.groups && lhs.edges == rhs.edges && same(lhs.bounds, rhs.bounds) }

    public func node(_ id: String) -> ArchitectureNodeLayout? { nodes.first { $0.id == id } }
    public func group(_ id: String) -> ArchitectureGroupLayout? { groups.first { $0.id == id } }
}

/// Deterministic layered layout for directed architecture graphs.
///
/// Strongly connected components are collapsed while assigning layers, so cycles
/// never cause an infinite traversal. Disconnected components are laid out from
/// left to right, and nested groups are expanded around their descendants.
public struct ArchitectureLayoutEngine {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    public var canvasPadding: CGFloat

    public init(horizontalSpacing: CGFloat = 80, verticalSpacing: CGFloat = 64, canvasPadding: CGFloat = 32) {
        self.horizontalSpacing = max(0, horizontalSpacing)
        self.verticalSpacing = max(0, verticalSpacing)
        self.canvasPadding = max(0, canvasPadding)
    }

    public func layout(_ graph: ArchitectureGraph) -> ArchitectureLayout {
        let nodes = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let edgesByID = Dictionary(graph.edges.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let validEdges = edgesByID.values.filter { nodes[$0.source] != nil && nodes[$0.destination] != nil }
            .sorted { ($0.source, $0.destination, $0.id) < ($1.source, $1.destination, $1.id) }
        guard !nodes.isEmpty else { return ArchitectureLayout(nodes: [], groups: [], edges: [], bounds: .zero) }

        let componentByNode = stronglyConnectedComponents(nodes: Array(nodes.keys).sorted(), edges: validEdges)
        let componentIDs = Set(componentByNode.values).sorted()
        var componentEdges = Set<Pair>()
        for edge in validEdges {
            let a = componentByNode[edge.source]!
            let b = componentByNode[edge.destination]!
            if a != b { componentEdges.insert(Pair(a, b)) }
        }
        let componentLayers = assignLayers(componentIDs: componentIDs, edges: componentEdges, nodes: nodes, componentByNode: componentByNode)

        var positions: [String: CGPoint] = [:]
        let layerGroups = Dictionary(grouping: nodes.keys) { componentLayers[componentByNode[$0]!] ?? 0 }
        var cursorY = canvasPadding
        for layer in layerGroups.keys.sorted() {
            let layerNodeIDs = layerGroups[layer]!.sorted { ($0, $1) < ($1, $0) }
            var cursorX = canvasPadding
            for id in layerNodeIDs {
                let node = nodes[id]!
                // A small stable offset for nodes in the same SCC makes cycles readable.
                let componentMembers = nodes.keys.filter { componentByNode[$0] == componentByNode[id] }.sorted()
                let memberOffset = CGFloat(componentMembers.firstIndex(of: id) ?? 0) * (verticalSpacing * 0.35)
                positions[id] = CGPoint(x: cursorX + node.size.width / 2, y: cursorY + node.size.height / 2 + memberOffset)
                cursorX += node.size.width + horizontalSpacing
            }
            let maxHeight = layerNodeIDs.map { nodes[$0]!.size.height }.max() ?? 0
            cursorY += maxHeight + verticalSpacing
        }

        // Barycentric refinement reduces crossings without depending on hash order.
        for _ in 0..<3 {
            for layer in layerGroups.keys.sorted() {
                for id in layerGroups[layer]!.sorted() {
                    let neighbors = validEdges.flatMap { edge -> [String] in
                        if edge.source == id { return [edge.destination] }
                        if edge.destination == id { return [edge.source] }
                        return []
                    }.compactMap { positions[$0]?.x }
                    guard !neighbors.isEmpty else { continue }
                    positions[id]!.x = (positions[id]!.x + neighbors.reduce(0, +) / CGFloat(neighbors.count)) / 2
                }
            }
        }

        let nodeLayouts = nodes.keys.sorted().compactMap { id -> ArchitectureNodeLayout? in
            guard let center = positions[id] else { return nil }
            let node = nodes[id]!
            return ArchitectureNodeLayout(id: id, frame: CGRect(x: center.x - node.size.width / 2, y: center.y - node.size.height / 2, width: node.size.width, height: node.size.height), layer: componentLayers[componentByNode[id]!] ?? 0)
        }

        let groupLayouts = makeGroupLayouts(graph.groups, nodeLayouts: nodeLayouts)
        let edgeLayouts = validEdges.map { edge in
            route(edge, nodeLayouts: nodeLayouts, ordinal: validEdges.firstIndex(of: edge) ?? 0)
        }
        let rects = nodeLayouts.map(\.frame) + groupLayouts.map(\.frame) + edgeLayouts.flatMap { $0.points }.map { CGRect(origin: $0, size: .zero) }
        let union = rects.reduce(CGRect.null) { $0.union($1) }
        let bounds = union.isNull ? .zero : union.insetBy(dx: -canvasPadding, dy: -canvasPadding)
        return ArchitectureLayout(nodes: nodeLayouts, groups: groupLayouts, edges: edgeLayouts, bounds: bounds)
    }

    private struct Pair: Hashable { let a: Int; let b: Int; init(_ a: Int, _ b: Int) { self.a = a; self.b = b } }

    private func stronglyConnectedComponents(nodes: [String], edges: [ArchitectureEdge]) -> [String: Int] {
        var index = 0, stack: [String] = [], onStack = Set<String>(), indexes = [String: Int](), low = [String: Int](), result = [String: Int](), component = 0
        let outgoing = Dictionary(grouping: edges) { $0.source }
        func visit(_ v: String) {
            indexes[v] = index; low[v] = index; index += 1; stack.append(v); onStack.insert(v)
            for w in (outgoing[v] ?? []).map(\.destination).sorted() {
                if indexes[w] == nil { visit(w); low[v] = min(low[v]!, low[w]!) }
                else if onStack.contains(w) { low[v] = min(low[v]!, indexes[w]!) }
            }
            if low[v] == indexes[v] {
                repeat { let w = stack.removeLast(); onStack.remove(w); result[w] = component } while result[v] == nil
                component += 1
            }
        }
        for node in nodes where indexes[node] == nil { visit(node) }
        return result
    }

    private func assignLayers(componentIDs: [Int], edges: Set<Pair>, nodes: [String: ArchitectureNode], componentByNode: [String: Int]) -> [Int: Int] {
        var incoming = Dictionary(uniqueKeysWithValues: componentIDs.map { ($0, 0) })
        var outgoing = [Int: [Int]]()
        for edge in edges { outgoing[edge.a, default: []].append(edge.b); incoming[edge.b, default: 0] += 1 }
        var queue = componentIDs.filter { incoming[$0] == 0 }.sorted(), layers = Dictionary(uniqueKeysWithValues: componentIDs.map { ($0, 0) })
        while let current = queue.first { queue.removeFirst(); for next in (outgoing[current] ?? []).sorted() { layers[next] = max(layers[next] ?? 0, (layers[current] ?? 0) + 1); incoming[next]! -= 1; if incoming[next] == 0 { queue.append(next); queue.sort() } } }
        for id in componentIDs where !layers.keys.contains(id) { layers[id] = 0 }
        return layers
    }

    private func makeGroupLayouts(_ groups: [ArchitectureGroup], nodeLayouts: [ArchitectureNodeLayout]) -> [ArchitectureGroupLayout] {
        let frames = Dictionary(uniqueKeysWithValues: nodeLayouts.map { ($0.id, $0.frame) })
        let definitions = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var resolved = [String: CGRect](), resolving = Set<String>()
        func resolve(_ id: String) -> CGRect? {
            if let frame = resolved[id] { return frame }
            guard let group = definitions[id], !resolving.contains(id) else { return nil }
            resolving.insert(id)
            let members = group.nodeIDs.compactMap { frames[$0] } + group.groupIDs.compactMap(resolve)
            resolving.remove(id)
            guard let first = members.first else { return nil }
            let frame = members.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -group.padding, dy: -group.padding)
            resolved[id] = frame
            return frame
        }
        return definitions.keys.sorted().compactMap { id in
            guard let frame = resolve(id) else { return nil }
            return ArchitectureGroupLayout(id: id, frame: frame)
        }
    }

    private func route(_ edge: ArchitectureEdge, nodeLayouts: [ArchitectureNodeLayout], ordinal: Int) -> ArchitectureEdgeLayout {
        let byID = Dictionary(uniqueKeysWithValues: nodeLayouts.map { ($0.id, $0) }), source = byID[edge.source]!.frame, destination = byID[edge.destination]!.frame
        let start = CGPoint(x: source.midX, y: source.maxY), end = CGPoint(x: destination.midX, y: destination.minY)
        let offset = CGFloat((ordinal % 5) - 2) * 10
        let middleY = (start.y + end.y) / 2 + offset
        return ArchitectureEdgeLayout(id: edge.id, source: edge.source, destination: edge.destination, points: [start, CGPoint(x: start.x, y: middleY), CGPoint(x: end.x, y: middleY), end])
    }
}
