import Foundation

struct GitCommit: Identifiable, Hashable {
    let id: String
    let shortHash: String
    let message: String
    let author: String
    let dateText: String
    let graphPrefix: String
    let lane: Int
    let activeLanes: [GitGraphLane]
    let edges: [GitGraphEdge]
    let branchLabels: [String]
    let connectorPrefixesAfter: [String]
}
