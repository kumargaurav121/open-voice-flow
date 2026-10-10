# 6. Visible, scripted UI automation for actions

Status: Accepted · 2026-10-08

## Context
The user wants to watch actions happen on screen and stop them if they go wrong.

## Decision
LLM → structured intent → per-app scripted adapter that drives the real app via Accessibility + synthetic keys, run by a cancellable step runner that streams progress to the notch. Irreversible steps (send) wait behind a 3 s countdown; `Esc` stops at any step. v1 ships only the Slack desktop DM adapter.

## Consequences
Works without API tokens; fully visible. Brittle to app UI changes — adapters need per-version maintenance. An agent-loop fallback and official-API adapters are roadmap items.

## Amendment (ticket 11)
The LLM's output is only ever an intent for the adapter, never text typed into an app: an unknown
command shows "Can't do that yet" and puts the transcript on the clipboard. The recipient must be a name
the speaker actually said, so a hallucinated or injected name can't reach the adapter.

## Amendment (ticket 12)
The Slack adapter never presses Return on a list it can't read: Slack's ⌘K suggestions put "Search for: …"
and duplicate names among the people, so the adapter reads the person rows, requires exactly one sound match
(else aborts), clicks that row, and verifies each step's result (the DM's window title, the drafted message,
an empty composer after sending). The name and message are pasted, since Slack ignores synthetic typing.

