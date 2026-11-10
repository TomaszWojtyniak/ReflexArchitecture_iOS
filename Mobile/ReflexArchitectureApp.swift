import InventoryCore
import SwiftUI
#if DEBUG
import IntrospectionKit
#endif

@main
struct ReflexArchitectureApp: App {
    @State private var app = InventoryApp(http: URLSessionHTTPClient())
    #if DEBUG
    @State private var server: IntrospectionServer?
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(tabs: app.tabs)
            #if DEBUG
                .task { startServer() }
            #endif
        }
    }

    #if DEBUG
    /// `nc localhost 7777` gives the same ls/do as the headless CLI, against the running app.
    private func startServer() {
        guard server == nil else { return }
        do {
            server = try IntrospectionServer(port: 7777, session: IntrospectionSession(root: app))
            server?.start()
        } catch {
            print("IntrospectionServer could not start: \(error)")
        }
    }
    #endif
}
