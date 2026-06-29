# Glyph (phone) next steps — from the X4 firmware side

Handoff for the **Glyph / iOS agent**. The X4 firmware side of the synchronized-
reading experience is built and device-verified. This is what the firmware now
provides and what the phone should build next.

**Canonical protocol/addressing** lives in the firmware-planning repo:
`x4-auto-reader/docs/addressing-contract.md`
(local sibling: `/Users/malpern/local-code/x4-auto-reader/docs/addressing-contract.md`).
Messages there are tagged `[LIVE]` (device-verified) vs `[PLANNED]`. The LIVE
commands you need are summarized inline below, so this doc is usable standalone.

## Phone build list (priority order)

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
