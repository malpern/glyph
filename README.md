# Glyph

A cross-device EPUB reader for iOS — the first client of a reading ecosystem
(iPhone → iPad → Mac → a non-Apple e-ink reader) built around one idea: **your
exact place, your highlights, and read-aloud, everywhere.**

Today Glyph imports EPUBs, renders them beautifully, remembers your reading
position, and **syncs that position across devices** through a key-based account —
no passwords typed anywhere. Highlights and text-to-speech are next.

## Status

- **Phase 1 — local reader:** import · library · open · resume. ✅
- **Phase 2a — cross-device position sync (Firebase):** ✅ verified on two devices.
- **Next:** bookmarks/highlights sync · in-reader live jump · TTS · iPad/Mac/e-ink clients.

See **[PROJECT.md](PROJECT.md)** for the full architecture and rationale.

## Stack

- **Swift 6 / SwiftUI**, iOS 27, MVVM, Observation, strict concurrency (`complete`)
- **[Readium](https://github.com/readium/swift-toolkit)** for EPUB rendering and
  the standardized `Locator` position model (never page numbers)
- **SwiftData** for the local store (source of truth), behind repository protocols
- **Cloud Firestore** as a sync transport (free Spark tier); the engine is
  backend-agnostic and lives in the dependency-free `ReaderCore` package

```
App/         SwiftUI app — composition root, navigation, Readium + Firebase boundaries
Features/    Library · Reader · Import · Settings
Packages/
  ReaderCore/  UI-free, Readium-free, backend-free: models · repositories · sync engine
```

## Build

```sh
brew install xcodegen
xcodegen generate
open Glyph.xcodeproj          # or: xcodebuild -scheme Glyph -destination 'platform=iOS Simulator,name=iPhone 17' build
swift test --package-path Packages/ReaderCore
```

`GoogleService-Info.plist` is committed (Firebase client config is app-embedded,
not a secret); data is protected by Firestore rules (`request.auth.uid`), and the
public API key is restricted to this app's bundle id and the Firebase APIs it uses,
so it can't be reused elsewhere. Auth uses a sync key the app turns into a real
Firebase login — see PROJECT.md. DEBUG-only launch hooks (`READER_*`) exist for
headless simulator testing and never ship.

Licensed under the [MIT License](LICENSE).
