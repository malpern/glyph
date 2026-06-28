# Glyph — Architecture & Rationale

**Glyph** is a cross-device EPUB reader. This repo is the **iPhone client** — the first of an
intended ecosystem (iPhone → iPad → Mac → a non-Apple X4/Crosspoint e-ink reader).
The long-term value is **cloud-synchronized reading state**; Phase 1 is the smallest
high-quality *local* reader that the sync layer can grow into without a rewrite.

## Phase 1 scope

Import EPUBs · show a library · open a book · remember the reading location ·
reopen to that exact location. Nothing else — no auth, cloud, AI, TTS, or DRM.

## Foundational decisions

### Platform: iOS 27, Swift 6 with complete strict concurrency
Deployment floor is **iOS 27.0** — the app targets the current generation, so it
adopts the latest APIs (Liquid Glass, newest SwiftUI/SwiftData) unconditionally,
with no `if #available` back-compat code. The app target builds under
**`SWIFT_STRICT_CONCURRENCY: complete`** with zero warnings in our code; Readium's
non-`Sendable` `Publication` is confined to the `ReadiumStack` boundary (the reader
gets a live publication on the main actor; import gets a `Sendable` snapshot), so it
never crosses an isolation domain. (`ReaderCore` keeps a lower floor — iOS 17 /
macOS 14 — to stay maximally reusable by future clients.)

### Rendering engine: Readium Swift Toolkit
The only actively-maintained native OSS toolkit with a **standardized, serializable
`Locator`** position model — the exact primitive cross-device resume needs.
FolioReaderKit is archived (2020); parser-only libs (EPUBKit) would force us to
rebuild pagination; commercial SDKs are paid. We pin `from: 3.10.0`.

### Position model: Readium `Locator` everywhere, never page numbers
Reading position is a serialized Readium `Locator` (`href` + `locations.progression`,
`totalProgression`, `position`, text `cfi`/`cssSelector`). It is a spec, so we depend
on it directly rather than re-wrapping it. We isolate Readium's *services*, not its
*value types*.

### Persistence: SwiftData behind repository protocols
SwiftData is fast to build and native to the Observation framework. It lives **only**
inside `ReaderCore/Persistence` behind `LibraryRepository` / `ReadingStateRepository`
protocols; features depend on protocols + pure-Codable domain structs. The storage
engine is therefore swappable, and a future sync engine slots in behind the same
protocols. **CloudKit is deliberately avoided** — the X4/Crosspoint target is non-Apple,
so sync will be a custom, portable engine.

### Stable, content-derived `bookID`
Cross-device resume only works if two devices agree on a book's identity. `bookID`
derives from the EPUB's `dc:identifier` (fallback: file SHA-256), **not** a per-import
UUID. Same book on two devices → same `bookID` → same reading state.

### Sync-ready records from day one
Every syncable record carries `id`, `updatedAt`, a soft-delete `deletedAt` tombstone,
and a `pendingSync` dirty flag — the schema an outbox-based sync engine expects.
Phase 1 doesn't sync, but adding these now avoids a later migration.

## Module layout

```
App/            SwiftUI app target (no storyboards). Composition root + DI + navigation.
Features/       Library · Reader · Import — SwiftUI views + @Observable view models.
Packages/
  ReaderCore/   UI-free, Readium-free SPM package: Models · Repositories · Persistence · Services.
project.yml     XcodeGen source of truth. The .xcodeproj is generated, not committed.
```

Dependency direction is one-way: **Features → ReaderCore**. Readium + UIKit stay at the
app/reader edge (the navigator bridge), never inside `ReaderCore`.

## Readium dependencies (Phase 1)

`ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`. The EPUB navigator in
Readium 3.10 no longer needs an HTTP server, so `ReadiumAdapterGCDWebServer` was
dropped. `ReadiumOPDS` / `ReadiumLCP` are intentionally absent.

## App icon

The icon is a bold **ampersand** — a typographic glyph, fitting the name — in a
glossy, dimensional style on an indigo-to-coral gradient. Generated with OpenAI
`gpt-image-1`; the 1024×1024 master lives at `Icon/glyph-icon-1024.png` and is
mirrored into `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
Rejected concepts are kept under `Icon/options/`.

A single 1024×1024 opaque icon is supplied; the system generates all sizes and
applies the rounded mask. (A future enhancement is a layered Icon Composer `.icon`
for the iOS 26+ Liquid Glass / tinted-icon treatments.)

The library empty-state uses the `BookArtwork` image asset — an open-book render
also generated with `gpt-image-1` (source at `Icon/generated/openai-icon.png`).

## Build & run

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerate Glyph.xcodeproj from project.yml
open Glyph.xcodeproj
# or: xcodebuild -project Glyph.xcodeproj -scheme Glyph \
#       -destination 'platform=iOS Simulator,name=iPhone 17' build
swift test --package-path Packages/ReaderCore   # Core unit tests
```

DEBUG-only launch hooks drive headless simulator verification (never in release):
`SIMCTL_CHILD_READER_AUTODEMO=1` imports the bundled sample, `…_AUTOOPEN=1` opens
it, `…_AUTOADVANCE=N` turns N pages through the real navigator → save path.

## Status — Phase 1 complete

All seven milestones built, committed, and verified on the iPhone 17 simulator:

| # | Milestone | Verified by |
|---|---|---|
| M1 | Scaffold (XcodeGen, ReaderCore, Readium) | empty app builds + launches |
| M2 | Core domain + SwiftData behind repositories | 7 round-trip unit tests |
| M3 | Import (Readium parse, stable bookID, cover) | sample imports with real cover/metadata |
| M4 | Library UI | cover grid renders |
| M5 | Reader (Readium navigator bridge) | live EPUB rendering |
| M6 | Locator-based resume | **read to Ch. VI → relaunch → resumed to Ch. VI** |
| M7 | Polish + this doc | clean Swift-6 build, no warnings in app code |

## Status — Phase 2a: cross-device position sync (Firebase) — working

Reading position now syncs across devices via Cloud Firestore (free Spark tier,
project `ios-reader-22859`). The architecture's payoff: sync slots in behind the
existing repositories with no feature rewrites.

| # | Milestone | Verified by |
|---|---|---|
| P2.1 | Firebase project + SDK (Firestore/Auth) | app builds + links Firebase 12.15 |
| P2.2 | Sync core in `ReaderCore` (engine, protocols) | 4 engine tests: convergence, LWW both ways |
| P2.3 | `FirebaseSyncClient` + wiring | push/observe over Firestore; engine started in `AppContainer` |
| P2.4 | Cross-device verify (stub user) | A read to Ch. IV → B opened to Ch. IV |
| P2.5 | Key-based real auth | **same verified over authenticated Firestore; data under `request.auth.uid`** |

**How it's built (recap):** `ReaderCore/Sync` defines `RemoteSyncClient` /
`AuthProviding` / `ReadingStateSyncStore` and a pure `ReadingStateSyncEngine`
(pull-before-push reconcile, last-writer-wins on `updatedAt`). The App layer's
`FirebaseSyncClient` implements the transport
(`users/{uid}/readingStates/{sha256(bookID)}`); Firebase never enters `ReaderCore`.
Local SwiftData stays the source of truth; Firestore is transport.

**Identity (P2.5): a key, not a password.** The user holds one high-entropy *sync
key*; the app deterministically derives a Firebase email+password from it and signs
in silently (`SyncKey` + `FirebaseKeyAuth`). So the same key on two devices →
the same account → the same data, with **no credential typed anywhere** — ideal for
the no-keyboard X4 (drop a key file) and easy on phones (copy / QR in the Sync
screen, reachable from the library toolbar). Firestore rules enforce
`request.auth.uid == userID`. Email/Password auth must be enabled once in the Firebase
console (free-tier Auth init is console-gated; the API path needs Blaze billing).

**Firebase ops:** `firebase deploy --only firestore:rules` updates rules
(`firestore.rules`); the project/app are managed via the `firebase` CLI. The
`GoogleService-Info.plist` is app-embedded config, not a secret.

### Still ahead (sync)
- **Shared clients** (iPad/Mac/X4): `ReaderCore` (UI-free, Readium-free, backend-free) reuses as-is.
- **Bookmarks/highlights + book-file sync**: the engine and models extend to these next.
- **Remove DEBUG launch hooks** before any real release.

## Status — Phase 3: X4 e-ink page-follow (TTS-driven) — phone side built

The phone is the "brain": it does TTS to AirPods and tells the X4 e-ink reader which
paragraph it's speaking, so the X4 turns its own pages to follow along. Audio is
always phone → AirPods; the X4 is a synchronized display + (later) remote.

| Piece | What | Where |
|---|---|---|
| Addressing | `<p>` start-tag scan over RAW spine bytes → 1-based ordinals matching the X4's expat count; simple-punctuation sentences | `ReaderCore/Reading` (tested) |
| Protocol | discriminated, forward-compatible `RemoteCommand`/`RemoteEvent` codec (`ping`/`goto` live) | `ReaderCore/Remote` (tested) |
| TTS | `SpeechController` — AVSpeechSynthesizer → AirPods, driven by the paragraph model, tracks `(spine,para,sentence)` | `Features/Reader` |
| Link | `X4Client` (WebSocket `ws://crosspoint.local:81`) + `RemoteSessionController` (page-follow) | `Features/Remote` |

**Verified (phone side, vs `Tools/mock_x4.py`):** app connects, and as TTS speaks each
paragraph it sends `{"cmd":"goto","para":N,"spine":S}` in order. The addressing contract
is `/Users/malpern/local-code/x4-auto-reader/docs/addressing-contract.md` (source of truth).

**To test against the real X4:** open the same EPUB on the device, press Volume Up
(it shows `ws://…:81`), then in the reader tap the broadcast icon to start the session
and ▶ to read aloud — the X4 follows. Per-sentence on-device highlight is deferred
(needs a firmware change); page-follow via `goto` is the live path.

### Still ahead (X4)
- **Start at the current page** (TTS currently starts at the first text spine).
- **Per-sentence highlight** (`highlight{spine,para,sent}`) once the firmware retains paragraph index per line.
- **Phase 4 buttons**: inbound `button` events already route into the playback controller; wire when the device sends them.

See `/Users/malpern/.claude/plans/dreamy-beaming-sphinx.md` for the full plan.
