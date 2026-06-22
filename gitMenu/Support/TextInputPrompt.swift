import AppKit

@MainActor
enum TextInputPrompt {
    static func request(
        title: String,
        message: String,
        placeholder: String,
        defaultValue: String = "",
        actionTitle: String = "Continue"
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: defaultValue)
        textField.placeholderString = placeholder
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
}
