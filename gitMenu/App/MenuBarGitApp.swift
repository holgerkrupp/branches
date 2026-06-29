import SwiftUI

@main
struct MenuBarGitApp: App {
    @AppStorage("recentRepositories") private var recentRepositoriesData: Data = Data()
    @AppStorage("gitHostAccounts") private var gitHostAccountsData: Data = Data()
    @State private var store: GitMenuStore
    @State private var credentialsStore: HostCredentialsStore
    @State private var subscriptionManager: SubscriptionManager

    init() {
        let persistedData = UserDefaults.standard.data(forKey: "recentRepositories")
            ?? UserDefaults.standard.data(forKey: "recentRepositoryBookmarks")
            ?? Data()
        let credentialsData = UserDefaults.standard.data(forKey: "gitHostAccounts") ?? Data()
        let subscriptionManager = SubscriptionManager()
        _store = State(
            initialValue: GitMenuStore(
                service: GitService.mock,
                subscriptionManager: subscriptionManager,
                persistedRepositoriesData: persistedData
            )
        )
        _credentialsStore = State(
            initialValue: HostCredentialsStore(persistedData: credentialsData)
        )
        _subscriptionManager = State(initialValue: subscriptionManager)
    }

    var body: some Scene {
        /*
        Window("gitMenu", id: "main") {
            ContentView(store: store, subscriptionManager: subscriptionManager)
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
            GitPopoverView(store: store, subscriptionManager: subscriptionManager)
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
                .task {
                    subscriptionManager.start()
                }
        }
        .menuBarExtraStyle(.window)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(
                credentialsStore: credentialsStore,
                subscriptionManager: subscriptionManager
            )
                .onChange(of: credentialsStore.persistedData, initial: true) { _, newValue in
                    gitHostAccountsData = newValue
                }
        }
    }
}
