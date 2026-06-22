import CryptoKit
import Foundation

nonisolated protocol GitServiceProtocol: Sendable {
    func loadRepositories() -> [Repository]
    func openRepository(at url: URL, selectedBranch: String?) throws -> Repository
    func openRemoteRepository(from remoteURL: String, selectedBranch: String?) throws -> Repository
    func cloneRepository(from remoteURL: String, into parentURL: URL) throws -> Repository
    func refreshRepository(_ repository: Repository, selectedBranch: String?) throws -> Repository
    func refreshSignature(for repository: Repository) throws -> String?
    func commitAll(in repository: Repository, message: String) throws -> Repository
    func checkout(branch: String, in repository: Repository) throws -> Repository
    func merge(branch: String, into repository: Repository) throws -> Repository
    func cherryPick(commitID: String, in repository: Repository) throws -> Repository
    func createBranch(named branch: String, from commitID: String, in repository: Repository) throws -> Repository
    func pullRequestURL(for repository: Repository, sourceBranch: String) -> URL?
}

nonisolated struct GitService: GitServiceProtocol, Sendable {
    enum Mode {
        case mock
    }

    static let mock = GitService(mode: .mock)

    private let mode: Mode
    private let gitExecutablePath: String

    init(mode: Mode) {
        self.mode = mode
        self.gitExecutablePath = GitBinaryResolver.resolve()
    }

    func loadRepositories() -> [Repository] {
        switch mode {
        case .mock:
            []
        }
    }
}

extension GitService {
    func openRepository(at url: URL, selectedBranch: String? = nil) throws -> Repository {
        let rootPath = try runGit(["rev-parse", "--show-toplevel"], in: url).trimmingCharacters(in: .whitespacesAndNewlines)
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        return try repository(
            at: rootURL,
            selectedBranch: selectedBranch,
            source: .local,
            displayPath: abbreviatedPath(for: rootURL),
            updatedText: "Updated just now",
            branchReferenceNamespace: "refs/heads",
            defaultBranchName: nil
        )
    }

    func openRemoteRepository(from remoteURL: String, selectedBranch: String? = nil) throws -> Repository {
        let normalizedURL = try normalizedRemoteURL(remoteURL)
        let cacheURL = try prepareRemoteCache(for: normalizedURL)
        let defaultBranchName = detectDefaultRemoteBranch(in: cacheURL)

        return try repository(
            at: cacheURL,
            selectedBranch: selectedBranch,
            source: .remote(remoteURL: normalizedURL),
            displayPath: displayPath(forRemoteURL: normalizedURL),
            updatedText: "Fetched just now",
            branchReferenceNamespace: "refs/remotes/origin",
            defaultBranchName: defaultBranchName
        )
    }

    func refreshRepository(_ repository: Repository, selectedBranch: String? = nil) throws -> Repository {
        switch repository.source {
        case .local:
            return try self.repository(
                at: repository.url,
                selectedBranch: selectedBranch,
                source: .local,
                displayPath: abbreviatedPath(for: repository.url),
                updatedText: "Updated just now",
                branchReferenceNamespace: "refs/heads",
                defaultBranchName: nil
            )
        case let .remote(remoteURL):
            let normalizedURL = try normalizedRemoteURL(remoteURL)
            let cacheURL = try prepareRemoteCache(for: normalizedURL)
            let defaultBranchName = detectDefaultRemoteBranch(in: cacheURL)

            return try self.repository(
                at: cacheURL,
                selectedBranch: selectedBranch,
                source: .remote(remoteURL: normalizedURL),
                displayPath: displayPath(forRemoteURL: normalizedURL),
                updatedText: "Fetched just now",
                branchReferenceNamespace: "refs/remotes/origin",
                defaultBranchName: defaultBranchName
            )
        }
    }

    func refreshSignature(for repository: Repository) throws -> String? {
        guard !repository.source.isRemote else {
            return nil
        }

        let branch = try runGit(["branch", "--show-current"], in: repository.url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let head = try runGit(["rev-parse", "HEAD"], in: repository.url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = try runGit(["status", "--porcelain"], in: repository.url)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return [branch, head, status].joined(separator: "\u{1F}")
    }

    func cloneRepository(from remoteURL: String, into parentURL: URL) throws -> Repository {
        let normalizedURL = try normalizedRemoteURL(remoteURL)
        let repositoryName = try repositoryName(from: normalizedURL)
        let destinationURL = parentURL.appendingPathComponent(repositoryName, isDirectory: true)

        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw GitServiceError.destinationAlreadyExists(repositoryName)
        }

        _ = try runGit(
            ["clone", "--", normalizedURL, destinationURL.path],
            in: parentURL,
            environment: fetchEnvironment
        )

        return try openRepository(at: destinationURL, selectedBranch: nil)
    }

    func commitAll(in repository: Repository, message: String) throws -> Repository {
        guard !repository.source.isRemote else {
            throw GitServiceError.readOnlyRepository
        }

        _ = try runGit(["add", "--all"], in: repository.url)
        _ = try runGit(["commit", "-m", message], in: repository.url)
        return try openRepository(at: repository.url, selectedBranch: nil)
    }

    func checkout(branch: String, in repository: Repository) throws -> Repository {
        guard !repository.source.isRemote else {
            throw GitServiceError.readOnlyRepository
        }

        _ = try runGit(["checkout", branch], in: repository.url)
        return try openRepository(at: repository.url, selectedBranch: nil)
    }

    func merge(branch: String, into repository: Repository) throws -> Repository {
        guard !repository.source.isRemote else {
            throw GitServiceError.readOnlyRepository
        }

        _ = try runGit(["merge", branch], in: repository.url)
        return try openRepository(at: repository.url, selectedBranch: nil)
    }

    func cherryPick(commitID: String, in repository: Repository) throws -> Repository {
        guard !repository.source.isRemote else {
            throw GitServiceError.readOnlyRepository
        }

        _ = try runGit(["cherry-pick", commitID], in: repository.url)
        return try openRepository(at: repository.url, selectedBranch: nil)
    }

    func createBranch(named branch: String, from commitID: String, in repository: Repository) throws -> Repository {
        guard !repository.source.isRemote else {
            throw GitServiceError.readOnlyRepository
        }

        _ = try runGit(["branch", branch, commitID], in: repository.url)
        return try openRepository(at: repository.url, selectedBranch: nil)
    }

    func pullRequestURL(for repository: Repository, sourceBranch: String) -> URL? {
        guard let originWebURL = repository.originWebURL else {
            return nil
        }

        let defaultBranch = repository.defaultBranchName ?? "main"
        guard !sourceBranch.isEmpty, sourceBranch != defaultBranch else {
            return nil
        }

        let host = originWebURL.host()?.lowercased() ?? ""

        if host.contains("gitlab") {
            var components = URLComponents(url: originWebURL.appendingPathComponent("-/merge_requests/new"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "merge_request[source_branch]", value: sourceBranch),
                URLQueryItem(name: "merge_request[target_branch]", value: defaultBranch)
            ]
            return components?.url
        }

        let comparePath = "\(defaultBranch)...\(sourceBranch)"
        if host.contains("github") {
            return originWebURL.appendingPathComponent("compare").appendingPathComponent(comparePath)
        }

        if host.contains("codeberg") || host.contains("gitea") || host.contains("forgejo") {
            return originWebURL.appendingPathComponent("compare").appendingPathComponent(comparePath)
        }

        return originWebURL.appendingPathComponent("compare").appendingPathComponent(comparePath)
    }
}

private extension GitService {
    var fetchEnvironment: [String: String] {
        [
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "ssh -o BatchMode=yes"
        ]
    }

    func normalizedRemoteURL(_ remoteURL: String) throws -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitServiceError.invalidRemoteURL
        }

        if trimmed.hasPrefix("git@") || trimmed.hasPrefix("ssh://") {
            return trimmed
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["https", "http", "git"].contains(scheme),
           url.host != nil {
            return trimmed
        }

        let knownHosts = ["github.com/", "gitlab.com/", "codeberg.org/"]
        if knownHosts.contains(where: { trimmed.lowercased().hasPrefix($0) }) {
            return "https://\(trimmed)"
        }

        throw GitServiceError.invalidRemoteURL
    }

    func repositoryName(from remoteURL: String) throws -> String {
        let trimmed = remoteURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathComponent = trimmed
            .split(separator: "/")
            .last
            .map(String.init)?
            .split(separator: ":")
            .last
            .map(String.init) ?? ""
        let name = pathComponent.hasSuffix(".git")
            ? String(pathComponent.dropLast(4))
            : pathComponent

        guard !name.isEmpty, name != ".", name != ".." else {
            throw GitServiceError.invalidRemoteURL
        }

        return name
    }

    func repository(
        at url: URL,
        selectedBranch: String? = nil,
        source: RepositorySource,
        displayPath: String,
        updatedText: String,
        branchReferenceNamespace: String,
        defaultBranchName: String?
    ) throws -> Repository {
        let displayName = source.remoteURL.flatMap(repositoryNameForDisplay(from:)) ?? url.lastPathComponent
        let branchNames = try loadBranchNames(in: url, namespace: branchReferenceNamespace)
        let currentBranch = inferredCurrentBranch(in: url, source: source)
        let resolvedDefaultBranchName = defaultBranchName ?? currentBranch
        let originWebURL = remoteWebURL(in: url, source: source)
        let branches = branchNames.enumerated().map { index, branchName in
            GitBranch(
                name: branchName,
                laneIndex: index,
                color: laneColor(for: index)
            )
        }

        let commits = try loadCommits(
            in: url,
            currentBranch: currentBranch,
            selectedBranch: selectedBranch,
            branchReferenceNamespace: branchReferenceNamespace
        )
        let workingTreeStatus = source.isRemote ? nil : loadWorkingTreeStatus(in: url)

        return Repository(
            source: source,
            url: url,
            name: displayName,
            path: displayPath,
            icon: repositoryIcon(for: url, source: source, displayName: displayName),
            branches: branches.isEmpty ? [GitBranch(name: currentBranch ?? "HEAD", laneIndex: 0, color: .main)] : branches,
            commits: commits,
            workingTreeStatus: workingTreeStatus,
            currentBranchName: currentBranch,
            defaultBranchName: resolvedDefaultBranchName,
            originWebURL: originWebURL,
            updatedText: updatedText
        )
    }

    func loadBranchNames(in url: URL, namespace: String) throws -> [String] {
        let output = try runGit(["for-each-ref", "--format=%(refname:short)", namespace], in: url)
        return output
            .split(whereSeparator: \.isNewline)
            .map { normalizedBranchName(String($0)) }
            .filter { !$0.isEmpty && $0 != "HEAD" }
    }

    func loadCommits(
        in url: URL,
        currentBranch: String?,
        selectedBranch: String?,
        branchReferenceNamespace: String
    ) throws -> [GitCommit] {
        var command = [
            "log",
            "--graph",
            "--date-order",
            "--topo-order",
            "--parents",
            "--decorate=short",
            "--date=short",
            "--pretty=format:%x1e%H%x1f%P%x1f%D%x1f%an%x1f%ad%x1f%s",
            "-n",
            "120"
        ]

        if let selectedBranch, !selectedBranch.isEmpty {
            command.append("\(branchReferenceNamespace)/\(selectedBranch)")
        } else {
            command.append("--all")
        }

        let output = try runGit(command, in: url)

        var commits: [GitCommit] = []
        var connectorPrefixes: [String] = []

        for line in output.split(whereSeparator: \.isNewline) {
            if line.contains("\u{1E}") {
                if !connectorPrefixes.isEmpty, !commits.isEmpty {
                    let lastCommit = commits.removeLast()
                    commits.append(
                        GitCommit(
                            id: lastCommit.id,
                            shortHash: lastCommit.shortHash,
                            message: lastCommit.message,
                            author: lastCommit.author,
                            dateText: lastCommit.dateText,
                            graphPrefix: lastCommit.graphPrefix,
                            lane: lastCommit.lane,
                            activeLanes: lastCommit.activeLanes,
                            edges: lastCommit.edges,
                            branchLabels: lastCommit.branchLabels,
                            connectorPrefixesAfter: connectorPrefixes
                        )
                    )
                    connectorPrefixes = []
                }

                guard let recordSeparatorIndex = line.firstIndex(of: "\u{1E}") else {
                    continue
                }

                let graphPrefix = String(line[..<recordSeparatorIndex])
                let payloadStart = line.index(after: recordSeparatorIndex)
                let payload = line[payloadStart...]
                let parts = payload.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 6 else {
                    continue
                }

                let hash = parts[0]
                let labels = parseLabels(parts[2])
                let nonPrimaryLabels = labels.filter { label in
                    label != currentBranch && label != "HEAD"
                }

                let displayLane = laneIndex(from: graphPrefix)
                let activeLanes = activeLanes(from: graphPrefix, fallbackLane: displayLane)

                commits.append(
                    GitCommit(
                        id: hash,
                        shortHash: String(hash.prefix(7)),
                        message: parts[5],
                        author: parts[3],
                        dateText: parts[4],
                        graphPrefix: graphPrefix,
                        lane: displayLane,
                        activeLanes: activeLanes,
                        edges: [],
                        branchLabels: nonPrimaryLabels.isEmpty ? Array(labels.prefix(1)) : nonPrimaryLabels,
                        connectorPrefixesAfter: []
                    )
                )
            } else {
                connectorPrefixes.append(String(line))
            }
        }

        if !connectorPrefixes.isEmpty, !commits.isEmpty {
            let lastCommit = commits.removeLast()
            commits.append(
                GitCommit(
                    id: lastCommit.id,
                    shortHash: lastCommit.shortHash,
                    message: lastCommit.message,
                    author: lastCommit.author,
                    dateText: lastCommit.dateText,
                    graphPrefix: lastCommit.graphPrefix,
                    lane: lastCommit.lane,
                    activeLanes: lastCommit.activeLanes,
                    edges: lastCommit.edges,
                    branchLabels: lastCommit.branchLabels,
                    connectorPrefixesAfter: connectorPrefixes
                )
            )
        }

        return commits
    }

    func loadWorkingTreeStatus(in url: URL) -> WorkingTreeStatus? {
        guard let output = try? runGit(["status", "--porcelain"], in: url) else {
            return nil
        }

        let count = output
            .split(whereSeparator: \.isNewline)
            .count

        guard count > 0 else {
            return nil
        }

        return WorkingTreeStatus(changeCount: count)
    }

    func parseLabels(_ decorationText: String) -> [String] {
        decorationText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { rawLabel in
                let label: String
                if rawLabel.hasPrefix("HEAD -> ") {
                    label = String(rawLabel.dropFirst("HEAD -> ".count))
                } else {
                    label = rawLabel
                }

                let normalizedLabel = normalizedDecorationLabel(label)
                if normalizedLabel.isEmpty || normalizedLabel == "HEAD" {
                    return nil
                }

                return normalizedLabel
            }
    }

    func laneIndex(from graphPrefix: String) -> Int {
        let characters = Array(graphPrefix)

        guard let starOffset = characters.firstIndex(of: "*") else {
            return 0
        }

        return min(max(starOffset / 2, 0), 5)
    }

    func activeLanes(from graphPrefix: String, fallbackLane: Int) -> [GitGraphLane] {
        let characters = Array(graphPrefix)
        var lanes: [GitGraphLane] = []

        for (offset, character) in characters.enumerated() where offset.isMultiple(of: 2) {
            guard character == "*" || character == "|" else {
                continue
            }

            let laneIndex = offset / 2
            lanes.append(GitGraphLane(index: laneIndex, color: laneColor(for: laneIndex)))
        }

        if lanes.isEmpty {
            lanes = [GitGraphLane(index: fallbackLane, color: laneColor(for: fallbackLane))]
        }

        return lanes
    }

    func runGit(_ arguments: [String], in url: URL, environment additions: [String: String] = [:]) throws -> String {
        try runGitRaw(["-C", url.path] + arguments, currentDirectory: nil, environment: additions)
    }

    func runGitRaw(
        _ arguments: [String],
        currentDirectory: URL? = nil,
        environment additions: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitExecutablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, newValue in
            newValue
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let outputCollector = PipeDataCollector()
        let errorCollector = PipeDataCollector()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCollector.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCollector.store(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()

        let outputData = outputCollector.data
        let errorData = errorCollector.data

        if process.terminationStatus != 0 {
            let errorMessage = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitServiceError.gitCommandFailed(errorMessage.isEmpty ? "Git command failed." : errorMessage)
        }

        return String(decoding: outputData, as: UTF8.self)
    }

    func abbreviatedPath(for url: URL) -> String {
        let fullPath = url.path
        let homePath = NSHomeDirectory()

        if fullPath.hasPrefix(homePath) {
            return "~" + fullPath.dropFirst(homePath.count)
        }

        return fullPath
    }

    func iconText(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalarPrefix = trimmed.prefix(2)
        return scalarPrefix.isEmpty ? "G" : scalarPrefix.uppercased()
    }

    func repositoryIcon(for url: URL, source: RepositorySource, displayName: String) -> RepositoryIcon {
        let fallbackText = RepositoryIcon.text(iconText(for: displayName), laneColor(for: 0))

        if source.isRemote {
            if let host = source.remoteURL.flatMap({ URL(string: $0)?.host?.lowercased() }) {
                if host.contains("github") {
                    return .symbol("chevron.left.forwardslash.chevron.right", .main)
                }
                if host.contains("gitlab") {
                    return .symbol("triangle", .amber)
                }
                if host.contains("codeberg") {
                    return .symbol("shippingbox.circle", .violet)
                }
            }
            return .symbol("network", .main)
        }

        if let appIcon = discoverXcodeAppIcon(in: url) {
            return .file(path: appIcon.path)
        }

        if fileExists(namedWithSuffix: ".xcodeproj", in: url) || fileExists(namedWithSuffix: ".xcworkspace", in: url) {
            return .symbol("hammer.circle.fill", .main)
        }

        if let androidIcon = discoverAndroidAppIcon(in: url) {
            return .file(path: androidIcon.path)
        }

        if fileExists(namedWithSuffix: ".uproject", in: url) {
            return .symbol("u.square.fill", .violet)
        }

        if fileExists(namedWithSuffix: ".unity", in: url) || fileExists(atRelativePath: "ProjectSettings/ProjectSettings.asset", in: url) {
            return .symbol("cube.transparent.fill", .main)
        }

        if fileExists(atRelativePath: "project.godot", in: url) {
            return .symbol("gamecontroller.fill", .green)
        }

        if fileExists(atRelativePath: "pubspec.yaml", in: url) {
            return .symbol("sparkles.square.filled.on.square", .main)
        }

        if fileExists(atRelativePath: "Package.swift", in: url) {
            return .symbol("shippingbox.fill", .amber)
        }

        return fallbackText
    }

    func laneColor(for index: Int) -> GitLaneColor {
        let palette: [GitLaneColor] = [.main, .green, .amber, .violet]
        return palette[index % palette.count]
    }

    func fileExists(namedWithSuffix suffix: String, in rootURL: URL) -> Bool {
        enumeratedPaths(in: rootURL, maximumDepth: 3).contains { $0.lastPathComponent.hasSuffix(suffix) }
    }

    func fileExists(atRelativePath relativePath: String, in rootURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(relativePath).path)
    }

    func discoverXcodeAppIcon(in rootURL: URL) -> URL? {
        let fileManager = FileManager.default

        for path in enumeratedPaths(in: rootURL, maximumDepth: 5) where path.lastPathComponent.hasSuffix(".appiconset") {
            if let png = bestRasterIcon(in: path) {
                return png
            }

            // Icon Composer exports may leave raster previews beside the composed asset.
            if let preview = bestMatchingFile(
                in: path,
                extensions: ["png", "jpg", "jpeg", "heic", "webp"],
                preferredNames: ["preview", "AppIcon", "Icon"]
            ) {
                return preview
            }

            // If the asset only contains a composed icon source, fall back to the project marker.
            if fileManager.contentsOfDirectoryExists(at: path, matchingExtension: "icon") ||
                fileManager.contentsOfDirectoryExists(at: path, matchingExtension: "iconcomposer") {
                return nil
            }
        }

        return nil
    }

    func discoverAndroidAppIcon(in rootURL: URL) -> URL? {
        let resCandidates = enumeratedPaths(in: rootURL, maximumDepth: 5).filter {
            $0.path.contains("/src/main/res/") || $0.path.contains("/app/src/main/res/")
        }

        let preferredNames = [
            "ic_launcher_round",
            "ic_launcher",
            "app_icon",
            "launcher"
        ]

        for resourceURL in resCandidates {
            if let icon = bestMatchingFile(
                in: resourceURL,
                extensions: ["png", "webp", "jpg", "jpeg"],
                preferredNames: preferredNames
            ) {
                return icon
            }
        }

        return nil
    }

    func bestRasterIcon(in directoryURL: URL) -> URL? {
        bestMatchingFile(
            in: directoryURL,
            extensions: ["png", "jpg", "jpeg", "heic", "webp"],
            preferredNames: ["AppIcon", "Icon", "appicon"]
        )
    }

    func bestMatchingFile(in directoryURL: URL, extensions: [String], preferredNames: [String]) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let filtered = contents.filter { url in
            extensions.contains(url.pathExtension.lowercased())
        }

        guard !filtered.isEmpty else {
            return nil
        }

        let preferred = filtered
            .sorted { lhs, rhs in
                iconSortKey(for: lhs, preferredNames: preferredNames) > iconSortKey(for: rhs, preferredNames: preferredNames)
            }
            .first

        return preferred
    }

    func iconSortKey(for url: URL, preferredNames: [String]) -> Int {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let preferredScore = preferredNames.enumerated().reduce(0) { partialResult, entry in
            let (index, candidate) = entry
            let loweredCandidate = candidate.lowercased()
            guard name.contains(loweredCandidate) else {
                return partialResult
            }

            return max(partialResult, 10_000 - index * 100)
        }

        let sizeScore = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return preferredScore + sizeScore
    }

    func enumeratedPaths(in rootURL: URL, maximumDepth: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []

        for case let url as URL in enumerator {
            let relativeDepth = url.pathComponents.count - rootURL.pathComponents.count
            if relativeDepth > maximumDepth {
                enumerator.skipDescendants()
                continue
            }

            urls.append(url)
        }

        return urls
    }

    func inferredCurrentBranch(in url: URL, source: RepositorySource) -> String? {
        switch source {
        case .local:
            return (try? runGit(["branch", "--show-current"], in: url).trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 }
        case .remote:
            return detectDefaultRemoteBranch(in: url)
        }
    }

    func detectDefaultRemoteBranch(in url: URL) -> String? {
        _ = try? runGit(["remote", "set-head", "origin", "-a"], in: url)
        let value = try? runGit(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.map(normalizedBranchName(_:))
    }

    func prepareRemoteCache(for remoteURL: String) throws -> URL {
        let cacheRoot = try remoteCacheRootURL()
        let cacheURL = cacheRoot.appendingPathComponent(remoteCacheFolderName(for: remoteURL), isDirectory: true)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            _ = try runGitRaw(["init", "--bare", cacheURL.path], currentDirectory: cacheRoot)
        }

        if (try? runGit(["remote", "get-url", "origin"], in: cacheURL)) == nil {
            _ = try runGit(["remote", "add", "origin", remoteURL], in: cacheURL)
        } else {
            _ = try runGit(["remote", "set-url", "origin", remoteURL], in: cacheURL)
        }

        _ = try runGit(
            ["fetch", "--prune", "--tags", "origin", "+refs/heads/*:refs/remotes/origin/*"],
            in: cacheURL,
            environment: fetchEnvironment
        )

        return cacheURL
    }

    func remoteCacheRootURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return baseURL
            .appendingPathComponent("gitMenu", isDirectory: true)
            .appendingPathComponent("RemoteCache", isDirectory: true)
    }

    func remoteCacheFolderName(for remoteURL: String) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let baseName = (try? repositoryName(from: remoteURL)) ?? "repository"
        return "\(baseName)-\(hash)"
    }

    func displayPath(forRemoteURL remoteURL: String) -> String {
        if let url = URL(string: remoteURL), let host = url.host {
            return host + url.path.replacingOccurrences(of: ".git", with: "")
        }

        if remoteURL.hasPrefix("git@"),
           let separatorIndex = remoteURL.firstIndex(of: ":") {
            let host = remoteURL[remoteURL.index(remoteURL.startIndex, offsetBy: 4)..<separatorIndex]
            let pathStart = remoteURL.index(after: separatorIndex)
            let path = remoteURL[pathStart...].replacingOccurrences(of: ".git", with: "")
            return "\(host)/\(path)"
        }

        return remoteURL.replacingOccurrences(of: ".git", with: "")
    }

    func repositoryNameForDisplay(from remoteURL: String) -> String? {
        try? repositoryName(from: remoteURL)
    }

    func remoteWebURL(in url: URL, source: RepositorySource) -> URL? {
        let remoteURL: String?

        switch source {
        case let .remote(sourceRemoteURL):
            remoteURL = sourceRemoteURL
        case .local:
            remoteURL = try? runGit(["remote", "get-url", "origin"], in: url)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let remoteURL, !remoteURL.isEmpty else {
            return nil
        }

        return webURL(from: remoteURL)
    }

    func webURL(from remoteURL: String) -> URL? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed), let host = url.host {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = url.path.hasSuffix(".git")
                ? String(url.path.dropLast(4))
                : url.path
            return components.url
        }

        guard trimmed.hasPrefix("git@"),
              let separatorIndex = trimmed.firstIndex(of: ":") else {
            return nil
        }

        let host = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<separatorIndex])
        let pathStart = trimmed.index(after: separatorIndex)
        let path = String(trimmed[pathStart...])
        let normalizedPath = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        return URL(string: "https://\(host)/\(normalizedPath)")
    }

    func normalizedBranchName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "origin/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedDecorationLabel(_ label: String) -> String {
        if label.hasPrefix("tag: ") {
            return String(label.dropFirst("tag: ".count))
        }

        if label == "origin/HEAD" {
            return ""
        }

        if label.hasPrefix("origin/") {
            return String(label.dropFirst("origin/".count))
        }

        return label
    }
}

nonisolated private final class PipeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData = Data()

    var data: Data {
        lock.withLock { storedData }
    }

    func store(_ data: Data) {
        lock.withLock {
            storedData = data
        }
    }
}

enum GitServiceError: LocalizedError {
    case gitCommandFailed(String)
    case gitBinaryUnavailable
    case invalidRemoteURL
    case destinationAlreadyExists(String)
    case readOnlyRepository

    var errorDescription: String? {
        switch self {
        case let .gitCommandFailed(message):
            return message
        case .gitBinaryUnavailable:
            return "No usable Git binary was found. Install Xcode or Command Line Tools."
        case .invalidRemoteURL:
            return "Enter a valid HTTPS or SSH Git repository URL."
        case let .destinationAlreadyExists(name):
            return "A folder named “\(name)” already exists at the selected location."
        case .readOnlyRepository:
            return "This action requires a local repository with a writable working copy."
        }
    }
}

nonisolated private enum GitBinaryResolver {
    static func resolve() -> String {
        let candidates = [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git"
        ]

        let fileManager = FileManager.default
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) ?? "/usr/bin/git"
    }
}

private extension FileManager {
    nonisolated func contentsOfDirectoryExists(at url: URL, matchingExtension pathExtension: String) -> Bool {
        guard let contents = try? contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }

        return contents.contains { $0.pathExtension.lowercased() == pathExtension.lowercased() }
    }
}
