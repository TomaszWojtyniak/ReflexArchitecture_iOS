import Foundation
import InventoryCore
import SwiftUI

/// Navigation state lives in Core. SwiftUI mirrors it and reports swipe-backs; views never push.
struct StackView: View {
    let navigator: StackNavigator
    @State private var firstSeen = FirstSeen()

    var body: some View {
        NavigationStack(path: Binding(
            get: {
                let path = navigator.state.path
                firstSeen.at = path.reduce(into: [:]) { seen, route in seen[route] = firstSeen.at[route] ?? .now }
                return path
            },
            set: { newPath in
                // SwiftUI writes back the stack it displays when a transition ends. When Core has
                // moved on meanwhile (an agent pushing faster than the animations), that write is
                // stale. A person can only pop screens that finished coming in, so a pop that would
                // remove a screen SwiftUI learned about less than 0.5 s ago is ignored.
                // ponytail: time-based; a navigation delegate reporting only interactive pops would be exact.
                let removed = navigator.state.path.dropFirst(newPath.count)
                let settled = removed.allSatisfy { route in
                    firstSeen.at[route].map { Date.now.timeIntervalSince($0) > 0.5 } ?? false
                }
                if settled { navigator.send(action: .popTo(depth: newPath.count)) }
            }
        )) {
            screen(navigator.state.root)
                .navigationDestination(for: Route.self) { screen($0) }
        }
    }

    @ViewBuilder private func screen(_ route: Route) -> some View {
        switch route {
        case .list(let viewModel): InventoryListView(viewModel: viewModel)
        case .detail(let viewModel): InventoryDetailView(viewModel: viewModel)
        }
    }
}

/// When SwiftUI first read each route from the binding. A plain class on purpose:
/// it is written during view updates and must never trigger one.
private final class FirstSeen {
    var at: [Route: Date] = [:]
}
