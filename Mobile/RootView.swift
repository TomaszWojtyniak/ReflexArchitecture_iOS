import InventoryCore
import SwiftUI

/// Navigation state lives in Core. SwiftUI mirrors it and reports swipe-backs; views never push.
struct RootView: View {
    let navigator: StackNavigator

    var body: some View {
        NavigationStack(path: Binding(
            get: { navigator.state.path },
            set: { navigator.send(action: .popTo(depth: $0.count)) }
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
