# 19. Learning from corrections

Status: Accepted · 2026-11-23 (v2 ticket 15)

## Context
- **The ticket:** after a paste, the app watches the field for a short while. When the same one-word fix
  ("gurujit" → "Gurjeet") happens twice within 7 days, it offers to add the word to the dictionary. Only word
  pairs are kept, locally, and the feature can be switched off.
- **The dictionary respells by sound** (ADR 0011), so a name heard roughly right is fixed once it's a term. Words
  heard as something else, or never added, keep coming out wrong; the user fixes them by hand.
- **The session already knows what it pasted.** The field is read through Accessibility, as the inserter and Undo
  Formatting do. Electron apps and browsers expose their fields only once asked (ADR 0016).

## Decision
- **Watching** (`CorrectionWatch`, through a `PastedField`, read by `AccessibilityPastedField`):
  - Right after a dictation's text is in, the focused field is followed. The paste must end at the cursor, so the
    text before and after it is known. A ⌘V is applied by the app a moment later, so the field is read again for
    up to 1 s until the paste shows.
  - It's read every 0.5 s until 30 s pass, focus moves to another element, or the next dictation or a successful
    Undo Formatting ends it.
  - Each read is compared word by word with what was pasted, without the punctuation around words. It counts only
    when the text around the paste is as it was, and each change is one word for one word. More words may follow
    a kept last word.
  - A fix counts once two reads in a row show it, so a word half typed doesn't. The last such fixes are learned
    when the watch ends, if learning is still on. A word fixed and sent within a second (Enter in Slack) isn't
    learned: that's the price of never learning half a word.
  - A last word followed by new ones isn't learned: "Supa base" for "supabass" looks the same as a fix followed by
    typing.
  - Not watched: commands (never pasted), snippets (their text is the user's own), password fields, and a field
    over 50,000 characters, which would be read in full twice a second.
- **Learning** (`DictionaryStore`, the user's choices, 2026-11-23):
  - A fix counts only when its new word is a name or term: not ordinary English by the spell check ("their" →
    "there", "the" → "The"), with an English letter, and not already in the dictionary.
  - The same fix in two dictations within 7 days (the fixed word in any case) suggests the new word; the same
    word fixed twice in one dictation is once. Only fixes of the last 7 days are kept, the two words and the date:
    older ones go at launch or the next fix, and all of them go when learning is switched off.
  - Accepting adds the word to the dictionary. Turning it down means it's never suggested again.
- **The offer:** the notch says it ("Add “Supabase” to your Dictionary? Menu bar → Add") for 4 s, and takes no
  click. A suggestion usually comes as the next dictation starts (which ends the watch), so it waits until the
  notch is free, after that dictation's ✓; several show in turn. The menu bar menu lists each suggestion with
  **Add “…” to Dictionary** and **Don't Suggest “…”** until one is chosen.
- **On by default**, with a switch in Settings → Privacy (the user's choice, as the SPEC said).
- **The log** says how each watch went (the field unreadable, the paste not found, or how it ended and how many
  one-word fixes it saw) and when a word was learned: never the word or the field's text.

## Consequences
- **Only where the field can be read.** A paste in Slack with line breaks or a list doesn't end at the cursor as
  pasted (ADR 0016), so it isn't watched. A browser's field is found only if its accessibility is already on: the
  app doesn't turn it on to learn, since that slows the browser (ADR 0017).
- **Fixes after 30 s, or after moving to another field, aren't learned.** Nor is a fix made by retyping a whole
  phrase.
- **The field's text is read in memory twice a second for up to 30 s** while learning is on; it's never kept.
