# Glyph — status & next steps

Living roadmap for the **Glyph / iOS** side of the two-device (phone "brain" + X4 e-ink)
synchronized-reading system. The firmware agent's handoff (what the X4 provides and
requests) is preserved verbatim at the bottom as the canonical contract reference.

## Where the phone is now (built)

- **Phase 1 — local reader.** Import EPUB → library → open → resume. Readium navigator
  behind a SwiftUI/`Locator` boundary; SwiftData behind repository protocols; positions
  are always Readium `Locator`s (never page numbers).
- **Phase 2 — cloud sync.** Firebase (Firestore + Auth), key-based real auth, reading-
  position sync with last-writer-wins on `updatedAt`. Firebase confined to the App layer;
  `ReaderCore` stays dependency-free.
- **Phase 3 — X4 integration.** TTS → AirPods (`SpeechController`), page-follow (`goto`),
  per-sentence highlight to the X4, lock-screen / AirPods media controls, auto-reconnect +
  re-announce, and a bidirectional position bridge (phone adopts the X4's reported `pos`).
- **Reader settings.** Theme (light / sepia / dark), text size, line spacing, font —
  persisted app-wide, applied live via Readium `EPUBPreferences`.
- **In-phone read-aloud highlighting.** The unit being read aloud is highlighted on the
  phone screen and kept in view, driven by the *same* raw-spine segmentation that drives
  AirPods + the X4. Implemented as a Readium text-locator `Decoration` (`tts` group) —
  Readium fuzzy-matches the text in the page DOM, so no precise DOM range is needed. See
  `SpeechController.spokenSentence`, `ReaderViewModel.ttsLocators`, `EPUBReaderView`.
- **Read-aloud granularity setting.** One **Sentence / Paragraph / Page / Off** setting
  (default **Sentence**) drives the phone highlight, the page-follow cadence, *and* what's
  emitted to the X4 — `highlight{spine,para,sent}` / paragraph mark `highlight{spine,para}`
  (`sent` omitted) / `goto{spine,para}` / nothing (Off = audio-only). In Paragraph/Page the
  follow target only changes per paragraph, so the page turns at most once per paragraph
  (fixes per-sentence follow jumpiness). `RemoteCommand.highlight`'s `sentence` is now
  optional. See `HighlightGranularity`, `RemoteSessionController`.
- **Bookmarks & highlights.** Bookmark the current page; select text → **Highlight** (4
  colours); both listed in one **Annotations** sheet (Bookmarks | Highlights) with
  tap-to-jump + swipe-to-delete; tap a highlight to recolour/delete. Persisted via SwiftData
  behind `ReadingStateRepository` (each record carries its own `updatedAt`/`deletedAt`, so
  sync is a drop-in later). Highlights render via a `highlights` decoration group. See
  `AnnotationsView`, `HighlightStyle`, `ReaderHostController`, `ReaderViewModel`.
- **Deploy pipeline.** `fastlane` lanes (`beta`, `register_app_id`, `add_internal_tester`,
  `tf_status`) — autonomous build → TestFlight via the App Store Connect API key. Live on
  TestFlight as **"Glyph: Read & Listen"** (`dev.malpern.Glyph`). Apple capability +
  recipe documented in `~/.config/agent/ACCESS.md`.

## Next (prioritized)

1. **X4 real-device end-to-end test** (page-follow + sentence highlight + position bridge,
   across all three granularities). Gated on hardware. (Task X4.)
2. **Sync bookmarks & highlights.** The records are sync-ready (id + `updatedAt`/`deletedAt`);
   extend the engine (or add parallel ones) + Firestore collections so annotations follow
   the same cross-device path as reading position.
3. **Follow refinement (optional).** Paragraph/Page cadence already removes most
   per-sentence jumpiness. A further nicety: suppress auto-follow briefly after a *manual*
   page turn (so re-reading isn't yanked), or only re-center when the unit is off-screen.
4. **Reverse-resume**: open the X4 → it jumps to the phone's newer cloud position. Gated on
   the firmware adding a freshness marker to `ready` so the phone knows whose position wins.
5. **Release-build optimization.** Currently archived with `SWIFT_OPTIMIZATION_LEVEL=-Onone`
   to dodge a Swift optimizer crash compiling SwiftSoup (a Readium dep) in Release.
   Confirmed present in **both Xcode 27 beta 1 (27A5194q) and beta 2 (27A5209h)**; `singlefile`
   did not help. It's an unfixed toolchain bug — revisit on the next toolchain bump
   (`fastlane beta` re-test is one command). Negligible impact for a reader app.
6. **TTS voice selection.** Firmware noted the phone and X4 voices "both sound like OpenAI
   voices." Pin the intended `AVSpeechSynthesisVoice` and surface a picker.
7. **`pos` local authority.** When the X4 user turns a page with the physical buttons, the
   phone should pause TTS and follow. The bridge adopts the position; confirm the
   pause-TTS-on-`pos` behavior end-to-end.

---

## Reference: from the firmware side (X4 agent handoff)

Handoff for the **Glyph / iOS agent**. The X4 firmware side of the synchronized-
reading experience is built and device-verified. This is what the firmware now
provides and what the phone should build next.

**Canonical protocol/addressing** lives in the firmware-planning repo:
`x4-auto-reader/docs/addressing-contract.md`
(local sibling: `/Users/malpern/local-code/x4-auto-reader/docs/addressing-contract.md`).
Messages there are tagged `[LIVE]` (device-verified) vs `[PLANNED]`. The LIVE
commands you need are summarized inline below, so this doc is usable standalone.

### 1. Highlight-granularity setting (NEW — please build)

The X4 e-ink refresh is slow: every time the highlight moves, the whole screen
does a ~half-second refresh/flash. So **how often** the highlight moves is the
dominant UX lever. Give the user a setting (Glyph Settings) to choose granularity.
The firmware supports all of these today:

| Setting | What the phone sends, and when | Refresh frequency |
| --- | --- | --- |
| **Sentence** | `{"cmd":"highlight","spine":S,"para":P,"sent":N}` on each spoken **sentence** | every few seconds (most flashing) |
| **Paragraph** | `{"cmd":"highlight","spine":S,"para":P}` (omit `sent`) on each new **paragraph** | every ~15–60s (calm) — **[LIVE]** |
| **Page-only** | `{"cmd":"goto","spine":S,"para":P}` on each new paragraph (no highlight mark) | only on page turns |

- **Paragraph mode is now LIVE.** `highlight` with `para` but no `sent` marks the
  whole paragraph with a calm **left-margin accent bar** (not a heavy full invert).
  Ack: `{"evt":"hl","spine":S,"para":P,"sent":-1,"ok":bool}` (`sent:-1` = paragraph).
- **Default:** undecided — pick it by feel after a real continuous-TTS read-along
  (we have never actually watched sentence highlighting at natural speaking pace).
  Likely **Paragraph** for the listen-on-AirPods-and-glance use case; **Sentence**
  for active read-along. Make it a setting and let the user choose.
- Implementation is trivial on your side: it's just *which command you emit and how
  often*. The firmware executes whatever you send.

### 2. Local authority on `pos` (LIVE on firmware — wire up the phone half)

When the user turns a page on the X4 with the physical buttons, the device emits
`{"evt":"pos","spine":S,"para":P}` and ignores inbound nav for ~1s. The phone must
treat `pos` as **"user took control": pause TTS and follow to that position.** Don't
fight it. (Verified at TTS cadence; a pathological command rate can starve the
device's button polling, so don't flood commands — one per sentence/paragraph.)

### 3. Reconcile on connect (LIVE)

`{"evt":"ready","spine":S,"para":P,"file":"<path>"}` arrives on connect with the
device's current position + book file. Use it to reconcile/resume so the two sides
start in sync.

### 4. Keep driving sync per the contract

`goto{spine,para}` (page-follow) and `highlight{spine,para,sent}` (sentence) are
LIVE. Address by the `<p>`-ordinal rule in the contract (count `<p>` in the RAW
spine bytes; do NOT use Readium's ContentElement index). Sentence segmentation must
match the device's `. ! ? …` rule.

## Notes / open items for the phone

- **TTS voice:** observed that the spoken voice "didn't match — both sound like
  OpenAI voices." That's entirely phone-side (your TTS/voice selection); worth
  pinning down which engine/voice you intend and why two sources sound alike.
- When you ship a feature that depends on a firmware message, confirm its tag is
  `[LIVE]` in the contract; ping the firmware side if you need a `[PLANNED]` one.
