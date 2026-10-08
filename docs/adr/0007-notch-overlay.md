# 7. Notch overlay as the primary UI

Status: Accepted · 2026-10-08

## Context
Macs have no Dynamic Island API; apps like NotchNook/Boring Notch fake it with a borderless window.

## Decision
A non-activating `NSPanel` above the menu bar on the active screen, growing out of the notch; a same-shaped pill at top centre on non-notched screens. Six states: Idle, Listening, Transcribing, Inserted, Acting, Error.

## Consequences
Consistent look everywhere; custom window/animation work we own.
