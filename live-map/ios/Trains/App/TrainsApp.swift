import SwiftUI

@main
struct TrainsApp: App {
    @State private var store = LiveStore(config: .current)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .task { store.start() }
        }
    }
}
