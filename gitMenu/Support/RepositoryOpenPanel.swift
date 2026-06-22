import AppKit

@MainActor
enum RepositoryOpenPanel {
    private static var isPresented = false

    static func chooseRepository(startingAt initialURL: URL? = nil) -> URL? {
        chooseDirectory(
            title: "Open Git Repository",
            message: "Choose a folder containing a Git repository.",
            prompt: "Open Repository",
            startingAt: initialURL?.deletingLastPathComponent()
        )
    }

    static func chooseCloneDestination(startingAt initialURL: URL? = nil) -> URL? {
        chooseDirectory(
            title: "Choose Clone Location",
            message: "Choose the parent folder where the remote repository should be cloned.",
            prompt: "Choose",
            startingAt: initialURL
        )
    }

    private static func chooseDirectory(
        title: String,
        message: String,
        prompt: String,
        startingAt initialURL: URL?
    ) -> URL? {
        guard !isPresented else { return nil }
        isPresented = true
        defer { isPresented = false }

        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = initialURL

        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
