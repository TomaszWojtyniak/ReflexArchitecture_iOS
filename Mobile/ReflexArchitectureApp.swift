import InventoryCore
import SwiftUI

@main
struct ReflexArchitectureApp: App {
    @State private var app = InventoryApp(http: URLSessionHTTPClient())

    var body: some Scene {
        WindowGroup {
            RootView(navigator: app.navigator)
        }
    }
}
