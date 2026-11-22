# 15. The widened cleanup guard: layout and self-corrections

Status: Accepted · 2026-11-20 (v2 tickets 09, 11)

Amended by ADR 0017 (v2 ticket 13): a third widening, for email only. The rewrite may add line breaks, keeping
every spoken one between the same words.

## Context
- **The AI cleanup's rewrite is used only if `AICleanupGuard` accepts it** (ADR 0004). Until v2 it could delete only
  fillers and nearby repeats, add at most 20% new words, and had to keep half the text.
- **v2 formatting needs two more things:**
  - Layout: dictation now has line breaks ("new line", ticket 09) and numbered lists (ticket 10).
  - Self-corrections (ticket 11): "four, actually no, let's make it five" should become "five". That deletes
    words that carry meaning, which the guard rejected.
- The spec allowed exactly two widenings, and everything else the guard rejected was to stay rejected.

## Decision
- **Layout (ticket 09):**
  - The rewrite must keep exactly the same line breaks, or the rules text is used (the user's choice). Fast put
    eval item 42 on one line and Thorough merged its paragraph break.
  - A list number opening a line ("1.", "2)") is layout on both sides: never a new word, and never standing in
    for a spoken one.
  - Lists don't need the AI: they are laid out by rules after the AI pass (ticket 10).
- **Self-corrections (ticket 11):**
  - They are looked for only when today's rules reject a rewrite, so every rewrite accepted before still is.
  - The guard aligns the rewrite with the spoken words to find the dropped runs. A dropped run counts as a
    correction if:
    - it is at most 12 words, its marker included, with at least one word before the marker: the mistake;
    - the kept words right after it are the fix, and replace the mistake word for word: as many words, at least
      one changed and at most half ("two tickets" → "three tickets", "teen baje hai" → "chaar baje hai");
    - a one-word mistake is swapped for its own kind: a number for a number ("four" → "five"), a name for a name.
  - Repeated words can be aligned two ways (to their earliest or latest spoken copy); both must find only
    corrections. Matched one way, "Meeting teen baje hai aaj, nahi nahi, chaar baje hai, office mein" →
    "Meeting teen baje hai, office mein" looks like "baje hai aaj" replaced by "baje hai office".
  - The alignment is skipped for dictations over about 500 words (`maxAlignment`); they get no corrections.
  - Code review found what a looser rule (any run with a marker and a word before it) let through: the fix
    dropped instead of the mistake ("Book two tickets, no wait, three tickets" → "Book two tickets"), and markers
    that weren't corrections ("We can't do Friday, sorry, I'll call you tomorrow" → "I'll call you tomorrow",
    "We actually no longer support Windows" → "Support Windows"). All are tests now.
    - The markers are "actually no", "no wait", "scratch that", "I mean", "sorry", "nahi nahi", and "nahin
      nahin" as the Hinglish model writes it.
    - Each run needs its own marker. The spec said one span; eval item 41 has two corrections.
  - With a correction, the rewrite may add no word at all. Otherwise "five" could become "six".
  - The rest is checked as before: other deletions must be fillers or repeats.
- **The shared prompt (local and cloud)** asks for self-corrections, with English and Hinglish examples, and one
  where "actually" and "sorry" stay. It also asks to keep each word spelled as it is: Thorough had written
  "chaar" as "chhār".

## Consequences
- **Eval items 40, 41 and 44** (word errors against the expected output):

  | Cleanup | 40 | 41 | 44 |
  |---|---|---|---|
  | Off | 70% | 100% | 0% |
  | Fast | 70% | 100% | 0% |
  | Thorough | 0% | 0% | 0% |
  | Cloud (Groq) | 0% | 0% | 0% |

  - Thorough and cloud keep only what was meant. The exact text still differs in punctuation from the speech
    model ("five at" for "five, at").
  - Fast doesn't correct: it leaves 40 as said, and on 41 it drops only the markers, which is rejected.
  - On 44, Thorough drops the "actually" of "I actually enjoyed the demo"; the guard rejects that and the rules
    text is pasted.
- **All clips, before and after** (36 English on Parakeet, 22 Hindi and Hinglish on the Hinglish model; runs
  `p11-before-*`, `p11-final-*`, and `p11-items-*` for the table above):
  - English Fast stays at 7.5% word errors. Thorough goes from 7.5% to 7.9%, mostly item 40's correction: the
    references are the spoken script, so a correction counts as deleted words.
  - Hinglish Fast stays at 15.4%. Thorough goes from 15.5% to 16.4%, all of it item 41's two corrections.
  - Rewrites rejected: English 10 → 9 (Fast) and 9 → 5 (Thorough); Hinglish 3 → 4 (Fast) and 3 → 5 (Thorough).
  - Other differences are punctuation, or a rewrite flipping between accepted and rejected. One regression:
    Fast turned clip 10's question into a statement ("…bhej sakte hain?" → "…hain."); the guard doesn't check
    question marks.
- **Real corrections the guard can't verify are rejected,** which is safe (the rules text is pasted):
  - a fix of a different length: "I'll come, no wait, I won't come" → "I won't come";
  - a repeated word the two alignments place differently: "Send Priya the deck, no wait, the report" → "Send
    Priya the report";
  - a contraction or other new word next to the fix: "I am free on Monday, sorry, Tuesday" → "I'm free on
    Tuesday".
- **What it can still accept:** a one-word number or name swap that wasn't meant as one ("Meet at four, sorry,
  five people are coming" → "Meet at five people are coming").
- **With AI cleanup off, self-corrections stay as spoken.**
- **A dictation with a spoken line break gets no correction** if the AI drops the break: the rewrite is rejected
  under the break rule. The prompt doesn't ask the AI to keep line breaks.
