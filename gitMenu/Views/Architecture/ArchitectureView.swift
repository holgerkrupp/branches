import SwiftUI

struct ArchitectureView: View {
    let repository: Repository
    @State private var layout: ArchitectureLayout?
    @State private var selectedID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var zoom: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Architecture").font(.headline); Spacer(); if isLoading { ProgressView().controlSize(.small) }; Button("Regenerate", systemImage: "arrow.clockwise") { generate() }.disabled(isLoading); Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1 } }.padding(8)
            Divider()
            if let errorMessage { ContentUnavailableView("Analysis Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage)) }
            else if isLoading { ProgressView("Analyzing repository…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let layout { GeometryReader { proxy in ScrollView([.horizontal, .vertical]) { ArchitectureCanvas(layout: layout, selectedID: $selectedID).scaleEffect(zoom, anchor: .topLeading).frame(width: max(proxy.size.width, layout.bounds.width * zoom + 48), height: max(proxy.size.height, layout.bounds.height * zoom + 48), alignment: .topLeading).padding(24) } } }
            else { ContentUnavailableView("No Architecture Yet", systemImage: "square.3.layers.3d.down.right", description: Text("Generate an offline architecture diagram for this repository.")) }
        }.task { if layout == nil { generate() } }
    }
    private func generate() { isLoading = true; errorMessage = nil; let url = repository.url; Task { do { let result = try await Task.detached(priority: .userInitiated) { let analysis = try await SwiftRepositoryAnalyzer().analyze(at: url); let graph = try await DeterministicRepositoryArchitectureService().build(from: analysis); let nodes = graph.components.map { ArchitectureNode(id: $0.id) }; let edges = graph.relationships.map { ArchitectureEdge(id: $0.id, source: $0.sourceID, destination: $0.targetID) }; return ArchitectureLayoutEngine().layout(ArchitectureGraph(nodes: nodes, edges: edges)) }.value; layout = result } catch { errorMessage = error.localizedDescription }; isLoading = false } }
}

private struct ArchitectureCanvas: View {
    let layout: ArchitectureLayout
    @Binding var selectedID: String?
    var body: some View { ZStack(alignment: .topLeading) { Canvas { context, _ in for edge in layout.edges { var path = Path(); if let first = edge.points.first { path.move(to: first); for point in edge.points.dropFirst() { path.addLine(to: point) } }; context.stroke(path, with: .color(.secondary.opacity(0.55)), lineWidth: 1.5) } }; ForEach(layout.nodes) { node in RoundedRectangle(cornerRadius: 10).fill(node.id == selectedID ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15)).overlay(Text(node.id.replacingOccurrences(of: "component:", with: "")).font(.caption).lineLimit(2).padding(8)).frame(width: node.frame.width, height: node.frame.height).position(x: node.frame.midX, y: node.frame.midY).onTapGesture { selectedID = node.id } } }.frame(width: max(1, layout.bounds.width), height: max(1, layout.bounds.height)) }
}
