import Testing
@testable import IntrospectionKit

nonisolated struct SetInput: IntrospectionInput {
    let value: Int
    static let fields = ["value"]
}

/// A screen whose own goBack clashes with the one its container lends.
final class Leaf: IntrospectionProviding {
    var count = 0
    var log: [String] = []
    var introspectionNode: any IntrospectionNode { Node(leaf: self) }

    struct Node: IntrospectionNode {
        let leaf: Leaf
        let name = "Leaf"
        var state: any Encodable { ["count": leaf.count] }
        var actions: [IntrospectionAction] {
            [
                IntrospectionAction("Bump") { leaf.count += 1 },
                IntrospectionAction("Set", input: SetInput.self) { leaf.count = $0.value },
                IntrospectionAction("goBack") { leaf.log.append("leaf") },
            ]
        }
    }
}

/// A container lending two actions to whatever is below it.
final class Container: IntrospectionProviding {
    let leaf = Leaf()
    var log: [String] = []
    var introspectionNode: any IntrospectionNode { Node(container: self) }

    struct Node: IntrospectionNode {
        let container: Container
        let name = "Container"
        var state: any Encodable { ["depth": 1] }
        var actions: [IntrospectionAction] {
            [
                IntrospectionAction("goBack") { container.log.append("goBack") },
                IntrospectionAction("close") { container.log.append("close") },
            ]
        }
        var child: (any IntrospectionNode)? { container.leaf.introspectionNode }
    }
}

@Test func lsShowsTheDeepestNodeWithLentActions() {
    let session = IntrospectionSession(root: Container())
    #expect(session.handle("ls") == """
        Leaf
          state   {"count":0}
          actions Bump, Set {value}, goBack, close
        """)
}

@Test func doRunsFocusedAndLentActionsAndRefusesTheRest() {
    let root = Container()
    let session = IntrospectionSession(root: root)
    #expect(session.handle("do Bump") == "ok")
    #expect(root.leaf.count == 1)
    #expect(session.handle("do close") == "ok")
    #expect(session.handle("do goBack") == "ok")
    #expect(root.log == ["close"])        // the nearest goBack wins
    #expect(root.leaf.log == ["leaf"])
    #expect(session.handle("do Fly") == #"error: unknown action "Fly"; available: Bump, Set {value}, goBack, close"#)
    #expect(session.handle("dance").hasPrefix(#"error: unknown command "dance""#))
}

@Test func inputsAreDecodedOrRefusedBeforeTheyRun() {
    let root = Container()
    let session = IntrospectionSession(root: root)
    #expect(session.handle(#"do Set {"value": 7}"#) == "ok")
    #expect(root.leaf.count == 7)
    for bad in ["do Set", "do Set 40", #"do Set {"value": "x"}"#, #"do Set {"value": 1.5}"#] {
        #expect(session.handle(bad).hasPrefix("error: Set expects {value}"), "\(bad)")
    }
    #expect(root.leaf.count == 7)
}

@Test func jsonLinesGetJSONAnswers() {
    let root = Container()
    let session = IntrospectionSession(root: root)
    #expect(session.handle(#"{"cmd":"ls"}"#) == #"{"actions":[{"fields":[],"title":"Bump"},{"fields":["value"],"title":"Set"},{"fields":[],"title":"goBack"},{"fields":[],"title":"close"}],"name":"Leaf","state":{"count":0}}"#)
    #expect(session.handle(#"{"cmd":"do","action":"Set","payload":{"value":3}}"#) == #"{"ok":true}"#)
    #expect(root.leaf.count == 3)
    #expect(session.handle(#"{"cmd":"do","action":"Fly"}"#) == #"{"error":"unknown action \"Fly\"; available: Bump, Set {value}, goBack, close"}"#)
}
