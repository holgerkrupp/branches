import Foundation

struct WorkingTreeStatus: Hashable {
    let changeCount: Int

    var summaryText: String {
        if changeCount == 1 {
            return "1 uncommitted change"
        }

        return "\(changeCount) uncommitted changes"
    }
}
