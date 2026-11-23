# 22. Restarts: three narrow rules, English dictation only

Status: Accepted · 2026-11-23 (v2 ticket 19)

## Context
- **Parakeet writes the speaker's restarts as said** (ADR 0013): "dropped from the from about", "We also We are
  also". On the 36 English clips they were 11 of its words in error, almost all of its gap to Whisper (6.8%
  against 6.1%; `docs/eval/reports/2026-11-18-parakeet-in-english-mode.md`).
- **Ordinary speech repeats too:** "very, very", "I know, I know", "it is what it is", "over and over", "the end of
  the week or the end of the month", "add it to the to do list", "per person", "six sixteen", "log in. Login".
  Removing words from those changes what was said.
- **The first rules took those words out.** The reviews traced them on dozens of such phrases. Tightened, the
  rules can't tell three of the six eval restarts from ordinary speech:
  - clip 63 "older lap laptops" has the shape of "per person";
  - clip 6 "next js. Next.js" crosses a full stop like "log in. Login";
  - clip 61 "to the team, to the beta group" reads as a list.

## Decision
- **Three narrow rules** (`SpokenRestarts`, in the rules cleanup before numbers become digits), the user's choices
  of 2026-11-23:
  - **An abandoned start:** a function word, one or two words, then that word again, within a sentence. The words
    dropped must come back right after, in order ("We also We are also"). Or they're an article given up before a
    function word or a number ("from the from about"), so "to the to do list" and "for a for loop" stay. The same
    words twice are meant ("I know, I know", "over and over and").
  - **A word broken off:** a lowercase run of consonants, not a title, that the next word starts with as said ("the
    tw twenty-eighth", "tw 28th"). A real word is never one ("per person", "six sixteen", "PR process").
  - **The same words written two ways within a sentence** ("e mail email"). Written the same way twice, or with
    only an apostrophe between them ("it's its own"), it's meant.
- **Clips 6, 61 and 63 stay as said** (the user's choice: safe rules over coverage).
- **English dictation only** (the user's choice): Hinglish keeps its repeats ("jaldi jaldi") and its particles.
  Commands keep theirs too.
- **Undo Formatting brings a restart back** (the user's choice): it's a guess, like spoken punctuation, so the text
  before formatting is the rules cleanup without it.

## Consequences
- **Eval (run `t19-safe-v2-long`, Parakeet at speaking pace as in the app):** on the 32 English clips without the
  formatting items (38-44):

  | | Word error rate |
  |---|---|
  | Whisper (`p07all-turbo-rt`) | 5.9% |
  | Parakeet before (`p07all-v2-long`) | 6.9% |
  | Parakeet with these rules | 6.5% |

  - Clips 35, 51 and 58 lost their restarts, 5 words; clip 57's "six.15" became "6:15" (an earlier fix). No other
    word changed.
  - **0.6 points behind Whisper: the ticket's 0.5 bar is missed by 0.1.** The restarts left as said (clips 6, 61
    and 63, 6 words) are about that.
  - On all 36 clips it's 7.1% against 6.1%. But Whisper's run predates spoken punctuation and lists, which the
    scorer counts as errors on items 39 and 42 (their references are the words said).
  - The first, looser rules (`t19-v2-long`) took out 8 words here, clips 6 and 63 too, but the reviews traced them
    taking words out of ordinary speech.
- **Restarts left as said:** a fragment with a vowel ("deplo deploy"), a contraction ("I'm I am"), a rephrasing ("we
  have to we need to"), a repeat across a full stop, and clips 6, 61 and 63.
