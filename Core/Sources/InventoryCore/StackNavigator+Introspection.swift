import IntrospectionKit

extension StackNavigator: IntrospectionProviding {
    public var introspectionNode: any IntrospectionNode { Node(navigator: self) }

    /// Lends goBack to whatever screen is on top; popTo stays a SwiftUI detail.
    private struct Node: IntrospectionNode {
        let navigator: StackNavigator
        let name = "Stack"
        var state: any Encodable { ["depth": navigator.state.path.count] }
        var actions: [IntrospectionAction] {
            [IntrospectionAction("goBack") { navigator.send(action: .goBack) }]
        }
        var child: (any IntrospectionNode)? { (navigator.state.path.last ?? navigator.state.root).node }
    }
}

private extension Route {
    @MainActor var node: any IntrospectionNode {
        switch self {
        case .list(let viewModel): viewModel.introspectionNode
        case .detail(let viewModel): viewModel.introspectionNode
        }
    }
}
