/// The one shape every screen (and the navigator) follows: actions in, state out.
///
/// - `State` holds everything the screen shows; views read it and nothing else.
/// - `Action` is the public surface, sent through `send(action:)`.
/// - `Message` is internal: `.viewAction(Action)` plus results coming back from services.
/// - `update(state:message:)` is the only writer of `state`. Effects start a `Task`
///   that reports back with `send(message:)`. `update` never reads `self.state`.
@MainActor protocol ViewModel: AnyObject {
    associatedtype State
    associatedtype Message
    var state: State { get set }
    func update(state: inout State, message: Message)
}

extension ViewModel {
    func send(message: Message) {
        update(state: &state, message: message)
    }
}
