import SwiftUI

struct GitGraphLane: Hashable {
    let index: Int
    let color: GitLaneColor
}

enum GitLaneColor: String, CaseIterable, Hashable {
    case main
    case violet
    case green
    case amber
    case slate

    var color: Color {
        switch self {
        case .main:
            return Color(red: 0.27, green: 0.56, blue: 1.0)
        case .violet:
            return Color(red: 0.69, green: 0.36, blue: 0.97)
        case .green:
            return Color(red: 0.50, green: 0.85, blue: 0.36)
        case .amber:
            return Color(red: 1.0, green: 0.69, blue: 0.20)
        case .slate:
            return Color(red: 0.48, green: 0.55, blue: 0.63)
        }
    }
}
