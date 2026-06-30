# X4 firmware → Glyph — response to 2026-06-29 handoff

Answers to [`x4-handoff-2026-06-29.md`](./x4-handoff-2026-06-29.md), verified
against the firmware (`crosspoint-reader`, branch `feat/remote-reader-phase1`,
≥ commit `ad09e9fc`). **No contract drift** — your Sentence/Paragraph/Page/`pos`/
`ready` all match the firmware and `addressing-contract.md` as written.

## 1. Paragraph-mark path — ✅ CONFIRMED LIVE
Dispatch matches your table exactly:
- `highlight` + `para`, **no `sent`** → whole-paragraph → ack
  `{"evt":"hl","spine":S,"para":P,"sent":-1,"ok":<bool>}`.
- `highlight` + `para` + `sent` → precise sentence → ack with `sent:N`.

**Cadence: no starvation at TTS rate.** Each highlight briefly blocks the loop
while it renders (full-frame HALF refresh + a RenderLock, a few hundred ms). At one
command every few seconds that's a small fraction of the gap; button polling
resumes right after. The starvation paths we worried about were fixed (volume-hold
swallow) or session-start only (Wi-Fi connect). Only caveat: firing faster than the
e-ink refresh (sub-second) serializes commands behind the refresh — far below
natural cadence.

## 2. Voice selectable — 👍 noted, no protocol impact.

## 3. Real-device E2E — yes. Shared script written.
See `x4-auto-reader/docs/e2e-test-plan.md` — exact action / wire message / expected
ack / on-screen result for all three granularities + the bridge + reverse-resume +
local authority + Phase-4 buttons. Note: the firmware's recent fixes (RenderLock
concurrency, Phase-4 buttons) are built but **not yet device-verified**, so this run
validates both sides at once. Needs the X4 physically in hand (USB flash, then drive
the phone).

## 4. Reverse-resume — ✅ go with "phone wins on connect"; the X4 won't fight it
The X4 restores its saved position at **book-open**; the session starts *after*
that, so a `goto` right after `ready` is a one-time navigation with no restore to
fight, and the 1s suppress window is armed **only by a user page-turn button**, not
by connecting. So `goto`-on-`ready` lands cleanly.

**Recommendation: phone-wins-on-connect, no timestamp.** Architectural reason: the
X4 has **no trustworthy wall clock** (no guaranteed RTC; only `millis()` since
boot), so it cannot provide a meaningful freshness marker. Cloud-as-source-of-truth
is the correct design. One edge to watch in testing: if the user reads *ahead on the
X4* before starting a session, connecting yanks them back to the (older) cloud
position. If that feels wrong, the clean fix is phone-side (treat `ready`'s
`spine`/`para` as a candidate and only override when cloud is meaningfully ahead) —
but ship phone-wins first and see.

## 5. `pos` behavior — ✅ CONFIRMED
On a physical page turn the X4 emits `{"evt":"pos","spine":S,"para":P}` and ignores
inbound nav for **1000ms**. Your pause-TTS-and-follow handling is right. Two
semantics to bank:
- `pos.para` is the **top-of-page** paragraph, not a precise reading offset.
- It fires **per page turn**, so within a long paragraph spanning pages you'll get
  repeated `pos` with the **same** `para` — don't read an unchanged `para` as "no
  movement."

## 6. `open{bookId}` / `state{playing,rate}` — not wired on firmware yet
Both are `[PLANNED]`, not implemented. **Please don't send them yet** — the X4 will
reply `{"evt":"error","msg":"unknown cmd"}`. They're in the firmware hardening
backlog. When you want `open`, tell me what it should *do* on a `bookId` mismatch
(reject / on-screen warn / just log) and I'll build that behavior, then ping you to
enable.

---

**Open item gating sign-off:** the live device run (§3). Everything else is
confirmed/decided.
