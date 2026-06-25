import SwiftUI
import AppKit

struct RepositoryListView: View {
    let repositories: [Repository]
    let selectedRepositoryID: Repository.ID?
    let isImportingRepository: Bool
    let onSelect: (Repository) -> Void
    let onRemove: (Repository) -> Void
    let onOpenRepository: () -> Void
    let onBrowseRemoteRepository: () -> Void
    let onCloneRepository: () -> Void

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 8),
        GridItem(.flexible(minimum: 0), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Repositories")
                    .font(.system(size: 12.5, weight: .medium))

                Spacer()

                if isImportingRepository {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.top, 1)
            .padding(.horizontal, 4)

            if repositories.isEmpty {
                Text("No repositories added yet.")
                    .font(.system(size: 12))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(repositories) { repository in
                        repositoryCard(repository)
                    }
                }
                .padding(.horizontal, 4)
            }

            actionRow
                .padding(.horizontal, 4)
                .padding(.top, 1)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func repositoryCard(_ repository: Repository) -> some View {
        Button {
            onSelect(repository)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                repositoryIconView(for: repository)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(repository.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)

                        if repository.source.isRemote {
                            Image(systemName: "network")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(repository.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(repository.id == selectedRepositoryID ? GitLaneColor.main.color : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: repository.id == selectedRepositoryID ? 0 : 1)
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(repository.id == selectedRepositoryID ? Color.white.opacity(0.07) : Color.white.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from List", role: .destructive) {
                onRemove(repository)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            compactActionButton(
                title: "Open",
                symbolName: "folder.badge.plus",
                shortcut: "⌘O",
                action: onOpenRepository
            )
            .keyboardShortcut("o", modifiers: [.command])

            compactActionButton(
                title: "Remote",
                symbolName: "antenna.radiowaves.left.and.right",
                action: onBrowseRemoteRepository
            )

            compactActionButton(
                title: "Clone",
                symbolName: "network",
                action: onCloneRepository
            )
        }
        .disabled(isImportingRepository)
    }

    private func compactActionButton(
        title: String,
        symbolName: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 10.5, weight: .semibold))

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                if let shortcut {
                    Spacer(minLength: 0)

                    Text(shortcut)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func repositoryIconView(for repository: Repository) -> some View {
        switch repository.icon {
        case let .file(path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                fallbackIconView(.text("G", .main))
            }
        case let .symbol(systemName, color):
            fallbackIconView(.symbol(systemName, color))
        case let .text(text, color):
            fallbackIconView(.text(text, color))
        }
    }

    @ViewBuilder
    private func fallbackIconView(_ icon: RepositoryIcon) -> some View {
        switch icon {
        case let .text(text, color):
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay {
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                }
        case let .symbol(systemName, color):
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.color.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(color.color.opacity(0.5), lineWidth: 1)
                )
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color.color)
                }
        case let .file(path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
    }
}
