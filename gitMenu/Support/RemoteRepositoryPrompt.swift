import AppKit

@MainActor
enum RemoteRepositoryPrompt {
    enum Mode {
        case browse
        case clone

        var title: String {
            switch self {
            case .browse:
                return "Open Remote Repository"
            case .clone:
                return "Clone Remote Repository"
            }
        }

        var message: String {
            switch self {
            case .browse:
                return "Enter an HTTPS or SSH Git URL to fetch and view commit history without cloning a working copy."
            case .clone:
                return "Enter an HTTPS or SSH Git URL from GitHub, GitLab, Codeberg, or another Git host."
            }
        }

        var actionTitle: String {
            switch self {
            case .browse:
                return "Open Remote"
            case .clone:
                return "Continue"
            }
        }
    }

    static func requestURL(mode: Mode) -> String? {
        let alert = NSAlert()
        alert.messageText = mode.title
        alert.informativeText = mode.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: mode.actionTitle)
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: suggestedURL)
        textField.placeholderString = "https://github.com/owner/repository.git"
        textField.frame = NSRect(x: 0, y: 0, width: 390, height: 24)
        alert.accessoryView = textField

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static var suggestedURL: String {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              value.contains("/") else {
            return ""
        }

        return value
    }
}
