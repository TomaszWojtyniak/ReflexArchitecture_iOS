/// The root of the app's object tree. The iOS app and the CLI are two hosts that construct it.
public final class InventoryApp {
    public let navigator: StackNavigator

    public init(http: any HTTPClient) {
        let api = InventoryAPI(http: http)
        weak var stack: StackNavigator?
        let list = InventoryListViewModel(api: api) { stack?.push($0) }
        navigator = StackNavigator(root: .list(list))
        stack = navigator
    }
}
