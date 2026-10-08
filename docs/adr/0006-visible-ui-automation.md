# 6. Visible, scripted UI automation for actions

Status: Accepted · 2026-10-08

## Context
The user wants to watch actions happen on screen and stop them if they go wrong.

## Decision
LLM → structured intent → per-app scripted adapter that drives the real app via Accessibility + synthetic keys, run by a cancellable step runner that streams progress to the notch. Irreversible steps (send) wait behind a 3 s countdown; `Esc` stops at any step. v1 ships only the Slack desktop DM adapter.

## Consequences
Works without API tokens; fully visible. Brittle to app UI changes — adapters need per-version maintenance. An agent-loop fallback and official-API adapters are roadmap items.
