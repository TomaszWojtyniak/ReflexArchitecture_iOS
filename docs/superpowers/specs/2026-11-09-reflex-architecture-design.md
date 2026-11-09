# ReflexArchitecture — design

Date: 2026-11-09
Source: [Reflex: an architecture for building mobile apps with agents](https://shopify.engineering/reflex) (Shopify Engineering, 2026-11-05). The article is the reference for everything not spelled out here.

## Intent

A small iOS test app for trying Shopify's Reflex architecture in Swift before deciding whether to use it in real apps. The app is only a vehicle. What matters is seeing all four Reflex pillars work end to end and judging the feedback loop:

1. **Core with no UI** — everything except views lives in a Swift package that builds and runs on macOS.
2. **One strict ViewModel shape** — actions in, state out, one place where state changes.
3. **Introspection** — every screen is exposed as a node: a name, its state as JSON, the actions it accepts.
4. **CLI** — `ls` / `do Action [json]` drive that contract headlessly; behavior tests speak the same protocol.

Success looks like: an agent or a person can walk the whole app from a terminal, the behavior suite runs headless in seconds, and the same commands drive the running simulator app live.

## Goals

- Core package (`InventoryCore`) with no SwiftUI/UIKit imports; `swift build` and `swift test` work on macOS.
- Every screen's ViewModel follows the shape in "ViewModel shape" below.
- `IntrospectionKit` module: node contract, focus on the deepest node, containers lending actions, typed action inputs, refusal of anything not on screen.
- Headless CLI host (`inventory-cli`) built on Core with fixtures, speaking text (`ls`, `do`) and newline-delimited JSON on stdin/stdout.
- Behavior tests in JavaScript that drive the CLI through the JSON protocol: journeys, fixtures for every request, zero network enforced.
- iOS app (SwiftUI) whose views only read ViewModel state and call `send(action:)`; navigation state lives in Core.
- Debug builds of the iOS app expose the same protocol on a local TCP port, so `ls`/`do` drive the simulator live.
- A project skill that teaches agents to run the CLI, add a fixture, add a screen and write a behavior test.
- Report the measured feedback loop: one journey that never touches the network (open a product, edit it, go back), timed after a warm-up run both headless and over port 7777 on the simulator, plus build and launch times reported separately. The app gets no fixture mode for this.

## Non-goals

- No Android/Kotlin twin. The JSON protocol and the JS tests stay platform-agnostic so one could be added later.
- No `@Introspectable` / `@IntrospectionInput` macros; introspection nodes are written by hand (the article says this is fine).
- Only a stack navigator — no tab or modal navigators until a screen needs one.
- HTTP is the only external edge — no Keychain, storage, feature flags or biometrics.
- No live-build journey suite or performance suite; the live socket is for exploration and one timing measurement.
- No screenshot/UI tests, no in-app assistant.

## Anti-goals (failure even if it "works")

- A view that calls anything on a ViewModel other than reading `state` and `send(action:)`.
- An introspection node containing an `if` or any rule that belongs in the reducer.
- Any third-party dependency, Swift or JavaScript.
- A test that passes while a real network request happened.
- Core importing SwiftUI/UIKit or failing to build with `swift build` on macOS.
- Pretty CLI output, colors, spinners, interactive wizards.

## Constraints

- Location: `~/ReflexArchitecture`, a new git repository (sibling of `~/TabBar`).
- Toolchain on this Mac: Xcode 27.2, Swift 6.4.2, macOS 27, iOS 27.2 simulator runtime, Node 22.20 (Bun is not installed).
- Swift 6 language mode, default actor isolation `MainActor` and approachable concurrency everywhere (same as the user's ModelViewer target).
- Package: `swift-tools-version: 6.2`, platforms `.macOS(.v26)`, `.iOS(.v26)`. App deployment target iOS 26.0.
- Behavior tests run on Node's built-in runner (`node --test`), plain `.mjs`, no npm packages.
- Real backend for the app: DummyJSON, base URL `https://dummyjson.com`:
  - `GET /products?limit=20&select=title,stock` → `{"products":[{"id":1,"title":"Essence Mascara Lash Princess","stock":99},…],"total":194,"skip":0,"limit":20}`
  - `PUT /products/{id}` with JSON body `{"stock": n}` → 200 with the product (writes are simulated, nothing persists); 404 for unknown ids.
- Debug socket: TCP port `7777`, local connections only, compiled out of Release builds.

## Design

### Layout

```
~/ReflexArchitecture/
├── Core/                          Swift package "InventoryCore"
│   ├── Package.swift
│   ├── Sources/IntrospectionKit/  contract, session (ls/do), debug TCP server
│   ├── Sources/InventoryCore/     app root, navigator, ViewModels, API, HTTP edge, +Introspection files
│   ├── Sources/InventoryCLI/      headless host: fixtures, network guard, stdin/stdout loop (product "inventory-cli")
│   └── Tests/                     few unit tests for primitives
├── Mobile/                        SwiftUI app sources
├── ReflexArchitecture.xcodeproj   iOS app target "ReflexArchitecture" → local package Core
├── behavior/                      sdk.mjs, *.test.mjs, fixtures/*.json
├── cli                            build + start the headless CLI (default fixture)
├── test                           unit tests + behavior suite
└── .claude/skills/reflex/SKILL.md
```

Dependencies point one way: `InventoryCore → IntrospectionKit`; `InventoryCLI → InventoryCore`; the app → `InventoryCore` (+ `IntrospectionKit` in Debug for the server). Core never knows about the app or the CLI.

### ViewModel shape

Every screen (and the navigator) is an `@Observable final class` with:

- `State` — a struct, `Encodable`, holding everything the screen shows. Exposed as `public internal(set) var state`.
- `Action` — public enum, everything a view (or the CLI) can ask for. Entry point: `public func send(action:)`, one line wrapping it into `.viewAction`.
- `Message` — internal enum: `.viewAction(Action)` plus results coming back from services.
- `update(state: inout State, message: Message)` — the reducer and the only writer of `state`. Side effects (service calls) start a `Task` that reports back with `send(message:)`.
- Services and callbacks arrive through `init`.

An internal `ViewModel` protocol in Core captures this (`State`, `Message`, `state { get set }`, `update(state:message:)`) and provides `send(message:)`. Everything except `state` and `send(action:)` is internal to Core, so the app module physically cannot break the view contract.

### Screens

**InventoryList** (root screen)
- State: `products: [Product]`, `isLoading: Bool` (starts `true`), `error: String?`.
- Loads on creation (no view lifecycle involved, so headless runs behave the same).
- Load failure → `isLoading = false`, `error = "Couldn't load products"`.
- Action `selectProduct(id: Int)` → pushes the detail screen for that product; unknown id or nothing loaded → no-op.
- When a detail screen reports a save, the list replaces that product's stock in `products`.

**InventoryDetail**
- State: `productId: Int`, `title: String`, `stockCount: Int`, `isSaving: Bool`, `isSaved: Bool`, `error: String?`.
- Stock stays within `0...999_999`. `increment` → +1, no-op at 999,999. `decrement` → −1, no-op at 0. `setQuantity(n)` → sets `n`, no-op outside the range. Every edit sets `isSaved = false`. Edits while saving are no-ops.
- `save` → no-op while saving; otherwise `isSaving = true`, `error = nil`, PUT the current `stockCount`. Success → `isSaving = false`, `isSaved = true`, report `Product(id, title, stock: stockCount)` to the list. Failure (non-2xx or thrown) → `isSaving = false`, `error = "Couldn't save"`.
- The response body is ignored; the status alone confirms the save (DummyJSON does not persist anything).

`Product`: `id: Int`, `title: String`, `stock: Int` — `Codable`, `Equatable`, `Identifiable`, `Sendable`.

### Navigation

`StackNavigator` lives in Core and follows the ViewModel shape: state `root: Route` (fixed at creation) and `path: [Route]`, actions `goBack` (pop one, no-op at root) and `popTo(depth:)` (used only by SwiftUI's path binding when the user swipes back). Pushing is internal to Core (`push(_:)`), called by the list ViewModel. `Route` is an enum with `.list(InventoryListViewModel)` and `.detail(InventoryDetailViewModel)`, hashable by object identity.

`InventoryApp` is the root object: it builds `InventoryAPI` from an injected `HTTPClient`, the list ViewModel and the navigator, and wires the list's push to the navigator. The iOS app and the CLI are just two hosts that construct `InventoryApp`.

### Network edge and fixtures

- Core declares `protocol HTTPClient { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`.
- Core ships the real `URLSessionHTTPClient` (on `URLSession.shared`); the app injects it.
- `InventoryAPI` (Core) owns the base URL `https://dummyjson.com` and builds the two requests above.
- The CLI injects `FixtureHTTPClient`, which answers from fixture files keyed by `"METHOD path?query"` (host ignored), e.g. `"GET /products?limit=20&select=title,stock"` and `"PUT /products/1"`. Value: `{"status": 200, "body": <any JSON, optional>, "delayMs": <optional wait before answering>}`. The delay exists so a test can act while a save is in flight.
- Zero network, enforced: the CLI installs `NetworkGuard`, a `URLProtocol` that fails and records every request made through the URL loading system. A request with no fixture is recorded the same way. After each command the host checks the record; if anything is there it prints `network violation: …` to stderr and exits with code 3, so the test fails even when the app recovered from the error.

### Introspection Kit

Contract (one protocol, as in the article, with state as any `Encodable` so the whole `State` struct is dumped and nothing can be forgotten):

```swift
public protocol IntrospectionNode {
    var name: String { get }
    var state: any Encodable { get }
    var actions: [IntrospectionAction] { get }
    var child: (any IntrospectionNode)? { get }   // default nil
}
public protocol IntrospectionProviding: AnyObject {
    var introspectionNode: any IntrospectionNode { get }
}
```

- Each ViewModel gets a `+Introspection.swift` file in Core. Deleting it changes nothing in the app.
- Node names: `InventoryList`, `InventoryDetail`; the navigator's node is `Stack`. `InventoryApp`'s node is the navigator's node (nothing to add at the root yet).
- Screen actions are PascalCase, one per `Action` case: `SelectProduct {id}`, `Increment`, `Decrement`, `Save`, `SetQuantity {quantity}`. Lent container actions are camelCase: the stack lends `goBack`. `popTo` is not lent.
- Rules: if a user can see it, it's in state; if a user can do it, it's in actions; every action is listed every time with no conditionals; actions only call `send(action:)`.
- Focus: follow `child` from the root to the deepest node. Available actions are the focused node's own, then each ancestor's, nearest first; on a duplicate title the first wins. Anything else is refused with the list of available actions.
- Action inputs are `Decodable` types that also declare their field names (`static let fields = ["quantity"]`); a missing or malformed payload is rejected before the ViewModel sees it.

### Protocol

One handler, `IntrospectionSession.handle(_ line: String) -> String`, used by the CLI host and the debug server. A line starting with `{` is JSON, anything else is text.

Text (for agents and people):

```
> ls
InventoryDetail
  state   {"isSaved":false,"isSaving":false,"productId":1,"stockCount":2,"title":"Essence Mascara Lash Princess"}
  actions Increment, Decrement, Save, SetQuantity {quantity}, goBack
> do SetQuantity {"quantity": 40}
ok
> do Fly
error: unknown action "Fly"; available: Increment, Decrement, Save, SetQuantity {quantity}, goBack
```

JSON (for the test SDK), one object per line:

- `{"cmd":"ls"}` → `{"name":"InventoryDetail","state":{…},"actions":[{"title":"Increment","fields":[]},{"title":"SetQuantity","fields":["quantity"]},…]}`
- `{"cmd":"do","action":"SetQuantity","payload":{"quantity":40}}` → `{"ok":true}` or `{"error":"…"}`

State JSON uses sorted keys; `nil` optionals are omitted.

### CLI host

`inventory-cli --fixtures <file.json>...` merges the fixture files, installs `NetworkGuard`, builds `InventoryApp(http: FixtureHTTPClient(…))`, then reads stdin line by line asynchronously (so effects get to run between commands), writes each response followed by a newline and flushes. The `./cli` script builds the product and starts it with `behavior/fixtures/Inventory.default.json` when no arguments are given.

### Mobile app

SwiftUI, English copy. `ReflexArchitectureApp` holds `InventoryApp(http: URLSessionHTTPClient())`. `RootView` binds `NavigationStack(path:)` to the navigator (reads `state.path`, writes `popTo(depth:)`), shows `state.root` and a destination for each `Route`. Views never push; rows are buttons that send `selectProduct`. List: titles with stock, a spinner while loading, the error text on failure. Detail: title, stock count, − and + buttons, a quantity field that sends `setQuantity` on submit (the typing buffer is the only view-local state), a Save button disabled while saving, a "Saved" mark and the error text.

### Live control (Debug only)

`IntrospectionServer` in IntrospectionKit, wrapped in `#if DEBUG`: a Network.framework listener on port 7777 accepting local connections only, one `IntrospectionSession` shared by all connections, each received line answered with `handle(_:)` on the main actor. The app starts it in Debug builds. `nc localhost 7777` then gives the same `ls`/`do` against the simulator, and the UI updates because views observe the same ViewModels.

### Behavior tests

`behavior/sdk.mjs` (no dependencies) exports `fixture(name)` → path of `behavior/fixtures/<name>.json` and `createBehaviorSession({ fixtures })`, which spawns the built `inventory-cli` and offers:

- `ls()` → `{name, state, actions}`
- `precondition(name, expectation?)` — poll until the focused node has that name (and `expectation(node)`, if given, stops throwing)
- `do({action, payload, expectation})` — send the action (throw if refused), then poll `ls` until `expectation(node)` stops throwing
- `close()`

Polling runs about every 10 ms for up to 2 s, then fails with the last assertion error and the last node seen. If the CLI process exits, pending calls fail with its stderr. Journeys fold their steps into one test; scenarios that need different fixtures are separate tests.

A session can take several fixture files; they are merged, later files winning on the same key. Files: `Inventory.default` (5 products, a PUT for each — used by `./cli`), `Inventory.stockCount2` (GET: product 1 with stock 2), `Inventory.saveSucceeds` (PUT product 1 → 200), `Inventory.saveFails` (PUT product 1 → 500), `Inventory.saveSlow` (PUT product 1 → 200 after 500 ms), `Inventory.listFails` (GET → 500).

### Unit tests

Swift Testing, small and few: the session (focus, lending, refusals, input decoding, JSON mode) with fake nodes, and the network guard plus fixture client. ViewModel behavior is covered by the behavior suite, as in the article's trophy.

### Agent skill

`.claude/skills/reflex/SKILL.md`: how to start the CLI and use `ls`/`do`, the node rules, how to add a fixture, how to add a screen (ViewModel + `+Introspection` + view), how to write a behavior test (assert something the action changes), how to run `./test`, how to drive the simulator with `nc localhost 7777`.

## Left to the builder

File names inside modules, view layout and styling, exact error wording beyond the strings pinned above, polling interval details, the five products in `Inventory.default`.

## Calls made without asking (for the user to check)

1. iOS only; no Android twin.
2. The article's inventory example, backed by DummyJSON.
3. Node's built-in test runner instead of Bun (Node is installed, Bun isn't).
4. No macros; hand-written nodes.
5. Stack navigation only.
6. `~/ReflexArchitecture`, new git repo, a commit after each plan task.
7. iOS 26.0, Swift 6, default MainActor isolation.
8. Debug socket on `localhost:7777`.
9. English UI copy.
10. One CLI process speaks both text and JSON instead of a separate front-end.
11. Save is confirmed by HTTP status; the list shows the locally saved stock.
12. Stock is capped at 999,999 so no input can overflow `Int`.
13. The feedback-loop measurement times a journey that never touches the network, headless and on the simulator, with build and launch times reported separately; the app gets no fixture mode.
14. Fixtures may carry `delayMs`, so the "no edits while saving" rule has a test.
