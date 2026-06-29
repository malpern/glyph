Review the diff of this pull request for **Glyph**, a SwiftUI iOS EPUB reader
(Swift 6, targets iOS 27). The shared logic lives in `Packages/ReaderCore` (a
UIKit-free, Readium-free Swift package); `App/` and `Features/` hold the SwiftUI
app, Readium navigator bridge, and Firebase sync.

Report only **high-priority issues** — be terse and specific:

- **P0** — correctness bugs, crashes, data loss, or security/secret-handling
  problems. The reading-position sync (last-writer-wins, dirty outbox) and the
  X4 `(spine, paragraph)` ↔ Readium addressing are the highest-risk areas: a
  silent off-by-one or conflict-resolution mistake corrupts a reader's position
  across devices, so scrutinize those closely.
- **P1** — missing test coverage for new logic, concurrency issues (this code is
  built under Swift strict concurrency), or clear API/contract violations.

Skip style nits, naming preferences, and speculative refactors. If the diff is
clean, say so in one line. Reference findings by `file:line`.
