import SwiftUI

@main
struct DECtalkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 420, minHeight: 380)
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
