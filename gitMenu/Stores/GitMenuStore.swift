import Observation
import SwiftUI

@MainActor
@Observable
final class GitMenuStore {
    static let allBranchesName = "All Branches"

    var repositories: [Repository]
    var selectedRepositoryID: Repository.ID?
    var selectedBranchName: String = "All Branches"
    var importErrorMessage: String?
    var persistedRepositoriesData: Data
    var isImportingRepository = false
    var importProgressText = "Loading repository..."

    private let service: GitServiceProtocol
    private let subscriptionManager: SubscriptionManager
    private var securityScopedPaths: Set<String> = []
    private var refreshSignatures: [Repository.ID: String] = [:]
    private var repositoryChangeMonitor: RepositoryChangeMonitor?
    private var repositoryChangeDebounceTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private var repositoryViewVisibilityCount = 0
    private var isCheckingForRepositoryChanges = false

    init(
        service: GitServiceProtocol,
        subscriptionManager: SubscriptionManager,
        persistedRepositoriesData: Data = Data()
    ) {
        self.service = service
        self.subscriptionManager = subscriptionManager
        self.persistedRepositoriesData = persistedRepositoriesData
        self.repositories = []
        self.selectedRepositoryID = nil

        restoreInitialRepositories(from: persistedRepositoriesData)
    }

    var selectedRepository: Repository? {
        repositories.first(where: { $0.id == selectedRepositoryID }) ?? repositories.first
    }

    var selectedBranches: [GitBranch] {
        selectedRepository?.branches ?? []
    }

    var visibleCommits: [GitCommit] {
        selectedRepository?.commits ?? []
    }

    func selectRepository(_ repository: Repository) {
        selectedRepositoryID = repository.id
        selectedBranchName = Self.allBranchesName

        guard isRepositoryViewVisible else { return }
        updateRepositoryChangeMonitor()
        scheduleSelectedRepositoryRefresh(delay: .zero)
    }

    func selectBranch(_ branchName: String) {
        guard selectedBranchName != branchName else { return }
        selectedBranchName = branchName
        reloadSelectedRepository()
    }

    func refresh() {
        guard !repositories.isEmpty else {
            return
        }

        let canUseRemoteFeatures = subscriptionManager.canUseRemoteFeatures
        if !canUseRemoteFeatures,
           selectedRepository?.source.isRemote == true,
           !subscriptionManager.requestAccess(to: .refresh) {
            return
        }

        let repositories = self.repositories
        let selectedRepositoryID = self.selectedRepositoryID
        let activeBranchSelection = self.activeBranchSelection
        let service = self.service

        runBackgroundLoad(progressText: "Refreshing history...") { [weak self] in
            do {
                let refreshedRepositories = try await Task.detached(priority: .userInitiated) {
                    try repositories.map { repository in
                        if repository.source.isRemote, !canUseRemoteFeatures {
                            return repository
                        }

                        let branch = repository.id == selectedRepositoryID ? activeBranchSelection : nil
                        return try service.refreshRepository(repository, selectedBranch: branch)
                            .preservingIdentity(from: repository)
                    }
                }.value

                guard let self else { return }
                self.repositories = refreshedRepositories
                self.validateSelectedBranch()
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                self?.importErrorMessage = error.localizedDescription
            }
        }
    }

    func refreshSelectedRepository() {
        guard let selectedRepositoryID,
              let repositoryIndex = repositories.firstIndex(where: { $0.id == selectedRepositoryID }) else {
            return
        }

        let repository = repositories[repositoryIndex]
        if repository.source.isRemote,
           !subscriptionManager.requestAccess(to: .refresh) {
            return
        }
        let selectedBranch = activeBranchSelection
        let service = self.service
        let progressText = repository.source.isRemote ? "Fetching remote history..." : "Refreshing history..."

        runBackgroundLoad(progressText: progressText) { [weak self] in
            do {
                let refreshedRepository = try await Task.detached(priority: .userInitiated) {
                    try service.refreshRepository(repository, selectedBranch: selectedBranch)
                        .preservingIdentity(from: repository)
                }.value

                guard let self,
                      let refreshedIndex = self.repositories.firstIndex(where: { $0.id == selectedRepositoryID }) else {
                    return
                }

                self.repositories[refreshedIndex] = refreshedRepository
                self.validateSelectedBranch()
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                self?.importErrorMessage = error.localizedDescription
            }
        }
    }

    func addRepository(from url: URL) {
        guard !isImportingRepository else { return }

        let startedAccess = startAccessIfNeeded(for: url)
        let service = self.service

        runBackgroundLoad(progressText: "Loading repository...") { [weak self] in
            do {
                let repository = try await Task.detached(priority: .userInitiated) {
                    try service.openRepository(at: url, selectedBranch: nil)
                }.value

                guard let self else { return }
                _ = self.startAccessIfNeeded(for: repository.url)
                self.insertAndSelect(repository)
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                guard let self else { return }
                if startedAccess {
                    self.stopAccess(for: url)
                }
                self.importErrorMessage = error.localizedDescription
            }
        }
    }

    func addRemoteRepository(from remoteURL: String) {
        guard !isImportingRepository else { return }
        guard subscriptionManager.requestAccess(to: .browse) else { return }

        let service = self.service

        runBackgroundLoad(progressText: "Fetching remote history...") { [weak self] in
            do {
                let repository = try await Task.detached(priority: .userInitiated) {
                    try service.openRemoteRepository(from: remoteURL, selectedBranch: nil)
                }.value

                guard let self else { return }
                self.insertAndSelect(repository)
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                self?.importErrorMessage = error.localizedDescription
            }
        }
    }

    func cloneRepository(from remoteURL: String, into parentURL: URL) {
        guard !isImportingRepository else { return }
        guard subscriptionManager.requestAccess(to: .clone) else { return }

        let startedAccess = startAccessIfNeeded(for: parentURL)
        let service = self.service

        runBackgroundLoad(progressText: "Cloning repository...") { [weak self] in
            do {
                let repository = try await Task.detached(priority: .userInitiated) {
                    try service.cloneRepository(from: remoteURL, into: parentURL)
                }.value

                guard let self else { return }
                _ = self.startAccessIfNeeded(for: repository.url)
                self.insertAndSelect(repository)
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                guard let self else { return }
                if startedAccess {
                    self.stopAccess(for: parentURL)
                }
                self.importErrorMessage = error.localizedDescription
            }
        }
    }

    func removeRepository(_ repository: Repository) {
        guard let index = repositories.firstIndex(where: { $0.id == repository.id }) else {
            return
        }

        let removed = repositories.remove(at: index)

        if case .local = removed.source {
            stopAccess(for: removed.url)
        }

        refreshSignatures.removeValue(forKey: removed.id)

        if selectedRepositoryID == removed.id {
            selectedRepositoryID = repositories.first?.id
            selectedBranchName = Self.allBranchesName
        }

        persistRepositories()

        if isRepositoryViewVisible {
            updateRepositoryChangeMonitor()
            scheduleSelectedRepositoryRefresh(delay: .zero)
        }
    }

    func commitWorkingTree(message: String) {
        guard let repository = selectedRepository else { return }
        performRepositoryMutation(progressText: "Creating commit...", repository: repository) { service, repository in
            try service.commitAll(in: repository, message: message)
        }
    }

    func pullSelectedRepository() {
        guard let repository = selectedRepository else { return }
        guard subscriptionManager.requestAccess(to: .pull) else { return }
        let branch = repository.currentBranchName ?? "current branch"
        performRepositoryMutation(progressText: "Pulling \(branch)...", repository: repository) { service, repository in
            try service.pull(repository)
        }
    }

    func pushSelectedRepository() {
        guard let repository = selectedRepository else { return }
        guard subscriptionManager.requestAccess(to: .push) else { return }
        let branch = repository.currentBranchName ?? "current branch"
        performRepositoryMutation(progressText: "Pushing \(branch)...", repository: repository) { service, repository in
            try service.push(repository)
        }
    }

    func push(commitID: String, to branch: String) {
        guard let repository = selectedRepository else { return }
        guard subscriptionManager.requestAccess(to: .pushCommit) else { return }
        performRepositoryMutation(
            progressText: "Pushing \(String(commitID.prefix(7))) to \(branch)...",
            repository: repository
        ) { service, repository in
            try service.push(commitID: commitID, to: branch, in: repository)
        }
    }

    func checkout(branch: String) {
        guard let repository = selectedRepository else { return }
        performRepositoryMutation(progressText: "Checking out \(branch)...", repository: repository) { service, repository in
            try service.checkout(branch: branch, in: repository)
        }
    }

    func merge(branch: String) {
        guard let repository = selectedRepository else { return }
        performRepositoryMutation(progressText: "Merging \(branch)...", repository: repository) { service, repository in
            try service.merge(branch: branch, into: repository)
        }
    }

    func cherryPick(commitID: String) {
        guard let repository = selectedRepository else { return }
        performRepositoryMutation(progressText: "Cherry-picking commit...", repository: repository) { service, repository in
            try service.cherryPick(commitID: commitID, in: repository)
        }
    }

    func createBranch(named branch: String, from commitID: String) {
        guard let repository = selectedRepository else { return }
        performRepositoryMutation(progressText: "Creating branch...", repository: repository) { service, repository in
            try service.createBranch(named: branch, from: commitID, in: repository)
        }
    }

    func pullRequestURL(for sourceBranch: String) -> URL? {
        guard let repository = selectedRepository else { return nil }
        return service.pullRequestURL(for: repository, sourceBranch: sourceBranch)
    }

    func clearImportError() {
        importErrorMessage = nil
    }

    func repositoryViewDidAppear() {
        repositoryViewVisibilityCount += 1
        guard repositoryViewVisibilityCount == 1 else { return }

        updateRepositoryChangeMonitor()
        startAutoRefresh()
        scheduleSelectedRepositoryRefresh(delay: .zero)
    }

    func repositoryViewDidDisappear() {
        repositoryViewVisibilityCount = max(0, repositoryViewVisibilityCount - 1)
        guard !isRepositoryViewVisible else { return }

        repositoryChangeMonitor?.stopMonitoring()
        repositoryChangeMonitor = nil
        repositoryChangeDebounceTask?.cancel()
        repositoryChangeDebounceTask = nil
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    @discardableResult
    private func startAccessIfNeeded(for url: URL) -> Bool {
        let standardizedPath = url.standardizedFileURL.path

        if securityScopedPaths.contains(standardizedPath) {
            return false
        }

        let started = url.startAccessingSecurityScopedResource()
        if started {
            securityScopedPaths.insert(standardizedPath)
        }

        return started
    }

    private func stopAccess(for url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        guard securityScopedPaths.contains(standardizedPath) else { return }

        url.stopAccessingSecurityScopedResource()
        securityScopedPaths.remove(standardizedPath)
    }

    private var activeBranchSelection: String? {
        selectedBranchName == Self.allBranchesName ? nil : selectedBranchName
    }

    private func persistRepositories() {
        let references = repositories.compactMap { repository -> PersistedRepositoryReference? in
            switch repository.source {
            case .local:
                guard let bookmarkData = try? repository.url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) else {
                    return nil
                }

                return .local(bookmarkData: bookmarkData)
            case let .remote(remoteURL):
                return .remote(remoteURL: remoteURL)
            }
        }

        persistedRepositoriesData = (try? JSONEncoder().encode(references)) ?? Data()
    }

    private func reloadSelectedRepository() {
        guard let selectedRepositoryID,
              let repositoryIndex = repositories.firstIndex(where: { $0.id == selectedRepositoryID }) else {
            return
        }

        let repository = repositories[repositoryIndex]
        if repository.source.isRemote,
           !subscriptionManager.requestAccess(to: .refresh) {
            return
        }

        let selectedBranch = activeBranchSelection
        let service = self.service

        runBackgroundLoad(progressText: "Refreshing history...") { [weak self] in
            do {
                let refreshedRepository = try await Task.detached(priority: .userInitiated) {
                    try service.refreshRepository(repository, selectedBranch: selectedBranch)
                        .preservingIdentity(from: repository)
                }.value

                guard let self,
                      let refreshedIndex = self.repositories.firstIndex(where: { $0.id == selectedRepositoryID }) else {
                    return
                }

                self.repositories[refreshedIndex] = refreshedRepository
                self.validateSelectedBranch()
                self.captureRefreshSignatures()
                self.importErrorMessage = nil
            } catch {
                self?.importErrorMessage = error.localizedDescription
            }
        }
    }

    private func performRepositoryMutation(
        progressText: String,
        repository: Repository,
        action: @escaping @Sendable (GitServiceProtocol, Repository) throws -> Repository
    ) {
        let service = self.service
        let selectedRepositoryID = repository.id

        runBackgroundLoad(progressText: progressText) { [weak self] in
            do {
                let refreshedRepository = try await Task.detached(priority: .userInitiated) {
                    try action(service, repository)
                        .preservingIdentity(from: repository)
                }.value

                guard let self else { return }

                if let repositoryIndex = self.repositories.firstIndex(where: { $0.id == selectedRepositoryID }) {
                    self.repositories[repositoryIndex] = refreshedRepository
                } else {
                    self.insertAndSelect(refreshedRepository)
                }

                self.selectedRepositoryID = refreshedRepository.id
                self.validateSelectedBranch()
                self.captureRefreshSignatures()
                self.persistRepositories()
                self.importErrorMessage = nil
            } catch {
                self?.importErrorMessage = error.localizedDescription
            }
        }
    }

    private func insertAndSelect(_ repository: Repository) {
        if let existingIndex = repositories.firstIndex(where: { existingRepository in
            switch (existingRepository.source, repository.source) {
            case (.local, .local):
                return existingRepository.url == repository.url
            case let (.remote(existingURL), .remote(newURL)):
                return existingURL == newURL
            default:
                return false
            }
        }) {
            repositories[existingIndex] = repository
        } else {
            repositories.insert(repository, at: 0)
        }

        selectedRepositoryID = repository.id
        selectedBranchName = Self.allBranchesName

        if isRepositoryViewVisible {
            updateRepositoryChangeMonitor()
            scheduleSelectedRepositoryRefresh(delay: .zero)
        }
    }

    private func validateSelectedBranch() {
        guard selectedBranchName != Self.allBranchesName,
              let repository = selectedRepository,
              !repository.branches.contains(where: { $0.name == selectedBranchName }) else {
            return
        }

        selectedBranchName = Self.allBranchesName
    }

    private func runBackgroundLoad(
        progressText: String,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard !isImportingRepository else { return }

        isImportingRepository = true
        importProgressText = progressText

        Task { @MainActor in
            await operation()
            self.isImportingRepository = false
        }
    }

    private var isRepositoryViewVisible: Bool {
        repositoryViewVisibilityCount > 0
    }

    private func updateRepositoryChangeMonitor() {
        repositoryChangeMonitor?.stopMonitoring()
        repositoryChangeMonitor = nil

        guard isRepositoryViewVisible,
              let repository = selectedRepository,
              !repository.source.isRemote else {
            return
        }

        let monitor = RepositoryChangeMonitor { [weak self] in
            self?.scheduleSelectedRepositoryRefresh()
        }
        repositoryChangeMonitor = monitor
        monitor.startMonitoring(repository.url)
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshSelectedRepositoryIfNeeded()

                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
            }
        }
    }

    private func scheduleSelectedRepositoryRefresh(delay: Duration = .milliseconds(250)) {
        repositoryChangeDebounceTask?.cancel()
        repositoryChangeDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard let self else { return }
            await self.refreshSelectedRepositoryIfNeeded()
        }
    }

    private func refreshSelectedRepositoryIfNeeded() async {
        guard isRepositoryViewVisible,
              !isImportingRepository,
              !isCheckingForRepositoryChanges,
              let selectedRepositoryID,
              let repository = repositories.first(where: { $0.id == selectedRepositoryID }),
              !repository.source.isRemote else {
            return
        }

        isCheckingForRepositoryChanges = true
        defer { isCheckingForRepositoryChanges = false }

        let service = self.service
        let activeBranchSelection = self.activeBranchSelection
        let existingSignature = refreshSignatures[repository.id]

        do {
            let newSignature = try await Task.detached(priority: .utility) {
                try service.refreshSignature(for: repository)
            }.value

            guard newSignature != existingSignature else {
                return
            }

            let refreshedRepository = try await Task.detached(priority: .userInitiated) {
                try service.refreshRepository(repository, selectedBranch: activeBranchSelection)
                    .preservingIdentity(from: repository)
            }.value

            guard let repositoryIndex = repositories.firstIndex(where: { $0.id == selectedRepositoryID }) else {
                return
            }

            repositories[repositoryIndex] = refreshedRepository
            if let newSignature {
                refreshSignatures[selectedRepositoryID] = newSignature
            } else {
                refreshSignatures.removeValue(forKey: selectedRepositoryID)
            }
            validateSelectedBranch()
        } catch {
            // Automatic refresh is best-effort and should not interrupt the user.
        }
    }

    private func captureRefreshSignatures() {
        var signatures: [Repository.ID: String] = [:]

        for repository in repositories where !repository.source.isRemote {
            if let signature = try? service.refreshSignature(for: repository) {
                signatures[repository.id] = signature
            }
        }

        refreshSignatures = signatures
    }

    private func restoreInitialRepositories(from persistedRepositoriesData: Data) {
        guard !persistedRepositoriesData.isEmpty else {
            let loadedRepositories = service.loadRepositories()
            repositories = loadedRepositories
            selectedRepositoryID = loadedRepositories.first?.id
            captureRefreshSignatures()
            return
        }

        isImportingRepository = true
        importProgressText = "Loading repositories..."

        let service = self.service
        let resolvedReferences = resolvePersistedReferences(from: persistedRepositoriesData)
        let includeRemoteRepositories = subscriptionManager.canUseRemoteFeatures

        Task { [weak self] in
            let restoredRepositories = await Task.detached(priority: .userInitiated) {
                Self.loadPersistedRepositories(
                    from: resolvedReferences,
                    service: service,
                    includeRemoteRepositories: includeRemoteRepositories
                )
            }.value

            guard let self else { return }

            self.repositories = restoredRepositories.isEmpty ? service.loadRepositories() : restoredRepositories
            self.selectedRepositoryID = self.repositories.first?.id
            self.captureRefreshSignatures()
            self.isImportingRepository = false

            if self.isRepositoryViewVisible {
                self.updateRepositoryChangeMonitor()
                self.scheduleSelectedRepositoryRefresh(delay: .zero)
            }
        }
    }

    private func resolvePersistedReferences(from persistedRepositoriesData: Data) -> [ResolvedPersistedReference] {
        let references: [PersistedRepositoryReference]

        if let decodedReferences = try? JSONDecoder().decode([PersistedRepositoryReference].self, from: persistedRepositoriesData) {
            references = decodedReferences
        } else if let bookmarks = try? JSONDecoder().decode([PersistedRepositoryBookmark].self, from: persistedRepositoriesData) {
            references = bookmarks.map { PersistedRepositoryReference.local(bookmarkData: $0.bookmarkData) }
        } else {
            return []
        }

        var resolvedReferences: [ResolvedPersistedReference] = []

        for reference in references {
            switch reference {
            case let .local(bookmarkData):
                var isStale = false

                guard let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else {
                    continue
                }

                _ = startAccessIfNeeded(for: url)
                resolvedReferences.append(.local(url))
            case let .remote(remoteURL):
                resolvedReferences.append(.remote(remoteURL))
            }
        }

        return resolvedReferences
    }

    nonisolated private static func loadPersistedRepositories(
        from references: [ResolvedPersistedReference],
        service: GitServiceProtocol,
        includeRemoteRepositories: Bool
    ) -> [Repository] {
        var restoredRepositories: [Repository] = []

        for reference in references {
            switch reference {
            case let .local(url):
                if let repository = try? service.openRepository(at: url, selectedBranch: nil) {
                    restoredRepositories.append(repository)
                }
            case let .remote(remoteURL):
                guard includeRemoteRepositories else {
                    continue
                }

                if let repository = try? service.openRemoteRepository(from: remoteURL, selectedBranch: nil) {
                    restoredRepositories.append(repository)
                }
            }
        }

        return restoredRepositories
    }

}

private enum PersistedRepositoryReference: Codable {
    case local(bookmarkData: Data)
    case remote(remoteURL: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case bookmarkData
        case remoteURL
    }

    private enum Kind: String, Codable {
        case local
        case remote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .local:
            self = .local(bookmarkData: try container.decode(Data.self, forKey: .bookmarkData))
        case .remote:
            self = .remote(remoteURL: try container.decode(String.self, forKey: .remoteURL))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .local(bookmarkData):
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(bookmarkData, forKey: .bookmarkData)
        case let .remote(remoteURL):
            try container.encode(Kind.remote, forKey: .kind)
            try container.encode(remoteURL, forKey: .remoteURL)
        }
    }
}

private struct PersistedRepositoryBookmark: Codable {
    let bookmarkData: Data
}

private enum ResolvedPersistedReference: Sendable {
    case local(URL)
    case remote(String)
}
