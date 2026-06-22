import SwiftUI

struct ContentView: View {
    let store: GitMenuStore

    var body: some View {
        GitPopoverView(store: store, isExpandedLayout: true)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview {
    ContentView(store: GitMenuStore(service: GitService.mock))
        .preferredColorScheme(.dark)
}
