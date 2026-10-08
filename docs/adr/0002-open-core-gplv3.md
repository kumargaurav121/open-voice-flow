# 2. GPLv3 open-core; paid = hosted services only

Status: Accepted · 2026-10-08

## Context
Personal → team → public open source, with possible paid features later.

## Decision
The app is GPLv3 and fully functional locally. Paid features are hosted services (cloud STT/LLM without API keys, team dictionary/adapters, sync) and signed convenience builds — never features locked inside the app.

## Consequences
Pipeline steps are provider protocols from day one; a hosted service is just another provider. GPLv3 keeps forks open (same model as VoiceInk). No Mac App Store (sandbox forbids Accessibility automation).
