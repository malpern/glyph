# Testing Glyph

The guiding principle: **the fast tier carries the load.** Almost all logic lives
in `Packages/ReaderCore` — a UIKit-free, Readium-free, Firebase-free Swift package
— so it tests with plain `swift test` in well under a second, no simulator, no
network. Keep it that way: when you add logic worth testing, push it *down* into
ReaderCore behind a protocol rather than testing it through the app target.

## Tiers

| Tier | What | Command | Where it runs |
|------|------|---------|---------------|
| **1 — ReaderCore unit** | Sync engine, persistence, parser, X4 protocol codec. Pure logic over protocols, fakes for I/O. | `make test` | Every save (local) + every PR (CI) |
| **2 — App / Features unit** | View-model behavior, Firebase client vs the **Firestore emulator**, keychain/auth. Needs the app target + simulator. | `make test-app` | Pre-push (local, opt-in) + every PR (CI) |
| **3 — Integration / E2E** | Emulator round-trip convergence, a few XCUITest smoke flows. | (see below) | CI only (UI: nightly) |
| **Manual** | X4 e-ink page-follow over WebSocket, TTS/AirPods. Hardware/AV-dependent. | TestFlight + `/verify` | By hand |

### Tier 1 — the inner loop (this is where new tests go)

```bash
make test          # swift test on ReaderCore — sub-second, no simulator
make test-watch    # re-run on change (needs: brew install watchexec)
```

ReaderCore has **no third-party dependencies**, so this build never fetches
Readium or Firebase. That's deliberate and worth protecting — it's why the loop is
fast. Current coverage: `SwiftDataStore` persistence, `ReadingStateSyncEngine`
conflict/convergence (last-writer-wins, dirty outbox, edit-during-push), the
`SpineParser`/sentence segmenter, and the `RemoteCommand`/`RemoteEvent` X4 codec.

**Highest-value places to deepen:**
- **Sync engine** — the data-loss surface. Clock-skew ties, delete-vs-update
  races, offline→online flush ordering, three-device convergence.
- **Parser** — paragraph numbering must match X4's expat 1-based indexing; drift
  here silently desyncs the e-ink follow. Add golden tests against real EPUB HTML
  fixtures.
- **Protocol codec** — malformed/forward-compatible JSON, unknown-command
  rejection.

**Make more things Tier 1:** extract pure logic out of `LibraryViewModel` /
`ReaderViewModel` (locator→spine resolution, import dedup, bookmark tracking) into
ReaderCore functions behind the existing repository protocols. Then they test here
instead of needing the simulator.

### Tier 2 — app target (slower, simulator)

Not wired up yet. To add it: create an iOS unit-test target in `project.yml`,
`xcodegen generate`, then `make test-app`. Reserve it for what genuinely needs the
app target — view models still coupled to Readium, the `FirebaseSyncClient`
transport against the local **Firestore emulator** (never prod), key derivation.

### Tier 3 — integration / E2E

- **Firebase emulator round-trip:** two in-process clients sync through the
  emulator → assert convergence. High value, no prod dependency. Start the
  emulator with `firebase emulators:start --only firestore`.
- **XCUITest smoke:** launch → import a fixture EPUB → open reader. Expensive, so
  keep it to a handful; CI nightly only.

## CI (GitHub Actions)

`.github/workflows/ci.yml` runs **Tier 1 on every push and PR** — fast because it
needs no simulator. As Tier 2/3 land, add them as separate jobs (and push the
XCUITest job to a nightly cron so PR latency stays low).

## Code review

PRs are reviewed by **Codex** via the official Codex GitHub App (auto-review on
open; trigger a re-review by commenting `@codex review`). This is a hosted
integration — there's no workflow file or API key in this repo for it.

## Conventions

- **Swift Testing**, not XCTest: `@Suite` / `@Test` / `#expect` / `#require`.
- Fakes are in-file `actor`/`struct` conformances to the real protocols
  (e.g. `FakeRemote` in `SyncEngineTests.swift`) — no mocking framework.
- In-memory stores via `ReaderStore.make(inMemory: true)`; each test is isolated.
