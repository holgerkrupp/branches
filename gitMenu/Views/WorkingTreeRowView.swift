import SwiftUI

struct WorkingTreeRowView: View {
    let status: WorkingTreeStatus
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
                    Text("WORKTREE")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)

                    Text(status.summaryText)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(isHovered ? "Tracked changes not yet committed" : "Uncommitted")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(height: 19, alignment: .leading)
            }

            Spacer(minLength: 8)

            Text("Now")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

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
        .accessibilityLabel("\(status.summaryText), working tree")
    }
}
