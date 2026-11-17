# Roadmap

v1 scope is defined in [`SPEC.md`](SPEC.md). Everything below is deliberately **not** in v1.

## v1 — Dictation + one action

- Push-to-talk dictation (English / Hindi / Hinglish), local STT + local cleanup
- Command hotkey with one action: Slack DM via visible UI automation, configurable countdown (default 3 s), Esc to stop
- Notch overlay (pill on non-notched screens), onboarding, manual dictionary, local history
- Personal eval set + WER script

## v2 — Feels alive

- **Live preview**: words appear in the notch while speaking. Transcribing while you speak (cut at pauses, only the tail left at release) shipped in v2 ticket 02 (ADR 0012); the notch doesn't show the parts yet.
- **Compressed Hinglish model**: shipped in v2 ticket 05: the encoder palettized to 6 bits, a 0.8 GB download instead of 1.6 GB, back on the Neural Engine, with accuracy held (`docs/eval/reports/2026-11-17-compressed-hinglish-model.md`).
- **Multiple Modes** (SuperWhisper-style): named presets of STT + LLM + prompt + language/script, e.g. "Hinglish Chat", "English Email"; switch per app or by shortcut.
- **Per-app tone**: casual in chat, formal in email, untouched in code.
- **Auto-learned dictionary**: learn from corrections the user makes right after insertion.
- **Contacts-aware names**: seed the dictionary from macOS Contacts / Slack.
- **Disambiguation**: when several contacts match (v1 aborts with "More than one …"), pause and let the user pick with a number key.
- **More actions**: open app, Messages/iMessage, WhatsApp, web search, Linear/Jira issue, calendar event.
- **Slack in the browser** adapter.
- Configurable auto-send (no countdown) per action once trusted.

## Later — Live / active mode

Two related ideas, both built as new **session kinds** on the existing pipeline:

- **Hands-free session**: shipped in v2 ticket 04 as double-tap `fn` to start, tap to stop, 10-minute cap (no stop on silence, so pauses to think are fine). Still to come: text flowing into the app while speaking.
- **Conversational agent**: chained commands with memory — "message Gurjeet I'm late… also tell Priya… now open Linear and create a ticket for it." Needs conversation state, multi-action plans and per-step confirmation rules.

## Later — Smarter automation

- **Agent-loop fallback**: for apps without a scripted adapter, the LLM reads the AX tree, picks the next step, repeats — still visible and stoppable.
- **Official API adapters** (e.g. Slack `chat.postMessage`) where reliability matters more than visibility.
- Possibly AI intent classification so a single hotkey can do both dictation and commands.
- Apple Foundation Models provider (zero-download) for English-only users once language support/OS baseline allow.

## Open-core / paid (hosted)

The app stays fully functional and GPLv3. Paid = hosted services plugged in as providers:

- **Hosted cloud mode**: best accuracy + AI commands with no API keys.
- **Team features**: shared dictionary, shared adapters, admin settings.
- **Sync**: settings and history across Macs.
- **Signed convenience builds** with auto-updates (VoiceInk model).

## Distribution milestones

1. Build-from-source (now) — free Apple ID Personal Team signing for dev.
2. Team testing — teammates build themselves, or receive a build + "Open Anyway"/`xattr` instructions.
3. Public — Apple Developer Program ($99/yr), Developer ID + notarization, Sparkle (EdDSA appcast), Homebrew cask.
