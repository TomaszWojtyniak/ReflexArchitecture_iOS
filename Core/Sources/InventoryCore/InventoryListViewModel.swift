import Observation

@Observable
public final class InventoryListViewModel: ViewModel {
    public struct State: Encodable {
        public var products: [Product] = []
        public var isLoading = true
        public var error: String?
    }

    public enum Action {
        case selectProduct(id: Int)
    }

    enum Message {
        case viewAction(Action)
        case load
        case loaded([Product])
        case loadFailed
        case saved(Product)
    }

    public internal(set) var state = State()
    private let api: InventoryAPI
    private let push: (Route) -> Void

    /// Starts loading right away: no view lifecycle involved, so headless runs behave the same.
    init(api: InventoryAPI, push: @escaping (Route) -> Void) {
        self.api = api
        self.push = push
        send(message: .load)
    }

    public func send(action: Action) { send(message: .viewAction(action)) }

    func update(state: inout State, message: Message) {
        switch message {
        case .load:
            Task {
                do { send(message: .loaded(try await api.products())) } catch { send(message: .loadFailed) }
            }
        case .loaded(let products):
            state.isLoading = false
            state.products = products
        case .loadFailed:
            state.isLoading = false
            state.error = "Couldn't load products"
        case .viewAction(.selectProduct(let id)):
            guard let product = state.products.first(where: { $0.id == id }) else { return }
            push(.detail(InventoryDetailViewModel(product: product, api: api) { [weak self] saved in
                self?.send(message: .saved(saved))
            }))
        case .saved(let product):
            guard let index = state.products.firstIndex(where: { $0.id == product.id }) else { return }
            state.products[index].stock = product.stock
        }
    }
}
