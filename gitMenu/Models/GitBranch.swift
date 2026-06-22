import SwiftUI

struct GitBranch: Identifiable, Hashable {
    let name: String
    let laneIndex: Int
    let color: GitLaneColor

    var id: String { name }
}
