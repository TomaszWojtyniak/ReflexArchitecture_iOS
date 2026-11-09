import Foundation

/// Answers one command line at a time against the focused node of the tree.
/// Text lines (`ls`, `do <Title> [json]`) get text answers; a line starting
/// with `{` is a JSON request and gets a one-line JSON answer.
public final class IntrospectionSession {
    private let root: any IntrospectionProviding
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(root: any IntrospectionProviding) {
        self.root = root
    }

    public func handle(_ line: String) -> String {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("{") { return handleJSON(line) }
        let (command, rest) = split(line)
        switch command {
        case "ls":
            let (node, actions) = focus()
            return """
                \(node.name)
                  state   \(json(node.state))
                  actions \(actions.map(\.label).joined(separator: ", "))
                """
        case "do":
            let (title, payload) = split(rest)
            return run(title, payload: payload.isEmpty ? nil : Data(payload.utf8)).map { "error: \($0)" } ?? "ok"
        default:
            return #"error: unknown command "\#(command)"; use ls or do <Action> [json]"#
        }
    }

    private func handleJSON(_ line: String) -> String {
        guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let command = request["cmd"] as? String
        else { return json(["error": #"a JSON request needs a "cmd""#]) }

        switch command {
        case "ls":
            let (node, actions) = focus()
            return json(Snapshot(name: node.name, state: node.state, actions: actions.map {
                Snapshot.Action(title: $0.title, fields: $0.fields)
            }))
        case "do":
            let payload = request["payload"].flatMap {
                try? JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed)
            }
            if let refusal = run(request["action"] as? String ?? "", payload: payload) {
                return json(["error": refusal])
            }
            return json(["ok": true])
        default:
            return json(["error": #"unknown command "\#(command)"; use ls or do <Action> [json]"#])
        }
    }

    /// The deepest node, and every action available there: its own first,
    /// then each ancestor's, nearest first; a title already taken is skipped.
    private func focus() -> (node: any IntrospectionNode, actions: [IntrospectionAction]) {
        var chain = [root.introspectionNode]
        while let child = chain[chain.count - 1].child { chain.append(child) }
        var taken = Set<String>()
        let actions = chain.reversed().flatMap(\.actions).filter { taken.insert($0.title).inserted }
        return (chain[chain.count - 1], actions)
    }

    /// Runs an available action. Returns why it was refused, or nil when it ran.
    private func run(_ title: String, payload: Data?) -> String? {
        let actions = focus().actions
        guard let action = actions.first(where: { $0.title == title }) else {
            return #"unknown action "\#(title)"; available: \#(actions.map(\.label).joined(separator: ", "))"#
        }
        do {
            try action.perform(payload)
            return nil
        } catch {
            return "\(action.title) expects {\(action.fields.joined(separator: ", "))}: \(reason(error))"
        }
    }

    private func reason(_ error: any Error) -> String {
        switch error as? DecodingError {
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
             .keyNotFound(_, let context), .dataCorrupted(let context):
            context.debugDescription
        default:
            "\(error)"
        }
    }

    // ponytail: states are plain Codable structs; only non-finite Doubles fail to encode, and they show as null.
    private func json(_ value: any Encodable) -> String {
        (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    /// "do Set {…}" → ("do", "Set {…}")
    private func split(_ text: String) -> (String, String) {
        let parts = text.split(separator: " ", maxSplits: 1)
        return (
            parts.first.map(String.init) ?? "",
            parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        )
    }
}

private struct Snapshot: Encodable {
    struct Action: Encodable {
        let title: String
        let fields: [String]
    }

    let name: String
    let state: any Encodable
    let actions: [Action]

    private enum CodingKeys: CodingKey { case name, state, actions }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(state, forKey: .state)
        try container.encode(actions, forKey: .actions)
    }
}
