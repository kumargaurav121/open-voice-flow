# 5. Push-to-talk with separate dictation and command hotkeys

Status: Accepted · 2026-10-08

## Context
Misreading dictation as a command (e.g. sending a Slack message) is costly. Always-on wake words hurt privacy and battery.

## Decision
Hold `fn` = dictate, hold Right `⌥` = command (both configurable), `Esc` = cancel. Unknown commands show "Can't do that yet" and copy the transcript; they never fall back to typing.

## Consequences
Predictable behaviour; one more shortcut to learn. AI intent classification on a single key is a later option.

## Amendment (ticket 10)
Configurable in Settings among held modifier keys only (fn, Right ⌥, Right ⌘, Right ⌃, Right ⇧): a modifier
never types a character or triggers an app shortcut while held. Dictate and command must be different
keys; a clash is refused. Cancel stays Esc (or any key pressed while a hotkey is held) and isn't
rebindable.
