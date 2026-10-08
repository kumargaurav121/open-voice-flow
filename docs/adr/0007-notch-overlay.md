# 7. Notch overlay as the primary UI

Status: Accepted · 2026-10-08 · Amended 2026-10-08 (ticket 04)

## Context
Macs have no Dynamic Island API; apps like NotchNook/Boring Notch fake it with a borderless window.

## Decision
A non-activating `NSPanel` above the menu bar on the active screen, growing out of the notch; a same-shaped pill at top centre on non-notched screens. Six states: Idle, Listening, Transcribing, Inserted, Acting, Error.

## Consequences
Consistent look everywhere; custom window/animation work we own.

## Amendment (ticket 04)
User feedback ("it looks like a fake notch") and research into boring.notch, DynamicNotchKit, NotchDrop,
Atoll and NotchNook changed the design: on a MacBook the notch grows **down into a panel** with concave
shoulders (the shape that makes these apps read as the hardware notch growing), content below the camera
row. On displays without a notch the **same panel** floats below the menu bar, at the user's request,
rather than a fake notch. Details in SPEC §4.5.
