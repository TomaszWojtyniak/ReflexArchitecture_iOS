import Observation

/// The tabs at the bottom of the screen. `report` (Zgłoś) is an action, not a destination:
/// selecting it opens the report sheet over the current tab.
nonisolated public enum MainTab: String, CaseIterable, Encodable, Sendable {
    case home, search, favorites, profile, report

    public var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .favorites: "Favorites"
        case .profile: "Profile"
        case .report: "Zgłoś"
        }
    }
}

/// The selected tab and the report sheet are Core state, like the stack: the CLI switches
/// tabs without a single view, and SwiftUI shows what Core decided.
@Observable
public final class TabNavigator: ViewModel {
    public struct State: Encodable {
        public var selected = MainTab.home
        public var isReportPresented = false
    }

    public enum Action {
        case selectTab(MainTab)
        case dismissReport  // Close, or the sheet swiped down
    }

    enum Message {
        case viewAction(Action)
    }

    public internal(set) var state = State()
    /// Home's stack lives as long as the app, so switching tabs never loses its screens.
    public let home: StackNavigator

    init(home: StackNavigator) {
        self.home = home
    }

    public func send(action: Action) { send(message: .viewAction(action)) }

    func update(state: inout State, message: Message) {
        switch message {
        case .viewAction(.selectTab(let tab)):
            guard !state.isReportPresented else { return }  // the sheet covers the tab bar
            if tab == .report {
                state.isReportPresented = true
            } else if tab != state.selected {
                state.selected = tab
            } else if tab == .home {
                home.send(action: .popTo(depth: 0))  // the selected tab tapped again: back to its first screen
            }
        case .viewAction(.dismissReport):
            state.isReportPresented = false
        }
    }
}
