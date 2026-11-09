import Foundation

/// A screen (or a container of screens) seen from outside the app:
/// a name, its state as JSON, the actions it accepts, and the node below it.
@MainActor public protocol IntrospectionNode {
    var name: String { get }
    var state: any Encodable { get }
    var actions: [IntrospectionAction] { get }
    var child: (any IntrospectionNode)? { get }
}

extension IntrospectionNode {
    public var child: (any IntrospectionNode)? { nil }
}

@MainActor public protocol IntrospectionProviding: AnyObject {
    var introspectionNode: any IntrospectionNode { get }
}

/// The payload of an action that takes input; `fields` is what `ls` shows.
public protocol IntrospectionInput: Decodable {
    static var fields: [String] { get }
}

public struct IntrospectionAction {
    public let title: String
    public let fields: [String]
    let perform: @MainActor (Data?) throws -> Void

    public init(_ title: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.fields = []
        self.perform = { _ in perform() }
    }

    public init<Input: IntrospectionInput>(
        _ title: String, input: Input.Type, perform: @escaping @MainActor (Input) -> Void
    ) {
        self.title = title
        self.fields = Input.fields
        self.perform = { payload in
            guard let payload else { throw MissingPayload() }
            perform(try JSONDecoder().decode(Input.self, from: payload))
        }
    }

    /// `Title {a, b}`, the way `ls` and refusals show the action.
    var label: String { fields.isEmpty ? title : "\(title) {\(fields.joined(separator: ", "))}" }
}

struct MissingPayload: Error, CustomStringConvertible {
    var description: String { "no payload" }
}
