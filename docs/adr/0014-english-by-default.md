# 14. English as the default language

Status: Accepted · 2026-11-20 (v2 ticket 08)

## Context
- **Hinglish has been the default mode since the first version.**
  - The bake-off of 2026-10-08 chose a Hinglish / English picker.
  - Hinglish mode understands English, Hindi and the two mixed.
- **Hinglish mode is worse on English.**
  - On the 17 English clips of eval set 2, the Hinglish model scored 11.9% word errors, against Whisper turbo's
    8.0% in English mode (`docs/eval/reports/2026-11-13-eval-set-2-baseline.md`, the scorer of the time).
  - The gap is mostly on short sentences: 19.1% against 7.7% on the 10 short clips.
- **English mode now runs Parakeet (ADR 0013).**
  - It scores 7.3% on the same 17 clips (after ticket 07's scorer fixes).
  - In the app log it took 0.36-0.53 s at release (2026-11-20). The Hinglish model took 0.80-1.10 s on shorter
    dictations (2026-11-18/19).

## Decision
- **A new install starts in English.**
  - `Mode.language` defaults to English.
  - The settings are saved on first launch, so a later change of default never switches an install.
- **A saved choice is never changed.**
  - Every saved `Mode` holds its language, and it is read back as saved.
  - Installs from before Modes (October 2026) saved a language only when one was picked. One that saved other
    settings, or finished setup, but no language keeps Hinglish, which it ran.
  - A missing or unknown language in saved settings falls back to English. The app always saves the language,
    so this happens only with a newer version's value or a hand edit.
  - Unreadable settings reset every field to its default, the language included.
- **Hinglish is one click away:**
  - Its note in the picker (menu and Settings) says when to use it: "Understands Hindi and mixed speech and
    writes it in English letters. Less accurate on pure English, and slower."
  - Setup's Try It step says that Hindi or mixed speech needs Hinglish, under Language in the menu bar. It
    doesn't name the selected language, since setup also reopens for existing users.
- **Setup still downloads every model.** Switching to Hinglish needs no download.

## Consequences
- **A Hindi speaker who skips the setup text starts in English mode.** Parakeet doesn't know Hindi, so Hindi
  comes out as wrong English until they switch. Picking the language automatically isn't on the roadmap.
- **Every new install now starts on Parakeet.**
  - In the app, Parakeet got 1 of its first 3 English dictations right (2026-11-20). The audio wasn't kept.
  - Ticket 20 compares it with Whisper on the app's own recordings.
  - Parakeet's restarts ("from the from about") are ticket 19.
- **Installs that ran before keep their language.** Only new installs start in English.
