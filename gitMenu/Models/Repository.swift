import Foundation

enum RepositorySource: Hashable, Codable, Sendable {
    case local
    case remote(remoteURL: String)

    nonisolated var remoteURL: String? {
        switch self {
        case .local:
            return nil
        case let .remote(remoteURL):
            return remoteURL
        }
    }

    nonisolated var isRemote: Bool {
        if case .remote = self {
            return true
        }

        return false
    }
}

enum RepositoryIcon: Hashable {
    case text(String, GitLaneColor)
    case symbol(String, GitLaneColor)
    case file(path: String)
}

struct Repository: Identifiable, Hashable {
    let id: UUID
    let source: RepositorySource
    let url: URL
    let name: String
    let path: String
    let icon: RepositoryIcon
    let branches: [GitBranch]
    let commits: [GitCommit]
    let workingTreeStatus: WorkingTreeStatus?
    let currentBranchName: String?
    let defaultBranchName: String?
    let originWebURL: URL?
    let updatedText: String

    nonisolated init(
        id: UUID = UUID(),
        source: RepositorySource = .local,
        url: URL,
        name: String,
        path: String,
        icon: RepositoryIcon,
        branches: [GitBranch],
        commits: [GitCommit],
        workingTreeStatus: WorkingTreeStatus? = nil,
        currentBranchName: String? = nil,
        defaultBranchName: String? = nil,
        originWebURL: URL? = nil,
        updatedText: String = "Updated just now"
    ) {
        self.id = id
        self.source = source
        self.url = url
        self.name = name
        self.path = path
        self.icon = icon
        self.branches = branches
        self.commits = commits
        self.workingTreeStatus = workingTreeStatus
        self.currentBranchName = currentBranchName
        self.defaultBranchName = defaultBranchName
        self.originWebURL = originWebURL
        self.updatedText = updatedText
    }

    nonisolated func preservingIdentity(from repository: Repository) -> Repository {
        Repository(
            id: repository.id,
            source: source,
            url: url,
            name: name,
            path: path,
            icon: icon,
            branches: branches,
            commits: commits,
            workingTreeStatus: workingTreeStatus,
            currentBranchName: currentBranchName,
            defaultBranchName: defaultBranchName,
            originWebURL: originWebURL,
            updatedText: updatedText
        )
    }
}
