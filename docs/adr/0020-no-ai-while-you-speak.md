# 20. AI formatting while you speak: not built; AI Cleanup stays off by default

Status: Accepted · 2026-11-23 (v2 ticket 16)

## Context
- **The ticket:** with AI cleanup on, clean each part in the background as it's transcribed while the user speaks
  (ADR 0012), with the previous part as context, so at release only the tail waits for the AI. Then measure the
  time AI adds at release, and decide with the user whether AI cleanup is on by default.
- **Background cleanup can only hide behind parts already transcribed while speaking.** English mode, the
  default (ADR 0014), cuts Parakeet's audio only after 40 s of speech (ADR 0013, for accuracy). A shorter English
  dictation has no text until release, so its AI pass can't start earlier.
- **The user's app log, 2026-10-08 to 2026-11-23:**

  | | |
  |---|---|
  | Dictations | 201 |
  | Cut into parts while speaking | 4 (2%) |
  | Longer than 40 s | 7 |
  | AI cleanups at release | 19: mean 2.2 s, slowest 3.9 s |
  | AI cleanups that hit the 4 s limit | 2 |

## Decision
- **Per-part AI cleanup isn't built** (the user's choice, 2026-11-23). It would change how the live transcriber
  joins parts, and need a joint pass where a self-correction spans a cut, to help about 2% of dictations.
- **AI Cleanup stays off by default** (the user's choice): at release it adds 2.2 s on average. Without it, text
  is in about 0.4 s after release (the median on 2026-11-20).

## Consequences
- **AI Cleanup's cost stays at release:** about 2 s with Thorough. Fast is quicker but doesn't lay out an email
  (ADR 0017).
- **Revisit** if English is cut at shorter pauses again, or the local AI gets several times faster.
