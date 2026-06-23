import SwiftUI

struct CommitRowView: View {
    let commit: GitCommit
    let graphWidth: CGFloat
    let rowHeight: CGFloat
    let actionMenu: AnyView?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Color.clear
                .frame(width: graphWidth, height: rowHeight)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    /*
                    Text(commit.shortHash)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 64, alignment: .leading)
*/
                    Text(commit.message)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    
                }

                secondaryLine
                    .frame(height: 19, alignment: .leading)
            }

            Spacer()

            if let actionMenu {
                Menu {
                    actionMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isHovered ? .secondary : .tertiary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(0.055))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovered)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        if isHovered {
            HStack(spacing: 6) {
                Label(commit.author.isEmpty ? "Unknown author" : commit.author, systemImage: "person")

                if !commit.branchLabels.isEmpty {
                    Text("•")
                    Label(commit.branchLabels.joined(separator: ", "), systemImage: "arrow.triangle.branch")
                }

            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .transition(.opacity)
        } else if !commit.branchLabels.isEmpty {
            HStack(spacing: 6) {
                ForEach(commit.branchLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color(for: label))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(color(for: label).opacity(0.14))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(color(for: label).opacity(0.80), lineWidth: 1)
                                )
                        )
                }
                Spacer()
                Text(commit.dateText)
                    .font(.system(size: 11))
                    .frame(width: 78, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            commit.message,
            "commit \(commit.id)",
            "author \(commit.author.isEmpty ? "unknown" : commit.author)",
            "date \(commit.dateText)"
        ]
        if !commit.branchLabels.isEmpty {
            parts.append("branches \(commit.branchLabels.joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
    }

    private func color(for label: String) -> Color {
        if label.contains("sync") {
            return GitLaneColor.violet.color
        }
        if label.contains("ui") {
            return GitLaneColor.green.color
        }
        if label.contains("release") {
            return GitLaneColor.amber.color
        }
        return GitLaneColor.main.color
    }
}
