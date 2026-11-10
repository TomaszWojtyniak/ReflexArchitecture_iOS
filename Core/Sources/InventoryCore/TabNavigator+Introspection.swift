import Foundation
import IntrospectionKit

extension TabNavigator: IntrospectionProviding {
    public var introspectionNode: any IntrospectionNode { Node(navigator: self) }

    /// Lends selectTab to every screen. Below it: the report sheet while it is open,
    /// otherwise the selected tab's screen.
    private struct Node: IntrospectionNode {
        let navigator: TabNavigator
        let name = "TabBar"
        var state: any Encodable { navigator.state }
        var actions: [IntrospectionAction] {
            [
                IntrospectionAction("selectTab", input: SelectTabInput.self) {
                    navigator.send(action: .selectTab($0.tab))
                },
            ]
        }
        var child: (any IntrospectionNode)? {
            if navigator.state.isReportPresented { return Sheet(navigator: navigator) }
            let tab = navigator.state.selected
            return tab == .home ? navigator.home.introspectionNode : Placeholder(tab: tab)
        }
    }

    /// Lends dismiss to the report, so dismiss exists only while the sheet is up.
    private struct Sheet: IntrospectionNode {
        let navigator: TabNavigator
        let name = "Sheet"
        var state: any Encodable { [String: String]() }
        var actions: [IntrospectionAction] {
            [IntrospectionAction("dismiss") { navigator.send(action: .dismissReport) }]
        }
        var child: (any IntrospectionNode)? { Placeholder(tab: .report) }
    }
}

/// Search, Favorites, Profile and the report sheet show an icon and their title, nothing else.
private struct Placeholder: IntrospectionNode {
    let tab: MainTab
    var name: String { tab.rawValue.capitalized }
    var state: any Encodable { ["title": tab.title] }
    var actions: [IntrospectionAction] { [] }
}

nonisolated struct SelectTabInput: IntrospectionInput {
    let tab: MainTab
    static let fields = ["tab"]

    private enum CodingKeys: CodingKey { case tab }

    /// An unknown tab is refused with the list of tabs, so whoever sent it can correct it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .tab)
        guard let tab = MainTab(rawValue: name) else {
            let tabs = MainTab.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .tab, in: container, debugDescription: #"unknown tab "\#(name)"; tabs: \#(tabs)"#)
        }
        self.tab = tab
    }
}
