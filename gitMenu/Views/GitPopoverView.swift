import SwiftUI
import AppKit

struct GitPopoverView: View {
    let store: GitMenuStore
    var isExpandedLayout: Bool = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            RepositoryListView(
                repositories: store.repositories,
                selectedRepositoryID: store.selectedRepositoryID,
                isImportingRepository: store.isImportingRepository,
                onSelect: store.selectRepository,
                onOpenRepository: openRepository,
                onBrowseRemoteRepository: openRemoteRepository,
                onCloneRepository: cloneRepository
            )

            Divider()
                .overlay(Color.white.opacity(0.06))

            if let repository = store.selectedRepository {
                VStack(spacing: 0) {
                    toolbar(for: repository)
                    GitGraphView(
                        repository: repository,
                        store: store,
                        commits: store.visibleCommits,
                        workingTreeStatus: repository.workingTreeStatus
                    )
                }
            } else if store.isImportingRepository {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)

                    Text(store.importProgressText)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 28))

                    Text("No Repositories")
                        .font(.system(size: 18, weight: .semibold))

                    Text("Open a local repository or browse a remote Git URL to see commit history here.")
                        .font(.system(size: 13.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)

                    Button(action: openRepository) {
                        Label("Open Repository…", systemImage: "folder.badge.plus")
                            .font(.system(size: 13.5, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer
        }
        .padding(8)
        .background(
            CommandKeyMonitor {
                openRepository()
            }
        )
        .alert("Couldn’t Add Repository", isPresented: Binding(
            get: { store.importErrorMessage != nil },
            set: { if !$0 { store.clearImportError() } }
        )) {
            Button("OK", role: .cancel) {
                store.clearImportError()
            }
        } message: {
            Text(store.importErrorMessage ?? "Please choose a valid Git repository.")
        }
    }

    @ViewBuilder
    private func toolbar(for repository: Repository) -> some View {
        HStack(spacing: 8) {
            Text(repository.name)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            Picker("Branch", selection: Binding(
                get: { store.selectedBranchName },
                set: { store.selectBranch($0) }
            )) {
                Text(GitMenuStore.allBranchesName).tag(GitMenuStore.allBranchesName)
                ForEach(store.selectedBranches) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .pickerStyle(.menu)
            
            .tint(GitLaneColor.main.color)
            .disabled(store.isImportingRepository)

            if repository.source.isRemote {
                toolbarButton(systemName: "arrow.clockwise", action: store.refreshSelectedRepository)
                    .help("Fetch remote history")
                    .disabled(store.isImportingRepository)
            } else {
                Image(systemName: "bolt.badge.clock")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
                    .help("Local repositories refresh automatically")
            }
/*
            toolbarButton(systemName: "line.3.horizontal.decrease", action: {})
                .disabled(store.isImportingRepository)
            toolbarButton(systemName: "arrow.up.left.and.arrow.down.right", action: openExpandedWindow)
 */
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.selectedBranchName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if store.isImportingRepository {
                ProgressView()
                    .controlSize(.small)

                Text(store.importProgressText)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.green.opacity(0.85))
                    .frame(width: 6, height: 6)

                Text(store.selectedRepository?.updatedText ?? "Updated just now")
                    .font(.system(size: 11.5))
                    .lineLimit(1)
            }

            Spacer()
/*
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.plain)
*/
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func toolbarButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 22, height: 22)
               
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.84))
    }

    private func openExpandedWindow() {
        if isExpandedLayout {
            return
        }

        openWindow(id: "main")
    }

    private func openRepository() {
        guard !store.isImportingRepository,
              let url = RepositoryOpenPanel.chooseRepository(
                startingAt: panelStartingDirectory
              ) else {
            return
        }

        store.addRepository(from: url)
    }

    private func cloneRepository() {
        guard !store.isImportingRepository,
              let remoteURL = RemoteRepositoryPrompt.requestURL(mode: .clone),
              let destinationURL = RepositoryOpenPanel.chooseCloneDestination(
                startingAt: panelStartingDirectory?.deletingLastPathComponent()
              ) else {
            return
        }

        store.cloneRepository(from: remoteURL, into: destinationURL)
    }

    private func openRemoteRepository() {
        guard !store.isImportingRepository,
              let remoteURL = RemoteRepositoryPrompt.requestURL(mode: .browse) else {
            return
        }

        store.addRemoteRepository(from: remoteURL)
    }

    private var panelStartingDirectory: URL? {
        guard let repository = store.selectedRepository,
              !repository.source.isRemote else {
            return nil
        }

        return repository.url
    }
}

#Preview {
    GitPopoverView(store: GitMenuStore(service: GitService.mock))
        .frame(width: 500, height: 720)
}
