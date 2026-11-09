import IntrospectionKit

extension InventoryDetailViewModel: IntrospectionProviding {
    public var introspectionNode: any IntrospectionNode { Node(viewModel: self) }

    private struct Node: IntrospectionNode {
        let viewModel: InventoryDetailViewModel
        let name = "InventoryDetail"
        var state: any Encodable { viewModel.state }
        var actions: [IntrospectionAction] {
            [
                IntrospectionAction("Increment") { viewModel.send(action: .increment) },
                IntrospectionAction("Decrement") { viewModel.send(action: .decrement) },
                IntrospectionAction("Save") { viewModel.send(action: .save) },
                IntrospectionAction("SetQuantity", input: SetQuantityInput.self) {
                    viewModel.send(action: .setQuantity($0.quantity))
                },
            ]
        }
    }
}

nonisolated struct SetQuantityInput: IntrospectionInput {
    let quantity: Int
    static let fields = ["quantity"]
}
