import SwiftUI

struct ContentView: View {
    let store: GitMenuStore
    let subscriptionManager: SubscriptionManager

    var body: some View {
        GitPopoverView(
            store: store,
            subscriptionManager: subscriptionManager,
            isExpandedLayout: true
        )
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    let subscriptionManager = SubscriptionManager()
    ContentView(
        store: GitMenuStore(
            service: GitService.mock,
            subscriptionManager: subscriptionManager
        ),
        subscriptionManager: subscriptionManager
    )
        .preferredColorScheme(.dark)
}
