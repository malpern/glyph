# Reader — Architecture & Rationale

A cross-device EPUB reader. This repo is the **iPhone client** — the first of an
intended ecosystem (iPhone → iPad → Mac → a non-Apple X4/Crosspoint e-ink reader).
The long-term value is **cloud-synchronized reading state**; Phase 1 is the smallest
high-quality *local* reader that the sync layer can grow into without a rewrite.

## Phase 1 scope

Import EPUBs · show a library · open a book · remember the reading location ·
reopen to that exact location. Nothing else — no auth, cloud, AI, TTS, or DRM.

## Foundational decisions

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

## Build & run

```sh
brew install xcodegen          # one-time
xcodegen generate              # regenerate Reader.xcodeproj from project.yml
open Reader.xcodeproj
# or: xcodebuild -project Reader.xcodeproj -scheme Reader \
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

### Phase 2 seams (already in place)
- **Sync engine** plugs in behind `LibraryRepository` / `ReadingStateRepository`;
  records already carry `updatedAt` + `deletedAt` tombstones, `ReadingState` carries
  `pendingSync`. No CloudKit (non-Apple device target).
- **Shared clients** (iPad/Mac): `ReaderCore` is UI-free and Readium-free — reusable as-is.
- **TTS / highlights / notes**: positions are Readium `Locator`s end to end; `Bookmark`
  and `Highlight` models and storage already exist (unused in Phase 1).

See `/Users/malpern/.claude/plans/dreamy-beaming-sphinx.md` for the full plan.
