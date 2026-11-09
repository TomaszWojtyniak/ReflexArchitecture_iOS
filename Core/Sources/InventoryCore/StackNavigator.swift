import Observation

/// A screen on the navigation stack, hashable by identity so SwiftUI can use it as a path element.
nonisolated public enum Route: Hashable {
    case list(InventoryListViewModel)
    case detail(InventoryDetailViewModel)

    public static func == (lhs: Route, rhs: Route) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private var id: ObjectIdentifier {
        switch self {
        case .list(let viewModel): ObjectIdentifier(viewModel)
        case .detail(let viewModel): ObjectIdentifier(viewModel)
        }
    }
}

/// Navigation is state in Core: pushing a screen is a state change, so the CLI
/// can walk the whole app without a single view being created.
@Observable
public final class StackNavigator: ViewModel {
    public struct State {
        public let root: Route
        public var path: [Route] = []
    }

    public enum Action {
        case goBack
        case popTo(depth: Int)  // SwiftUI's path binding, when the user swipes back
    }

    enum Message {
        case viewAction(Action)
        case push(Route)
    }

    public internal(set) var state: State

    init(root: Route) {
        state = State(root: root)
    }

    public func send(action: Action) { send(message: .viewAction(action)) }

    func push(_ route: Route) { send(message: .push(route)) }

    func update(state: inout State, message: Message) {
        switch message {
        case .push(let route):
            state.path.append(route)
        case .viewAction(.goBack):
            if !state.path.isEmpty { state.path.removeLast() }
        case .viewAction(.popTo(let depth)):
            if (0..<state.path.count).contains(depth) { state.path.removeLast(state.path.count - depth) }
        }
    }
}
