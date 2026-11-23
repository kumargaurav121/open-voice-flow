# 21. Sentence breaks at cuts: kept on the pause rule

Status: Accepted · 2026-11-23 (v2 ticket 17)

## Context
- **The ticket:** where a dictation is cut while it's spoken (ADR 0012), the join keeps a sentence break only
  after a pause of 1 s or more. On the eval's cut clips that misses breaks the speaker made: 21 with the Hinglish
  model (7 when each clip is transcribed whole) and 9 with the English model. The candidates were a seam check (a
  second transcription across each cut), the previous part as Whisper's context, or word hints ("ne", "aur").
- **How often a dictation is cut, in the user's app log** (2026-10-08 to 2026-11-23, by the language last chosen):

  | Language | Dictations | Cut while speaking |
  |---|---|---|
  | Hinglish | 132 | 1 |
  | English | 51 | 3 |
  | Before the log named it | 18 | 0 |

## Decision
- **Not built** (the user's choice, 2026-11-23). It would change the text of about 2% of the user's dictations. The
  join keeps the pause rule (ADR 0012).

## Consequences
- **A long dictation cut while spoken can still run two sentences together, or break one,** at a cut made at a
  short pause.
- **Revisit** if dictations are cut more often (shorter English parts, ADR 0013), or with ticket 20's recordings
  from the app.
