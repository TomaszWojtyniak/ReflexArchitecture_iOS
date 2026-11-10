import Observation

@Observable
public final class InventoryDetailViewModel: ViewModel {
    public struct State: Encodable {
        public let productId: Int
        public let title: String
        public var stockCount: Int
        public var isSaving = false
        public var isSaved = false
        public var error: String?
    }

    public enum Action {
        case increment, decrement, save
        case setQuantity(Int)
    }

    enum Message {
        case viewAction(Action)
        case saved
        case saveFailed
    }

    static let stockRange = 0...999_999

    public internal(set) var state: State
    private let api: InventoryAPI
    private let onSaved: (Product) -> Void

    init(product: Product, api: InventoryAPI, onSaved: @escaping (Product) -> Void) {
        state = State(productId: product.id, title: product.title, stockCount: product.stock)
        self.api = api
        self.onSaved = onSaved
    }

    public func send(action: Action) { send(message: .viewAction(action)) }

    func update(state: inout State, message: Message) {
        switch message {
        case .viewAction(let action):
            guard !state.isSaving else { return }  // nothing changes while a save is in flight
            switch action {
            // Wrapping on purpose: stock from the backend can be Int.max/Int.min; the wrapped
            // result lands outside stockRange, so edit(_:to:) turns it into a no-op.
            case .increment: Self.edit(&state, to: state.stockCount &+ 1)
            case .decrement: Self.edit(&state, to: state.stockCount &- 1)
            case .setQuantity(let quantity): Self.edit(&state, to: quantity)
            case .save:
                state.isSaving = true
                state.error = nil
                let (id, stock) = (state.productId, state.stockCount)
                Task {
                    do {
                        try await api.save(id: id, stock: stock)
                        send(message: .saved)
                    } catch {
                        send(message: .saveFailed)
                    }
                }
            }
        case .saved:
            state.isSaving = false
            state.isSaved = true
            onSaved(Product(id: state.productId, title: state.title, stock: state.stockCount))
        case .saveFailed:
            state.isSaving = false
            state.error = "Couldn't save"
        }
    }

    /// Edits outside the stock range are no-ops, so no input can overflow.
    private static func edit(_ state: inout State, to stock: Int) {
        guard stockRange.contains(stock) else { return }
        state.stockCount = stock
        state.isSaved = false
    }
}
