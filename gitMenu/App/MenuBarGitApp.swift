import SwiftUI

@main
struct MenuBarGitApp: App {
    @AppStorage("recentRepositories") private var recentRepositoriesData: Data = Data()
    @AppStorage("gitHostAccounts") private var gitHostAccountsData: Data = Data()
    @State private var store: GitMenuStore
    @State private var credentialsStore: HostCredentialsStore

    init() {
        let persistedData = UserDefaults.standard.data(forKey: "recentRepositories")
            ?? UserDefaults.standard.data(forKey: "recentRepositoryBookmarks")
            ?? Data()
        let credentialsData = UserDefaults.standard.data(forKey: "gitHostAccounts") ?? Data()
        _store = State(
            initialValue: GitMenuStore(
                service: GitService.mock,
                persistedRepositoriesData: persistedData
            )
        )
        _credentialsStore = State(
            initialValue: HostCredentialsStore(persistedData: credentialsData)
        )
    }

    var body: some Scene {
        /*
        Window("gitMenu", id: "main") {
            ContentView(store: store)
                .persistedWindowSize(
                    widthKey: "mainWindowWidth",
                    heightKey: "mainWindowHeight",
                    defaultSize: CGSize(width: 780, height: 840),
                    minSize: CGSize(width: 720, height: 760),
                    maxSize: CGSize(width: 1440, height: 1400)
                )
                .onChange(of: store.persistedRepositoriesData, initial: true) { _, newValue in
                    recentRepositoriesData = newValue
                }
        }
        .windowResizability(.contentMinSize)
*/
        MenuBarExtra("gitMenu", image: "git-branch.symbols") {
            GitPopoverView(store: store)
                .persistedWindowSize(
                    widthKey: "menuPanelWidth",
                    heightKey: "menuPanelHeight",
                    defaultSize: CGSize(width: 500, height: 690),
                    minSize: CGSize(width: 440, height: 560),
                    maxSize: CGSize(width: 860, height: 1200)
                )
                .onChange(of: store.persistedRepositoriesData, initial: true) { _, newValue in
                    recentRepositoriesData = newValue
                }
        }
        .menuBarExtraStyle(.window)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(credentialsStore: credentialsStore)
                .onChange(of: credentialsStore.persistedData, initial: true) { _, newValue in
                    gitHostAccountsData = newValue
                }
        }
    }
}
