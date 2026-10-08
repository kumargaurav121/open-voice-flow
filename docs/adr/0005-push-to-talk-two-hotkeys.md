# 5. Push-to-talk with separate dictation and command hotkeys

Status: Accepted · 2026-10-08

## Context
Misreading dictation as a command (e.g. sending a Slack message) is costly. Always-on wake words hurt privacy and battery.

## Decision
Hold `fn` = dictate, hold Right `⌥` = command (both configurable), `Esc` = cancel. Unknown commands show "Can't do that yet" and copy the transcript; they never fall back to typing.

## Consequences
Predictable behaviour; one more shortcut to learn. AI intent classification on a single key is a later option.
