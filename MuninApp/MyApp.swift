import SwiftUI

@main struct MyApp: App {
    @State private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 600)
        #endif
    }
}
