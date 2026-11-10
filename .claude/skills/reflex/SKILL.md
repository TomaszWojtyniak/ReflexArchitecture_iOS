---
name: reflex
description: Use when exploring, testing or changing ReflexArchitecture — run the headless CLI (ls/do), add fixtures, add a screen or tab (ViewModel + introspection node + SwiftUI view), write behavior tests, or drive the simulator app over localhost:7777.
---

# Reflex in this repo

The app's logic runs headlessly. Every screen is a ViewModel exposed as a node (name, state as JSON, actions). You read and drive the app through that contract, never through pixels.

## Run

```sh
./cli                     # headless app on behavior/fixtures/Inventory.default.json
./cli behavior/fixtures/Inventory.stockCount2.json behavior/fixtures/Inventory.saveFails.json
./test                    # swift unit tests, then the behavior suite (node --test)
```

Inside `./cli`, one command per line:

```
ls                                 # focused screen: name, state JSON, available actions
do SelectProduct {"id":2}          # an action with input takes a JSON object
do goBack                          # lent by the navigator (camelCase = lent)
do selectTab {"tab":"search"}      # lent by the tab bar: home, search, favorites, profile, report
do dismiss                         # closes the report sheet that "report" (Zgłoś) opens
{"cmd":"ls"}                       # JSON lines get one-line JSON answers (what the test SDK uses)
```

`printf 'ls\ndo SelectProduct {"id":2}\nls\n' | ./cli` works for one-shot checks. Exit code 3 with `network violation: …` on stderr means a request had no fixture.

Against the Debug app running in the simulator (same protocol, the UI follows):

```sh
printf 'ls\n' | nc -w 1 localhost 7777
node behavior/live/navigation-race.mjs   # fast open/edit/back journeys must keep their pushes
```

Wait for `"isLoading":false` in `ls` before driving the live app: its list comes from the real network.

## Rules

- Core (`Core/Sources/InventoryCore`, `IntrospectionKit`) never imports SwiftUI or UIKit; it must build with `swift build`.
- ViewModel shape: `State` (Encodable struct, everything the screen shows), public `Action` enum, internal `Message` enum with `.viewAction(Action)` plus service results, `update(state:message:)` as the only writer of state. Effects start a `Task` in `update` and report back with `send(message:)`. `update` never reads `self.state`.
- Views read `viewModel.state` and call `viewModel.send(action:)`. Nothing else is public.
- Navigation is Core state: `TabNavigator` (selected tab, report sheet) holds Home's `StackNavigator`. Views never push or switch tabs; they send actions. `RootView` sends every tab tap as `selectTab`, and Core decides: switch, back to the first screen on a repeat tap, or open the report sheet.
- SwiftUI writes back the stack it displays after each transition; `StackView` ignores pops of screens it learned about less than 0.5 s ago, so a stale write can't undo a fresh push. Keep that guard, and rerun `behavior/live/navigation-race.mjs`, when touching `StackView`.
- Nodes: if a user can see it, it's in state; if a user can do it, it's in actions; every action is listed every time, no `if` in a node; actions only call `send(action:)`.
- Edge cases (zero stock, unknown id, bad range) are decided in `update`, never in the node or the view.

## Add a fixture

A fixture file maps `"<METHOD> <path>[?<query>]"` (host ignored) to `{"status": n, "body": <any JSON>, "delayMs": n}`; `body` and `delayMs` are optional. Sessions can load several files; later files win on the same key. Compose small files (`Inventory.stockCount2` + `Inventory.saveSucceeds`) instead of copying big ones. Every request needs one: a miss ends the CLI with a network violation.

## Add a screen

1. `Core/Sources/InventoryCore/<Name>ViewModel.swift` — the shape above, `@Observable public final class`, services and callbacks through `init`.
2. `Core/Sources/InventoryCore/<Name>ViewModel+Introspection.swift` — `IntrospectionProviding` with a private `Node`: PascalCase action titles, one per `Action` case. Inputs are `nonisolated struct <Action>Input: IntrospectionInput { …; static let fields = [...] }` (without `nonisolated` the default MainActor isolation breaks the conformance).
3. A `Route` case and a push from the ViewModel that opens it; the navigator's node picks it up.
4. `Mobile/<Name>View.swift` — reads `state`, sends actions, nothing else; add the route to `RootView`.
5. A behavior test before any of the above is done.

A tab instead of a pushed screen (or a real screen for a placeholder tab): a `MainTab` case (title in Core, icon in `RootView`), its node in `TabNavigator`'s `child`, its view in `RootView`, and a journey in `behavior/tabs.test.mjs`.

## Write a behavior test

In `behavior/*.test.mjs` (Node's runner, no dependencies):

```js
const session = createBehaviorSession({ fixtures: [fixture('Inventory.stockCount2'), fixture('Inventory.saveSucceeds')] });
t.after(() => session.close());
await session.precondition('InventoryList', ({ state }) => assert.equal(state.isLoading, false));
await session.do({ action: 'SelectProduct', payload: { id: 1 }, expectation: ({ name }) => assert.equal(name, 'InventoryDetail') });
await assert.rejects(session.do({ action: 'Fly' }), /unknown action "Fly"/);
```

- One journey per fixture set; fold its steps into one test. Separate tests only when the fixtures differ.
- Expect something the action changes (or provably keeps). An expectation already true before the action proves nothing.
- `do` polls `ls` for up to 2 s, then fails with the last state it saw. Read that state before touching code.
- Always close the session (`t.after(() => session.close())`): `close()` asks once more, so a network violation caused by the last step still fails the test.
