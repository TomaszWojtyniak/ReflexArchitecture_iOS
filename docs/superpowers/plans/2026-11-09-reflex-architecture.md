# ReflexArchitecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A small iOS inventory app built on Shopify's Reflex architecture (headless Swift Core, strict ViewModels, introspection nodes, a CLI and JS behavior tests) plus live control of the simulator app over a local socket.

**Architecture:** A Swift package in `Core/` holds `IntrospectionKit` (node contract and the `ls`/`do` session), `InventoryCore` (ViewModels, navigator, API, HTTP edge) and the `inventory-cli` host. Behavior tests in `behavior/` spawn the CLI with fixtures and speak newline-delimited JSON to it. The SwiftUI app in `Mobile/` builds the same Core on the real network and, in Debug, serves the same protocol on port 7777.

**Tech Stack:** Swift 6.4 toolchain, SwiftPM tools 6.2, Swift Testing, Observation, SwiftUI, Network.framework, Xcode 27.2, Node 22 (`node --test`). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-09-reflex-architecture-design.md`

## Global Constraints

- Repo root is `~/ReflexArchitecture`; every path is relative to it and every command runs from it.
- `Core/Package.swift`: `// swift-tools-version: 6.2`, package name `InventoryCore`, platforms `.macOS(.v26), .iOS(.v26)`.
- Every Swift target: `swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]`.
- App target: iOS 26.0, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- No third-party dependencies, no `package.json`, no `npm install`.
- `IntrospectionKit` and `InventoryCore` never import SwiftUI or UIKit.
- On every ViewModel only `state` (settable inside Core only) and `send(action:)` are public; everything else stays `internal`.
- API: base `https://dummyjson.com`; `GET /products?limit=20&select=title,stock`; `PUT /products/{id}` with `Content-Type: application/json` and body `{"stock":n}`.
- Copy: `Couldn't load products`, `Couldn't save`.
- Node names `InventoryList`, `InventoryDetail`, `Stack`. Action titles `SelectProduct {id}`, `Increment`, `Decrement`, `Save`, `SetQuantity {quantity}`, and the lent `goBack`.
- Stock range `0...999_999`.
- Fixture key: `"<METHOD> <percent-encoded path>[?<percent-encoded query>]"`, host ignored. Fixture value: `{"status": n, "body"?: any JSON, "delayMs"?: n}`.
- Network violation: stderr line `network violation: <entry>`, exit code 3.
- Debug server: port 7777, local connections only, all of its code inside `#if DEBUG`.

## Review Focus

1. Swiping back in the app must move Core's navigator too: `ls` over the socket says `InventoryList` afterwards (Task 5, Step 7).
2. Two commands in one TCP packet, or one command split across packets, each get exactly one answer (Task 5, `LineBuffer` test).
3. No input can overflow the stock: `SetQuantity` above 999,999 is ignored and `Increment` at 999,999 stays put (Task 3 journey).
4. Malformed payloads (missing, not an object, wrong type, fractional) are refused before the ViewModel sees them (Task 1 session test, Task 3 journey).
5. `goBack` on the root and `SelectProduct` with an unknown id leave the user on the list (Task 3 journey).

---

### Task 1: Repository and Introspection Kit

**Files:**
- Create: `.gitignore`, `Core/Package.swift`
- Create: `Core/Sources/IntrospectionKit/IntrospectionNode.swift` (`IntrospectionNode`, `IntrospectionProviding`, `IntrospectionInput`, `IntrospectionAction`)
- Create: `Core/Sources/IntrospectionKit/IntrospectionSession.swift`
- Test: `Core/Tests/IntrospectionKitTests/IntrospectionSessionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor public protocol IntrospectionNode {
      var name: String { get }
      var state: any Encodable { get }
      var actions: [IntrospectionAction] { get }
      var child: (any IntrospectionNode)? { get }   // protocol extension default: nil
  }
  @MainActor public protocol IntrospectionProviding: AnyObject {
      var introspectionNode: any IntrospectionNode { get }
  }
  public protocol IntrospectionInput: Decodable { static var fields: [String] { get } }
  public struct IntrospectionAction {
      public let title: String
      public let fields: [String]                     // [] when the action takes no input
      public init(_ title: String, perform: @escaping @MainActor () -> Void)
      public init<Input: IntrospectionInput>(_ title: String, input: Input.Type,
                                             perform: @escaping @MainActor (Input) -> Void)
  }
  public final class IntrospectionSession {
      public init(root: any IntrospectionProviding)  // keeps root alive
      public func handle(_ line: String) -> String    // text in → text out, JSON in → JSON out
  }
  ```

- [ ] **Step 1: Start the repository**

```bash
git init
printf '.build/\n.swiftpm/\nDerivedData/\nxcuserdata/\n.DS_Store\n' > .gitignore
git add .gitignore docs
git commit -m "docs: Reflex architecture design and plan"
```

- [ ] **Step 2: Write `Core/Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "InventoryCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "IntrospectionKit", targets: ["IntrospectionKit"]),
    ],
    targets: [
        .target(name: "IntrospectionKit", swiftSettings: settings),
        .testTarget(name: "IntrospectionKitTests", dependencies: ["IntrospectionKit"], swiftSettings: settings),
    ]
)
```

- [ ] **Step 3: Write the failing tests** in `Core/Tests/IntrospectionKitTests/IntrospectionSessionTests.swift`

```swift
import Testing
@testable import IntrospectionKit

struct SetInput: IntrospectionInput {
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
```

- [ ] **Step 4: Run them to see them fail**

Run: `swift test --package-path Core`
Expected: build error `cannot find 'IntrospectionSession' in scope`.

- [ ] **Step 5: Implement the contract and the session**

- `IntrospectionAction` keeps an internal `perform: @MainActor (Data?) throws -> Void`. The input initializer decodes `Input` with `JSONDecoder` and throws when the payload is missing or doesn't decode.
- Focus: follow `child` from `root.introspectionNode` to the deepest node. Available actions are that node's, then each ancestor's, nearest first, skipping titles already seen.
- Text: `ls` answers three lines (name, `  state   <json>`, `  actions <titles>`, an action with fields written `Title {a, b}`); `do <Title> [json]` answers `ok`; refusals start with `error: `.
- JSON (the line starts with `{`): parse with `JSONSerialization`, re-serialize `payload` to `Data` for the action. `{"cmd":"ls"}` → `{"actions":[{"fields":[…],"title":…}],"name":…,"state":…}`; `do` → `{"ok":true}` or `{"error":"…"}`.
- Messages: `unknown action "<T>"; available: <titles as in ls>`; `<T> expects {<fields>}` optionally followed by `: <reason>`; `unknown command "<cmd>"; use ls or do <Action> [json]`.
- One `JSONEncoder` with `[.sortedKeys, .withoutEscapingSlashes]` for states and JSON answers.

- [ ] **Step 6: Run the tests**

Run: `swift test --package-path Core`
Expected: 4 tests passed.

- [ ] **Step 7: Commit**

```bash
git add Core
git commit -m "feat: IntrospectionKit contract and ls/do session"
```

---

### Task 2: Inventory Core, headless CLI and the first journey

**Files:**
- Modify: `Core/Package.swift` (add `InventoryCore` and `InventoryCLI`)
- Create in `Core/Sources/InventoryCore/`: `Product.swift`, `HTTPClient.swift` (protocol and `URLSessionHTTPClient`), `InventoryAPI.swift`, `ViewModel.swift`, `StackNavigator.swift` (with `Route`), `InventoryListViewModel.swift`, `InventoryDetailViewModel.swift`, `InventoryApp.swift`, and the introspection files `InventoryApp+Introspection.swift`, `StackNavigator+Introspection.swift`, `InventoryListViewModel+Introspection.swift`, `InventoryDetailViewModel+Introspection.swift`
- Create in `Core/Sources/InventoryCLI/`: `CLI.swift`, `FixtureHTTPClient.swift`
- Create: `behavior/sdk.mjs`, `behavior/inventory.test.mjs`
- Create: `behavior/fixtures/Inventory.default.json`, `Inventory.stockCount2.json`, `Inventory.saveSucceeds.json`
- Create (executable): `cli`, `test`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces, `InventoryCore`:
  ```swift
  public struct Product: Codable, Equatable, Identifiable, Sendable {
      public let id: Int; public let title: String; public var stock: Int
  }
  public protocol HTTPClient { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }
  public final class URLSessionHTTPClient: HTTPClient { public init() }   // URLSession.shared
  struct InventoryAPI {
      init(http: any HTTPClient)
      func products() async throws -> [Product]   // decodes {"products":[…]}
      func save(id: Int, stock: Int) async throws  // throws on non-2xx, ignores the body
  }
  @MainActor protocol ViewModel: AnyObject {
      associatedtype State
      associatedtype Message
      var state: State { get set }
      func update(state: inout State, message: Message)   // the only writer of state
  }
  extension ViewModel { func send(message: Message) }      // update(state: &state, message:)

  @Observable public final class InventoryListViewModel: ViewModel {
      public struct State: Encodable { public var products: [Product] = []; public var isLoading = true; public var error: String? }
      public enum Action { case selectProduct(id: Int) }
      public internal(set) var state: State
      public func send(action: Action)
      init(api: InventoryAPI, push: @escaping (Route) -> Void)   // starts loading right away
  }
  @Observable public final class InventoryDetailViewModel: ViewModel {
      public struct State: Encodable {
          public let productId: Int; public let title: String; public var stockCount: Int
          public var isSaving = false; public var isSaved = false; public var error: String?
      }
      public enum Action { case increment, decrement, save, setQuantity(Int) }
      public internal(set) var state: State
      public func send(action: Action)
      init(product: Product, api: InventoryAPI, onSaved: @escaping (Product) -> Void)
  }
  nonisolated public enum Route: Hashable {           // nonisolated ==/hash(into:) on ObjectIdentifier
      case list(InventoryListViewModel)
      case detail(InventoryDetailViewModel)
  }
  @Observable public final class StackNavigator: ViewModel {
      public struct State { public let root: Route; public var path: [Route] = [] }
      public enum Action { case goBack, popTo(depth: Int) }
      public internal(set) var state: State
      public func send(action: Action)
      init(root: Route)
      func push(_ route: Route)
  }
  public final class InventoryApp {
      public let navigator: StackNavigator
      public init(http: any HTTPClient)
  }
  // InventoryApp, StackNavigator and both screens conform to IntrospectionProviding in their +Introspection files.
  ```
- Produces, `InventoryCLI`:
  ```swift
  struct Fixture { let status: Int; let body: Data }
  final class FixtureHTTPClient: HTTPClient {
      init(fixtures: [String: Fixture])
      static func load(_ paths: [String]) throws -> [String: Fixture]   // later files win
      static func key(for request: URLRequest) -> String
  }
  @main enum CLI { static func main() async }
  ```
- Produces, `behavior/sdk.mjs`: `fixture(name) → path`, `createBehaviorSession({ fixtures })` → `{ ls(), precondition(name, expectation?), do({ action, payload, expectation }), close() }`.

- [ ] **Step 1: Write the fixtures**

`behavior/fixtures/Inventory.stockCount2.json`:
```json
{
  "GET /products?limit=20&select=title,stock": {
    "status": 200,
    "body": { "products": [{ "id": 1, "title": "Essence Mascara Lash Princess", "stock": 2 }], "total": 1, "skip": 0, "limit": 20 }
  }
}
```
`behavior/fixtures/Inventory.saveSucceeds.json`: `{ "PUT /products/1": { "status": 200 } }`
`behavior/fixtures/Inventory.default.json`: the same GET with five products (ids 1–5, your choice of titles and stock) and `"PUT /products/<id>": { "status": 200 }` for each of them.

- [ ] **Step 2: Write `behavior/sdk.mjs`**

No dependencies; Node built-ins only. Rules:
- The binary is `../Core/.build/debug/inventory-cli` resolved from `import.meta.url`, spawned with `['--fixtures', ...paths]`. `fixture(name)` resolves `./fixtures/<name>.json` the same way.
- One request in flight at a time: write `JSON.stringify(request) + '\n'`, resolve with the next stdout line parsed as JSON (`readline` over stdout).
- `ls()` sends `{"cmd":"ls"}`. `do({ action, payload, expectation })` sends `{"cmd":"do", action, payload}`, throws `do <action> refused: <error>` on an `error` answer, then, if an expectation was given, polls `ls()` until `expectation(node)` stops throwing. `precondition(name, expectation?)` polls until the name matches and the optional expectation passes.
- Polling: every 10 ms for up to 2000 ms; on timeout throw the last assertion message plus `\nlast seen: <JSON of the node>`. Only assertion errors are retried.
- When the process exits, every pending and later call rejects at once with `inventory-cli exited with code <code>: <collected stderr>`. Swallow `error` events on the child's stdin (EPIPE after exit).
- `close()` ends stdin and kills the process if it is still running.

- [ ] **Step 3: Write the failing journey** in `behavior/inventory.test.mjs`

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBehaviorSession, fixture } from './sdk.mjs';

// Every journey starts on the loaded list and opens one product.
async function openInventoryDetail(session, id = 1) {
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await session.do({
    action: 'SelectProduct',
    payload: { id },
    expectation: ({ name, state }) => {
      assert.equal(name, 'InventoryDetail');
      assert.equal(state.productId, id);
    },
  });
}

test('given save succeeds, the user can adjust the quantity and save it', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveSucceeds')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);

  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 1) });
  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 0) });
  // Decrement is always listed; the ViewModel decides it does nothing at zero
  await session.do({ action: 'Decrement', expectation: ({ state }) => assert.equal(state.stockCount, 0) });
  await session.do({
    action: 'SetQuantity',
    payload: { quantity: 40 },
    expectation: ({ state }) => assert.equal(state.stockCount, 40),
  });
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) });
  // any edit after a save makes the screen unsaved again
  await session.do({
    action: 'Increment',
    expectation: ({ state }) => {
      assert.equal(state.stockCount, 41);
      assert.equal(state.isSaved, false);
    },
  });
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) });
  // back on the list, the product shows what was saved
  await session.do({
    action: 'goBack',
    expectation: ({ name, state }) => {
      assert.equal(name, 'InventoryList');
      assert.equal(state.products.find((p) => p.id === 1).stock, 41);
    },
  });
});
```

- [ ] **Step 4: Write the two scripts** and `chmod +x cli test`

`cli`:
```sh
#!/bin/sh
# Start the headless app. Without arguments it loads the default fixtures.
set -e
cd "$(dirname "$0")"
swift build -q --package-path Core --product inventory-cli >&2
[ $# -eq 0 ] && set -- behavior/fixtures/Inventory.default.json
exec Core/.build/debug/inventory-cli --fixtures "$@"
```
`test`:
```sh
#!/bin/sh
# Unit tests, then the behavior suite against the headless CLI.
set -e
cd "$(dirname "$0")"
swift test --package-path Core
swift build --package-path Core --product inventory-cli
node --test 'behavior/*.test.mjs'
```

- [ ] **Step 5: Run it to see it fail**

Run: `./test`
Expected: the unit tests pass, then `error: no product named 'inventory-cli'`.

- [ ] **Step 6: Add the targets to `Core/Package.swift`**

Products: `.library(name: "InventoryCore", targets: ["InventoryCore"])`, `.executable(name: "inventory-cli", targets: ["InventoryCLI"])`.
Targets: `.target(name: "InventoryCore", dependencies: ["IntrospectionKit"], swiftSettings: settings)`, `.executableTarget(name: "InventoryCLI", dependencies: ["InventoryCore", "IntrospectionKit"], swiftSettings: settings)`.

- [ ] **Step 7: Implement `InventoryCore`**

- Reducers follow the spec's "Screens" and "Navigation" sections exactly, including every no-op, the 0…999,999 range and the two error strings. Effects start a `Task` inside `update` that reports back through `send(message:)`; `update` never reads `self.state`.
- The list sends itself a load message in `init`. `selectProduct` for a loaded id calls `push(.detail(…))` with an `onSaved` that sends the list a message replacing that product's stock (capture the list weakly).
- `save` success reports `Product(id: productId, title: title, stock: stockCount)` to `onSaved`.
- `StackNavigator`: `goBack` pops one (no-op on the root), `popTo(depth:)` trims `path` to `depth` (no-op unless `0 <= depth < path.count`), `push` appends.
- `InventoryApp.init` builds the API, the list and the navigator, wiring the list's `push` to the navigator through a weakly captured local.
- `InventoryAPI.products()` builds the URL with `URLComponents` and query items in this order: `limit=20`, `select=title,stock`.
- Nodes: `InventoryApp` returns the navigator's node. `Stack`: state `["depth": state.path.count]`, actions `[goBack]`, child the node of `state.path.last ?? state.root`. `InventoryList`: state is the `State`, actions `SelectProduct` with input `SelectProductInput { let id: Int }`. `InventoryDetail`: state is the `State`, actions `Increment`, `Decrement`, `Save`, `SetQuantity` with input `SetQuantityInput { let quantity: Int }`. No conditionals in any node.

- [ ] **Step 8: Implement `InventoryCLI`**

- Arguments must be `--fixtures` plus at least one path; otherwise write `usage: inventory-cli --fixtures <file.json>...` to stderr and `exit(64)`.
- `FixtureHTTPClient.key(for:)` = method (default `GET`) + space + `url.path(percentEncoded: true)` + (`?` + `url.query(percentEncoded: true)` when there is a query). `load` reads each file with `JSONSerialization`; `body` is optional and stored re-serialized (empty `Data` when absent). A hit returns the body with an `HTTPURLResponse` of that status; a miss throws `URLError(.resourceUnavailable)` for now.
- `CLI.main` builds `IntrospectionSession(root: InventoryApp(http: FixtureHTTPClient(…)))`, then reads `for try await line in FileHandle.standardInput.bytes.lines` (async, so effects run between commands), skips blank lines and writes each answer plus `"\n"` with `FileHandle.standardOutput.write` (unbuffered; never `print`). EOF ends the process with status 0.

- [ ] **Step 9: Run everything**

Run: `./test`
Expected: 4 Swift tests pass, then `# pass 1` from node.

- [ ] **Step 10: Walk the app by hand**

Run: `printf 'ls\ndo SelectProduct {"id":2}\nls\n' | ./cli`
Expected: an `InventoryList` block with the five default products, `ok`, then an `InventoryDetail` block with `"productId":2` and `actions Increment, Decrement, Save, SetQuantity {quantity}, goBack`.

- [ ] **Step 11: Commit**

```bash
git add Core behavior cli test
git commit -m "feat: inventory core, headless CLI and the save journey"
```

---

### Task 3: Failure and edge journeys, zero network

**Files:**
- Modify: `Core/Package.swift` (add `.testTarget(name: "InventoryCLITests", dependencies: ["InventoryCLI"], swiftSettings: settings)`)
- Create: `Core/Sources/InventoryCLI/NetworkGuard.swift`
- Modify: `Core/Sources/InventoryCLI/FixtureHTTPClient.swift`, `Core/Sources/InventoryCLI/CLI.swift`
- Test: `Core/Tests/InventoryCLITests/NetworkGuardTests.swift`
- Create: `behavior/fixtures/Inventory.saveFails.json`, `behavior/fixtures/Inventory.saveSlow.json`, `behavior/fixtures/Inventory.listFails.json`
- Modify: `behavior/inventory.test.mjs`

**Interfaces:**
- Consumes: `FixtureHTTPClient`, `Fixture`, `CLI` and the SDK from Task 2.
- Produces:
  ```swift
  nonisolated final class NetworkGuard: URLProtocol {
      static func install()                 // URLProtocol.registerClass, safe to call twice
      static func record(_ entry: String)   // thread-safe (Mutex)
      static var violations: [String] { get }
      static func reset()                   // tests only
  }
  ```
  Entries: `"<METHOD> <absolute URL>"` for a request the guard caught, `"missing fixture: <key>"` for a fixture miss.
- Changes: `struct Fixture { let status: Int; let body: Data; var delayMs = 0 }`.

- [ ] **Step 1: Write the failing Swift tests** in `Core/Tests/InventoryCLITests/NetworkGuardTests.swift`

```swift
import Foundation
import Testing
@testable import InventoryCLI

@Suite(.serialized) struct NetworkGuardTests {
    @Test func requestsThroughTheSharedSessionAreBlockedAndRecorded() async {
        NetworkGuard.reset()
        NetworkGuard.install()
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(from: URL(string: "https://example.com/ping")!)
        }
        #expect(NetworkGuard.violations == ["GET https://example.com/ping"])
    }

    @Test func requestsWithoutAFixtureAreRecorded() async throws {
        NetworkGuard.reset()
        let client = FixtureHTTPClient(fixtures: [
            "GET /products?limit=20&select=title,stock": Fixture(status: 200, body: Data("{}".utf8)),
        ])
        let (body, response) = try await client.send(
            URLRequest(url: URL(string: "https://dummyjson.com/products?limit=20&select=title,stock")!))
        #expect(response.statusCode == 200)
        #expect(body == Data("{}".utf8))

        var put = URLRequest(url: URL(string: "https://dummyjson.com/products/7")!)
        put.httpMethod = "PUT"
        await #expect(throws: (any Error).self) { _ = try await client.send(put) }
        #expect(NetworkGuard.violations == ["missing fixture: PUT /products/7"])
    }
}
```

- [ ] **Step 2: Write the fixtures and the journeys**

`Inventory.saveFails.json`: `{ "PUT /products/1": { "status": 500, "body": { "message": "boom" } } }`
`Inventory.saveSlow.json`: `{ "PUT /products/1": { "status": 200, "delayMs": 500 } }`
`Inventory.listFails.json`: `{ "GET /products?limit=20&select=title,stock": { "status": 500 } }`

Append to `behavior/inventory.test.mjs`:
```js
test('given save fails, the quantity stays unsaved', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveFails')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await session.do({
    action: 'Save',
    expectation: ({ state }) => {
      assert.equal(state.isSaving, false);
      assert.equal(state.isSaved, false);
      assert.equal(state.error, "Couldn't save");
    },
  });
});

test('given the list fails to load, the user sees an error', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.listFails')] });
  t.after(() => session.close());
  await session.precondition('InventoryList', ({ state }) => {
    assert.equal(state.isLoading, false);
    assert.equal(state.error, "Couldn't load products");
    assert.deepEqual(state.products, []);
  });
});

test('actions that make no sense change nothing', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2')] });
  t.after(() => session.close());
  await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
  await session.do({ action: 'goBack', expectation: ({ name }) => assert.equal(name, 'InventoryList') });
  await session.do({
    action: 'SelectProduct',
    payload: { id: 999 },
    expectation: ({ name }) => assert.equal(name, 'InventoryList'),
  });

  await openInventoryDetail(session);
  for (const quantity of [-5, 1_000_000]) {
    await session.do({ action: 'SetQuantity', payload: { quantity }, expectation: ({ state }) => assert.equal(state.stockCount, 2) });
  }
  await session.do({ action: 'SetQuantity', payload: { quantity: 999_999 }, expectation: ({ state }) => assert.equal(state.stockCount, 999_999) });
  await session.do({ action: 'Increment', expectation: ({ state }) => assert.equal(state.stockCount, 999_999) });
  // malformed input never reaches the ViewModel
  for (const quantity of ['many', 1.5]) {
    await assert.rejects(session.do({ action: 'SetQuantity', payload: { quantity } }), /SetQuantity expects \{quantity\}/);
  }
  // what isn't on screen can't be done
  await assert.rejects(session.do({ action: 'SelectProduct', payload: { id: 1 } }), /unknown action "SelectProduct"/);
});

test('a request without a fixture fails the session', async (t) => {
  const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2')] });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await assert.rejects(
    session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaved, true) }),
    /network violation: missing fixture: PUT \/products\/1/,
  );
});

test('edits while a save is in flight change nothing', async (t) => {
  const session = createBehaviorSession({
    fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveSlow')],
  });
  t.after(() => session.close());
  await openInventoryDetail(session);
  await session.do({ action: 'Save', expectation: ({ state }) => assert.equal(state.isSaving, true) });
  await session.do({ action: 'Increment', expectation: ({ state }) => assert.equal(state.stockCount, 2) });
  // a second Save is ignored too; the first one lands with the original quantity
  await session.do({
    action: 'Save',
    expectation: ({ state }) => {
      assert.equal(state.isSaved, true);
      assert.equal(state.stockCount, 2);
    },
  });
});
```

- [ ] **Step 3: Run to see what fails**

Run: `swift test --package-path Core`
Expected: build error `cannot find 'NetworkGuard' in scope`.

Run: `node --test 'behavior/*.test.mjs'`
Expected: `a request without a fixture fails the session` fails (it times out instead of reporting a violation), and so does `edits while a save is in flight change nothing` (fixtures answer at once, so `isSaving` is never seen). The other new journeys pin reducer rules written in Task 2 and may already pass; if one fails, fix the reducer, not the test.

- [ ] **Step 4: Implement the guard**

- `NetworkGuard` answers `canInit` with `true` for everything, records `"<METHOD> <url.absoluteString>"` in `startLoading` and fails the load with `URLError(.notConnectedToInternet)`. Storage is a `Mutex<[String]>` from `Synchronization`.
- `FixtureHTTPClient` records `"missing fixture: <key>"` before throwing on a miss. `load` reads the optional `delayMs`; a hit waits that long (`Task.sleep(for: .milliseconds(delayMs))`) before answering.
- `CLI.main` calls `NetworkGuard.install()` before building the app. Before writing each answer, if `NetworkGuard.violations` is not empty it writes one `network violation: <entry>` line per entry to stderr and calls `exit(3)`.

- [ ] **Step 5: Run everything**

Run: `./test`
Expected: 6 Swift tests and 6 behavior tests pass.

- [ ] **Step 6: Commit**

```bash
git add Core behavior
git commit -m "feat: failure journeys and zero-network guard"
```

---

### Task 4: SwiftUI app on the real network

**Files:**
- Create: `ReflexArchitecture.xcodeproj/project.pbxproj`
- Create: `Mobile/ReflexArchitectureApp.swift`, `Mobile/RootView.swift`, `Mobile/InventoryListView.swift`, `Mobile/InventoryDetailView.swift`

**Interfaces:**
- Consumes: `InventoryApp(http:)`, `URLSessionHTTPClient()`, `StackNavigator.state.root`, `.state.path`, `.send(action: .popTo(depth:))`, `Route`, and `state` / `send(action:)` of both screens.
- Produces: app target `ReflexArchitecture`, extended in Task 5.

- [ ] **Step 1: Write the project file**

Model it on `~/TabBar/TabBar.xcodeproj/project.pbxproj` (objectVersion 90, the `ModelViewer` target's settings): one application target `ReflexArchitecture`; a `PBXFileSystemSynchronizedRootGroup` for `Mobile`; an `XCLocalSwiftPackageReference` with `relativePath = Core` in the project's `packageReferences`; `XCSwiftPackageProductDependency` entries `InventoryCore` and `IntrospectionKit` in the target's `packageProductDependencies` and as `productRef` build files in its Frameworks phase. Target settings: `PRODUCT_BUNDLE_IDENTIFIER = devplaceholder.ReflexArchitecture`, `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `SDKROOT = iphoneos`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"`, `TARGETED_DEVICE_FAMILY = "1,2"`, `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES`, `INFOPLIST_KEY_UILaunchScreen_Generation = YES`, `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 2S742HE3ZF`, plus the Swift settings from Global Constraints.

- [ ] **Step 2: Write the views**

- `ReflexArchitectureApp` keeps `InventoryApp(http: URLSessionHTTPClient())` in `@State` and shows `RootView(navigator:)`.
- `RootView`: `NavigationStack(path:)` with a `Binding` that reads `navigator.state.path` and writes `navigator.send(action: .popTo(depth: newPath.count))`; the root screen is `navigator.state.root`; `.navigationDestination(for: Route.self)`; one `switch` over `Route` picks the view.
- `InventoryListView`: rows are `Button`s sending `.selectProduct(id:)` (no `NavigationLink`), each showing title and stock; a `ProgressView` while `isLoading`; the `error` text when set; title "Inventory".
- `InventoryDetailView`: title, stock count, − and + buttons, a quantity `TextField` that sends `.setQuantity` on submit (its typing buffer is the only `@State` in the view), Save disabled while `isSaving`, a "Saved" label when `isSaved`, the `error` text when set.

- [ ] **Step 3: Build**

Run: `xcodebuild -project ReflexArchitecture.xcodeproj -scheme ReflexArchitecture -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`. If the scheme is missing, add a shared one in `ReflexArchitecture.xcodeproj/xcshareddata/xcschemes/` modelled on `~/TabBar/TabBar.xcodeproj/xcshareddata/xcschemes/TabBar.xcscheme`.

- [ ] **Step 4: Check that Core stays UI-free**

Run: `grep -rlE "import (SwiftUI|UIKit)" Core/Sources`
Expected: no output.

- [ ] **Step 5: Use the app in the simulator**

Install and launch on the `iPhone 18 Pro` simulator (iOS 27.2). Expected: 20 DummyJSON products with stock; tapping the first opens its detail; −, +, typing a quantity and Save end with "Saved"; Back shows the saved stock in the list; swiping back from the left edge works. Take a screenshot of the list and of a saved detail.

- [ ] **Step 6: Commit**

```bash
git add ReflexArchitecture.xcodeproj Mobile
git commit -m "feat: SwiftUI app bound to the Reflex core"
```

---

### Task 5: Drive the simulator app from the terminal

**Files:**
- Create: `Core/Sources/IntrospectionKit/LineBuffer.swift` and `Core/Sources/IntrospectionKit/IntrospectionServer.swift`, each wrapped entirely in `#if DEBUG`
- Test: `Core/Tests/IntrospectionKitTests/LineBufferTests.swift`
- Modify: `Mobile/ReflexArchitectureApp.swift`

**Interfaces:**
- Consumes: `IntrospectionSession(root:)`, `handle(_:)`.
- Produces:
  ```swift
  #if DEBUG
  struct LineBuffer { mutating func append(_ data: Data) -> [String] }   // complete non-empty lines, "\r" stripped, tail kept
  public final class IntrospectionServer {
      public init(port: UInt16, session: IntrospectionSession) throws
      public func start()
  }
  #endif
  ```

- [ ] **Step 1: Write the failing test**

```swift
#if DEBUG
import Foundation
import Testing
@testable import IntrospectionKit

@Test func lineBufferSplitsAndJoinsPackets() {
    var buffer = LineBuffer()
    #expect(buffer.append(Data("ls\ndo In".utf8)) == ["ls"])
    #expect(buffer.append(Data("crement\n".utf8)) == ["do Increment"])
    #expect(buffer.append(Data("ls\r\nls\n\n".utf8)) == ["ls", "ls"])
}
#endif
```

- [ ] **Step 2: Run it to see it fail**

Run: `swift test --package-path Core --filter lineBuffer`
Expected: build error `cannot find 'LineBuffer' in scope`.

- [ ] **Step 3: Implement `LineBuffer` and the server**

`NWListener` on `NWParameters.tcp` with `acceptLocalOnly = true`, port 7777; listener and connections run on `.main`, so callbacks enter the session through `MainActor.assumeIsolated`. Each connection gets its own `LineBuffer` and a receive loop; every line is answered with `handle(_:) + "\n"`; the connection is cancelled on completion or error. The server keeps strong references to itself and its live connections.

- [ ] **Step 4: Run the test**

Run: `swift test --package-path Core --filter lineBuffer`
Expected: 1 test passed.

- [ ] **Step 5: Start the server in Debug**

In `ReflexArchitectureApp`, inside `#if DEBUG`, create `IntrospectionServer(port: 7777, session: IntrospectionSession(root: app))` once at launch, start it and keep it in `@State`.

- [ ] **Step 6: Drive the simulator**

Build and launch the Debug app, then:
- `printf 'ls\n' | nc -w 1 localhost 7777` → `InventoryList` with 20 products.
- `printf 'do SelectProduct {"id":1}\nls\n' | nc -w 1 localhost 7777` → `ok`, then an `InventoryDetail` block; the simulator shows the detail screen (screenshot).
- `printf 'do Increment\n' | nc -w 1 localhost 7777` → `ok`; the count on screen goes up (screenshot).

- [ ] **Step 7: Swipe back and ask again**

Swipe back from the left edge in the simulator, then `printf 'ls\n' | nc -w 1 localhost 7777`.
Expected: `InventoryList`.

- [ ] **Step 8: Release builds without the server**

Run: `xcodebuild -project ReflexArchitecture.xcodeproj -scheme ReflexArchitecture -configuration Release -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit**

```bash
git add Core Mobile
git commit -m "feat: drive the debug app over localhost:7777"
```

---

### Task 6: Teach agents and measure the loop

**Files:**
- Create: `.claude/skills/reflex/SKILL.md`

- [ ] **Step 1: Write the skill**

Frontmatter: `name: reflex`; `description: Use when exploring, testing or changing ReflexArchitecture — run the headless CLI (ls/do), add fixtures, add a screen (ViewModel + introspection node + SwiftUI view), write behavior tests, or drive the simulator app over localhost:7777.`
Sections, terse, commands first: **Run** (`./cli`, `ls`, `do Action {json}`, `./test`, `nc localhost 7777` against a Debug build); **Rules** (ViewModel shape, the three node rules, views only read `state` and call `send(action:)`, Core never imports UI); **Add a fixture** (key format, composing files, a miss is a network violation); **Add a screen** (the files to create, PascalCase actions, camelCase lent actions); **Write a behavior test** (one journey per fixture set, `precondition` then `do` with an expectation on something the action changes, `assert.rejects` for refusals).

- [ ] **Step 2: Check the skill's commands**

Run each command exactly as the skill writes it: `printf 'ls\n' | ./cli`, `./test`, and the `nc` command against the running Debug app.
Expected: the outputs the skill describes.

- [ ] **Step 3: Measure the feedback loop**

With a throwaway Node script (not committed), send a journey that never touches the network — `do SelectProduct {"id":1}`, `do Increment` three times, `do SetQuantity {"quantity":10}`, `do goBack`, each followed by `ls` — first to a headless `inventory-cli --fixtures behavior/fixtures/Inventory.default.json` over stdin/stdout, then to the Debug app over `localhost:7777` with its list already loaded. Run each once to warm up, then time five runs. Also note the `./test` total and the time from `xcodebuild` to the app showing its list. Report the numbers next to the article's (a couple hundred milliseconds headless, about two seconds on a simulator).

- [ ] **Step 4: Commit**

```bash
git add .claude
git commit -m "docs: reflex skill for agents"
```
