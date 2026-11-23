# 18. Snippets

Status: Accepted · 2026-11-23 (v2 ticket 14)

## Context
- **The ticket:** saved snippets, a short cue and a longer text, managed like the Dictionary. Saying a cue as the
  whole dictation pastes its text exactly as saved, skipping cleanup and formatting. A cue inside a longer
  dictation doesn't trigger, commands never match, and it works in both languages.
- **The SPEC's order puts the snippet match first**, before the rules cleanup, and a match skips everything else.
- **What the speech models write:** the cue's words with their own capitals and punctuation ("My address."),
  sometimes with a filler. Parakeet writes numbers as words, and the rules cleanup writes 10 and up as digits but
  leaves one to nine as words (v2 ticket 07).

## Decision
- **A cue matches when it's the whole dictation, whatever its case, punctuation and fillers** (the user's choice,
  2026-11-23; the SPEC named only case and punctuation):
  - The cue is compared as typed. What was said is compared as said first, then after the rules cleanup (fillers
    out, 10 and up in digits). So "ER diagram" said is that cue's, and a cue's own filler-like word ("uh oh") must
    be said: "Oh." alone isn't "uh oh".
  - Each side is lowercase words of letters and digits: an apostrophe joins ("what's" is "whats"), other
    punctuation splits ("follow-up" is "follow up"), accents go, and each digit is its word.
  - So "Um, MY EMAIL!" matches "my email"; "call nine", "call nine one one" and "room fifteen" match the cues
    "call 9", "call 911" and "room 15".
  - Devanagari from the Hinglish model is in English letters by then (`LatinScriptSpeechToText`).
- **Everywhere, code editors and terminals included** (the user's choice): the match comes before the style, so a
  saved address or prompt can go into a terminal. Nothing else changes there: a non-cue dictation still gets the
  raw transcript.
- **Undo Formatting puts back the cue as said**, through the rules cleanup ("My email."), the user's choice; in a
  code editor or terminal exactly as said, as for any dictation there. A cue said by accident costs one keystroke,
  like any other formatting (ADR 0016).
- **Commands never match:** the command pipeline has no snippets.
- **The store** (`SnippetStore`, like `DictionaryStore`): an ordered list of cue and text, saved as JSON in local
  preferences, edited in place.
  - Both are trimmed. Every dictation is trimmed before it's pasted, so what's saved is what's pasted.
  - A cue needs an English letter or a digit beyond fillers: transcripts are in English letters, and a cue of
    fillers alone ("um") would match a hesitation. A cue said the same way as another's ("My Email!") is refused.
  - Each saved snippet is read on its own: one unreadable or duplicate entry drops only itself.
- **Settings → Snippets**, a tab next to Dictionary in the same style: the list with + and −, and below it the cue
  and a multi-line text.
  - Selecting a snippet edits it. Add or Save (or Return in the cue), with a beep when the cue is taken.
  - Clicking away keeps an edit, as the Dictionary's does; `+` keeps a draft under way.
  - The text box makes no smart quotes, dashes or text replacements, so "--flag" stays as typed.
- **The log** says "Snippet pasted", never the cue or the text. History keeps the pasted text, as for any
  dictation.

## Consequences
- **No AI, no style, no guard** for a snippet: it's pasted exactly as saved, even in a chat app whose style would
  drop a final full stop.
- **A snippet's text isn't held to "English letters and Western digits"**, the rule for what the speech models
  write: it's the user's own text, pasted as typed.
- **Not matched:** Hindi number words for a cue's digits ("nau" for "9"), and a Hinglish cue the Hinglish model
  spells differently ("meraa" for "mera").
- **Trimming** drops a first line's indentation and a final line break.
- **As for any dictation:** Undo Formatting is refused in Slack for a snippet with a line break (ADR 0016), and a
  multi-line snippet pasted into a terminal puts every line at the prompt.
- **A transcript that mishears the cue doesn't match.** The comparison is exact after normalising; the dictionary's
  respellings apply to the transcript first, so a name in a cue should be the dictionary's spelling.
- **A snippet's text is pasted like any dictation:** typed in or pasted with the clipboard restored, so rich text
  isn't kept.
