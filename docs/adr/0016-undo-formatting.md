# 16. Undo Formatting

Status: Accepted · 2026-11-21 (v2 ticket 12)

## Context
- **v2 formatting guesses** (ADR 0015): spoken punctuation and line breaks, lists, and the AI's self-corrections.
  A wrong guess should cost one keystroke.
- **The ticket:** "Undo Formatting" (menu item and shortcut) replaces the last pasted dictation with its raw
  transcript, only if the field still ends with exactly that text; otherwise the notch says it can't.
- **A menu-bar app is never the active app**, so a menu item's key equivalent alone works only while its menu is
  open. The hotkey tap is listen-only: a shortcut it caught would also reach the focused app, and ⌥Z types "Ω"
  into the very field being undone.

## Decision
- **What comes back: the text before formatting**, not the raw transcript (the user's choice, 2026-11-21).
  - That is the rules cleanup alone: fillers stay out, and spacing, capitals and digits stay as they are. Spoken
    punctuation and line breaks, lists and the AI's changes are undone, so a spoken "comma" comes back as the word.
  - A dictation that nothing formatted has nothing to undo. Code editors get the raw transcript, so neither
    do they.
  - `CleanupSpeechToText.unformatted` keeps it for the last transcript; the session pairs it with the pasted
    text.
- **The safety check: the text just before the cursor** (the user's choice), not the end of the field.
  - Nothing may be selected, and the text right before the cursor must be exactly what was pasted. So a dictation
    into the middle of a document can be undone, and if the user has typed or clicked elsewhere since, nothing
    changes.
  - The inserter selects that text, then inserts the earlier text over it the usual way (typed in, or pasted
    with the clipboard restored). The selection is read back first: if the field ignored it, a paste would leave
    both texts in the field. If it landed elsewhere, the cursor is put back, so nothing selected gets typed over.
- **Kept until the next dictation starts, or until undone.** A refused undo can be tried again, since each try
  re-checks the text.
- **⌃⌥Z, system-wide, through Carbon's hot keys** (`RegisterEventHotKey`). The focused app never sees the
  keystroke, and no permission is needed. The menu shows ⌃⌥Z next to **Undo Formatting**, which is disabled
  when there is nothing to undo. The undo waits (up to a second) for ⌃⌥ to lift, so a ⌘V can't carry them.
- **Electron apps and Chromium browsers** expose their fields only once asked. When there is no focused field,
  the undo sets Electron's `AXManualAccessibility` on the front app (as the Slack action already does) and looks
  for the field for up to a second.
- **The notch** says "Couldn't undo formatting", with details. Often nothing was edited, so it doesn't say the
  text changed. The log gives the field's role, its length and cursor, and where the text first differs (letters
  and digits only named as such), never the text.

## Consequences
- **Checked on the user's Mac (2026-11-21):**
  - TextEdit: undone; refused after typing "!"; undone again once the "!" was deleted.
  - Slack: a one-line dictation was undone. With a line break it was refused: Slack reports a length of 27 and
    the cursor at 26 for "Hi Rohan,\nSee you tomorrow.". A pasted list becomes Slack's own formatted list, with
    a blank line above and the cursor on an empty line below, so a list can't be undone there.
  - The first undo in an Electron app that hadn't exposed its fields yet was refused even after the 1 s wait
    (Slack, Orca); the next one found the field.
  - Not checked on the device: Notes, a browser text box, and the menu item.
- **Rich-text boxes** (Slack, likely Gmail) need a different check, such as selecting and reading the selected
  text back (ticket 23).
- **Undoing doesn't change the history**, which keeps the formatted text.
- **Waking Slack's accessibility** lasts until Slack quits. Dictations into it then try the direct insert first,
  as they already did after a Slack command.
