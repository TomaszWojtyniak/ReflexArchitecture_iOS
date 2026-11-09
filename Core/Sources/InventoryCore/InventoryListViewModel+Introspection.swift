import IntrospectionKit

extension InventoryListViewModel: IntrospectionProviding {
    public var introspectionNode: any IntrospectionNode { Node(viewModel: self) }

    private struct Node: IntrospectionNode {
        let viewModel: InventoryListViewModel
        let name = "InventoryList"
        var state: any Encodable { viewModel.state }
        var actions: [IntrospectionAction] {
            [
                IntrospectionAction("SelectProduct", input: SelectProductInput.self) {
                    viewModel.send(action: .selectProduct(id: $0.id))
                },
            ]
        }
    }
}

nonisolated struct SelectProductInput: IntrospectionInput {
    let id: Int
    static let fields = ["id"]
}
