import AppKit
import SwiftUI

struct GitGraphView: View {
    let repository: Repository
    let store: GitMenuStore
    @Bindable var subscriptionManager: SubscriptionManager
    let commits: [GitCommit]
    let workingTreeStatus: WorkingTreeStatus?
    private let graphWidth: CGFloat = 118
    private let rowHeight: CGFloat = 48

    private var rowCount: Int {
        commits.count + (workingTreeStatus == nil ? 0 : 1)
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                GitGraphCanvas(
                    commits: commits,
                    workingTreeStatus: workingTreeStatus,
                    rowHeight: rowHeight
                )
                    .frame(width: graphWidth, height: CGFloat(rowCount) * rowHeight)
                    .padding(.leading, 18)

                LazyVStack(alignment: .leading, spacing: 0) {
                    if let workingTreeStatus {
                        WorkingTreeRowView(
                            status: workingTreeStatus,
                            graphWidth: graphWidth,
                            rowHeight: rowHeight,
                            actionMenu: AnyView(workingTreeActionMenu)
                        )
                    }

                    ForEach(commits) { commit in
                        CommitRowView(
                            commit: commit,
                            graphWidth: graphWidth,
                            rowHeight: rowHeight,
                            actionMenu: AnyView(commitActionMenu(for: commit))
                        )
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.visible)
    }

    private var workingTreeActionMenu: some View {
        Group {
            if repository.source.isRemote {
                EmptyView()
            } else {
                Button("Commit Changes...", systemImage: "square.and.pencil") {
                    guard let message = TextInputPrompt.request(
                        title: "Commit Changes",
                        message: "Enter a commit message for the current working tree changes.",
                        placeholder: "Describe the change",
                        actionTitle: "Commit"
                    ) else {
                        return
                    }

                    store.commitWorkingTree(message: message)
                }

                Button("Reveal Repository in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([repository.url])
                }

                Divider()

                Button("Refresh", systemImage: "arrow.clockwise") {
                    store.refresh()
                }
            }
        }
    }

    private func commitActionMenu(for commit: GitCommit) -> some View {
        let localBranchLabels = commit.branchLabels.filter { label in
            repository.branches.contains(where: { $0.name == label })
        }
        let defaultBranchName = repository.defaultBranchName
        let currentBranchName = repository.currentBranchName

        return Group {
            Button("Copy Commit Hash", systemImage: "doc.on.doc") {
                copyToPasteboard(commit.id)
            }

            Button("Copy Commit Message", systemImage: "text.alignleft") {
                copyToPasteboard(commit.message)
            }

            if !repository.source.isRemote {
                Divider()

                if repository.hasRemote, !pushBranches(for: commit).isEmpty {
                    Menu("Push Commit", systemImage: "arrow.up.circle") {
                        ForEach(pushBranches(for: commit), id: \.self) { branch in
                            Button("To \(shortBranchName(branch))") {
                                pushCommit(commit.id, to: branch)
                            }
                        }
                    }
                    .disabled(store.isImportingRepository)
                }

                Button("Create Branch from Commit...", systemImage: "arrow.triangle.branch") {
                    guard let branchName = TextInputPrompt.request(
                        title: "Create Branch",
                        message: "Create a new branch at commit \(commit.shortHash).",
                        placeholder: "feature/new-branch",
                        actionTitle: "Create"
                    ) else {
                        return
                    }

                    store.createBranch(named: branchName, from: commit.id)
                }

                Button("Cherry-Pick Commit", systemImage: "square.stack.3d.up") {
                    store.cherryPick(commitID: commit.id)
                }
            }

            if !localBranchLabels.isEmpty {
                Divider()

                ForEach(localBranchLabels, id: \.self) { branch in
                    if branch != currentBranchName {
                        Button("Checkout \(branch)", systemImage: "arrow.right.circle") {
                            store.checkout(branch: branch)
                        }
                    }

                    if !repository.source.isRemote,
                       branch != currentBranchName {
                        Button("Merge \(branch)", systemImage: "arrow.triangle.merge") {
                            store.merge(branch: branch)
                        }
                    }

                    if let pullRequestURL = store.pullRequestURL(for: branch),
                       branch != defaultBranchName {
                        Button("Create Pull Request for \(branch)", systemImage: "rectangle.and.pencil.and.ellipsis") {
                            NSWorkspace.shared.open(pullRequestURL)
                        }
                    }
                }
            }
        }
    }

    private func pushBranches(for commit: GitCommit) -> [String] {
        var branches: [String] = []

        if store.selectedBranchName != GitMenuStore.allBranchesName,
           repository.branches.contains(where: { $0.name == store.selectedBranchName }) {
            branches.append(store.selectedBranchName)
        }

        branches.append(contentsOf: commit.branchLabels.filter { label in
            repository.branches.contains(where: { $0.name == label })
        })

        if let currentBranchName = repository.currentBranchName {
            branches.append(currentBranchName)
        }

        return branches.reduce(into: []) { uniqueBranches, branch in
            if !uniqueBranches.contains(branch) {
                uniqueBranches.append(branch)
            }
        }
    }

    private func shortBranchName(_ branch: String) -> String {
        guard branch.count > 24 else {
            return branch
        }

        return String(branch.prefix(21)) + "..."
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func pushCommit(_ commitID: String, to branch: String) {
        guard subscriptionManager.requestAccess(
            to: .pushCommit,
            onUnlock: { pushCommit(commitID, to: branch) }
        ) else {
            return
        }

        store.push(commitID: commitID, to: branch)
    }
}
