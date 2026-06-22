import Foundation

struct GitHostAccount: Identifiable, Hashable, Codable {
    enum Kind: String, CaseIterable, Codable, Hashable, Identifiable {
        case github
        case gitlab
        case codeberg
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .github:
                return "GitHub"
            case .gitlab:
                return "GitLab"
            case .codeberg:
                return "Codeberg"
            case .custom:
                return "Custom Host"
            }
        }

        var defaultURL: String {
            switch self {
            case .github:
                return "https://github.com"
            case .gitlab:
                return "https://gitlab.com"
            case .codeberg:
                return "https://codeberg.org"
            case .custom:
                return ""
            }
        }

        var symbolName: String {
            switch self {
            case .github:
                return "chevron.left.forwardslash.chevron.right"
            case .gitlab:
                return "diamond"
            case .codeberg:
                return "shield"
            case .custom:
                return "network"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var hostURL: String
    var username: String
    var token: String
    var note: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        kind: Kind,
        hostURL: String,
        username: String = "",
        token: String = "",
        note: String = "",
        isEnabled: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.hostURL = hostURL
        self.username = username
        self.token = token
        self.note = note
        self.isEnabled = isEnabled
    }

    var displayTitle: String {
        kind.title
    }

    var statusText: String {
        if isEnabled && !token.isEmpty {
            return username.isEmpty ? "Connected" : "Connected as \(username)"
        }

        return "Not connected"
    }
}
