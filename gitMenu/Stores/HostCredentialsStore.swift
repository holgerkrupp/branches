import Observation
import Foundation

@MainActor
@Observable
final class HostCredentialsStore {
    var accounts: [GitHostAccount] {
        didSet {
            persist()
        }
    }

    var persistedData: Data

    init(persistedData: Data = Data()) {
        self.persistedData = persistedData
        if let decodedAccounts = try? JSONDecoder().decode([GitHostAccount].self, from: persistedData),
           !decodedAccounts.isEmpty {
            self.accounts = decodedAccounts
        } else {
            self.accounts = Self.defaultAccounts
            persist()
        }
    }

    func binding(for id: GitHostAccount.ID) -> GitHostAccount? {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        return accounts[index]
    }

    func update(_ account: GitHostAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        accounts[index] = account
    }

    func addCustomHost() {
        accounts.append(
            GitHostAccount(
                kind: .custom,
                hostURL: "",
                note: "Self-hosted Forgejo, Gitea, Bitbucket Server, or another Git provider."
            )
        )
    }

    func remove(_ accountID: GitHostAccount.ID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }

        guard accounts[index].kind == .custom else {
            return
        }

        accounts.remove(at: index)
    }

    private func persist() {
        persistedData = (try? JSONEncoder().encode(accounts)) ?? Data()
    }

    private static let defaultAccounts: [GitHostAccount] = [
        GitHostAccount(
            kind: .github,
            hostURL: GitHostAccount.Kind.github.defaultURL,
            note: "Use a personal access token with repo read access."
        ),
        GitHostAccount(
            kind: .gitlab,
            hostURL: GitHostAccount.Kind.gitlab.defaultURL,
            note: "Use a personal or group access token for your GitLab instance."
        ),
        GitHostAccount(
            kind: .codeberg,
            hostURL: GitHostAccount.Kind.codeberg.defaultURL,
            note: "Use an access token with repository read permissions."
        )
    ]
}
