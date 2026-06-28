# Testing Glyph

The guiding principle: **the fast tier carries the load.** Almost all logic lives
in `Packages/ReaderCore` — a UIKit-free, Readium-free, Firebase-free Swift package
— so it tests with plain `swift test` in well under a second, no simulator, no
network. Keep it that way: when you add logic worth testing, push it *down* into
ReaderCore behind a protocol rather than testing it through the app target.

## Tiers

| Tier | What | Command | Where it runs |
|------|------|---------|---------------|
| **0 — App compiles** | The full app target builds (Features + App, Readium + Firebase). | `make build` | Pre-push (local) — see CI note below |
| **1 — ReaderCore unit** | Sync engine, persistence, parser, X4 protocol codec. Pure logic over protocols, fakes for I/O. | `make test` | Every save (local) + every PR (CI) |
| **2 — App / Features unit** | View-model behavior, Firebase client vs the **Firestore emulator**, keychain/auth. Needs the app target + simulator. | `make test-app` | Pre-push (local) |
| **3 — Integration / E2E** | Emulator round-trip convergence, a few XCUITest smoke flows. | (see below) | Local / future self-hosted CI |
| **Manual** | X4 e-ink page-follow over WebSocket, TTS/AirPods. Hardware/AV-dependent. | TestFlight + `/verify` | By hand |

> **Why CI only runs Tier 1.** The app targets **iOS 27 / Xcode 27**, and
> GitHub-hosted runners only ship up to **Xcode 16** — they have no iOS 27 SDK, so
> the app target can't build there. ReaderCore's `swift test` works in CI because it
> builds for the **macOS host**, not the iOS SDK. Until hosted runners catch up (or
> we add a self-hosted runner on a Mac with Xcode 27), Tiers 0/2/3 are **local
> pre-push gates**: run `make build` before pushing any change to `App/` or
> `Features/`, since CI won't catch a compile break there.

### Tier 1 — the inner loop (this is where new tests go)

```bash
make test          # swift test on ReaderCore — sub-second, no simulator
make test-watch    # re-run on change (needs: brew install watchexec)
```

> **Run via `make test`, not bare `swift test`.** The SwiftData-backed suites
> create in-memory stores that aren't safe to spin up concurrently, so Swift
> Testing's default cross-suite parallelism occasionally SIGSEGVs them. `make test`
> (and CI) pass `--no-parallel`; the suite is sub-second, so it costs nothing.

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
needs no simulator. Tiers 0/2/3 can't run on hosted CI yet (the iOS 27 / Xcode 27
SDK gap above), so they stay local pre-push gates for now. The unlock is a
**self-hosted macOS runner with Xcode 27**; once that exists, add `make build` as a
job and the XCUITest smoke flows on a nightly cron so PR latency stays low.

## Code review

PRs are reviewed by **Codex** via the official Codex GitHub App (auto-review on
open; trigger a re-review by commenting `@codex review`). This is a hosted
integration — there's no workflow file or API key in this repo for it.

## Conventions

- **Swift Testing**, not XCTest: `@Suite` / `@Test` / `#expect` / `#require`.
- Fakes are in-file `actor`/`struct` conformances to the real protocols
  (e.g. `FakeRemote` in `SyncEngineTests.swift`) — no mocking framework.
- In-memory stores via `ReaderStore.make(inMemory: true)`; each test is isolated.
