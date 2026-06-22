import Foundation

struct GitGraphEdge: Hashable {
    let fromLane: Int
    let toLane: Int
    let color: GitLaneColor
    let style: GitGraphEdgeStyle
}

enum GitGraphEdgeStyle: Hashable {
    case straight
    case branchOut
    case mergeIn
}
