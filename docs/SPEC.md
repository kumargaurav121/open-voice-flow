# open-voice-flow — v1 Spec

An open-source macOS dictation app (in the spirit of Wispr Flow / SuperWhisper) that also executes voice commands, with a notch-based "Dynamic Island" style UI.

Decisions behind this spec are recorded in [`adr/`](adr/). Anything deferred lives in [`ROADMAP.md`](ROADMAP.md).

## 1. Goals

- **Dictation that is very accurate** in English, Hindi and Hinglish, inserted into any app.
- **Voice commands** that visibly drive apps on screen and can be stopped mid-way. v1 ships exactly one: *send a Slack DM*.
- **Local-first**: works offline after setup, nothing leaves the Mac unless the user picks a cloud provider.
- **Open-core ready**: everything in the app is open (GPLv3); future paid features are hosted providers plugged into the same interfaces.

## 2. Non-goals (v1)

Live/streaming transcription, hands-free sessions, conversational agent, multiple Modes, per-app tone, auto-learned dictionary, agent-loop automation, browser Slack, Intel Macs, telemetry, hosted backend. See ROADMAP.

## 3. Platform

- Apple Silicon (M1+), **macOS 14 Sonoma or later**.
- Native **Swift + SwiftUI**, AppKit for the overlay window. Menu-bar app (`LSUIElement`), no Dock icon.
- Not sandboxed, not on the Mac App Store (Accessibility automation is incompatible with the sandbox).
- Distribution v1: build from source. Personal/dev builds signed with a free Apple ID "Personal Team" (Apple Development cert) so TCC grants persist across rebuilds. Paid Developer ID + notarization + Sparkle + Homebrew cask only before public release.

## 4. User-facing behaviour

### 4.1 Hotkeys (configurable)

| Action | Default | Behaviour |
|---|---|---|
| Dictate | hold `fn` | Record while held; on release → transcribe → clean up → insert at cursor |
| Command | hold Right `⌥` | Record while held; on release → transcribe → parse intent → run action |
| Cancel | `Esc` | Cancel recording, processing, or a running action at any step |

Push-to-talk only. Very short presses (< ~250 ms) are ignored.

### 4.2 Dictation pipeline

1. **Capture** mic audio (16 kHz mono) while key held; trim leading/trailing silence.
2. **Transcribe** with the configured STT provider (default: Hinglish Whisper via WhisperKit, local).
3. **Clean up** with the configured LLM provider (default: Qwen3.5-2B 4-bit via MLX-Swift, local):
   - remove fillers ("um", "matlab", repeated words), fix punctuation/casing,
   - apply custom dictionary spellings,
   - **script normalisation**: default output is Latin script (Devanagari → romanised Hinglish); setting to keep Devanagari,
   - neutral style everywhere. **Skipped entirely** when the frontmost app is a code editor or terminal (bundle-ID list).
4. **Insert**: AX direct insert where the focused element supports it, else clipboard paste (`⌘V`) with the previous clipboard restored afterwards — unless the user changed the clipboard in the meantime.

The cleanup step is optional (setting); if disabled or it fails/times out, the raw transcript is inserted.

### 4.3 Command pipeline

1. Capture + transcribe as above (with cleanup applied to the message text).
2. **Parse intent** with the LLM using constrained/structured output into one of the known actions:
   ```
   send_message(app: "slack", to: String, text: String)
   ```
   The LLM only extracts the *name as spoken*; it never resolves people.
3. Notch shows the parsed command: `→ Slack · Gurjeet · "I'll be late"`.
4. **Run the adapter** (§4.4), streaming step progress to the notch.
5. Unknown / unparseable command → notch: "Can't do that yet", transcript copied to the clipboard. Never fall back to typing it.

### 4.4 Slack adapter (v1's only action)

Targets the **Slack desktop app** only (`com.tinyspeck.slackmacgap`). If not installed → error state.

Scripted, visible UI automation via Accessibility + synthetic keystrokes:

1. Activate/launch Slack, wait until frontmost.
2. `⌘K` → type the spoken name → wait for results.
3. Read the top result via AX. If nothing reasonably matches the spoken name → abort with "Couldn't find <name>".
4. `Enter` to open the DM; verify the conversation header via AX.
5. Insert the message text into the composer (paste).
6. **3-second countdown** in the notch: `→ Gurjeet Singh · "I'll be late" · sending in 3s [Esc]` (duration configurable).
7. Press `Enter` to send. On `Esc` at any step: stop, leave everything as-is on screen.

Each step has a timeout; failure at any step → error state naming the step.

### 4.5 Notch overlay

Borderless, non-activating `NSPanel` at the top centre of the **active screen**, above the menu bar, on all Spaces. On notched displays it hugs and grows out of the notch; on non-notched displays it renders as a pill of the same shape at top centre.

States (one state machine, all transitions animated):

| State | Visual |
|---|---|
| Idle | Invisible (just the hardware notch) |
| Listening | Widens; live waveform; colour differs for Dictate vs Command |
| Transcribing | Shimmer/spinner |
| Inserted | Brief ✓, collapses |
| Acting | Expands down: parsed command, then step list with ✓ / spinner, countdown |
| Error | Short red message; click for details |

The dictation transcript is *not* previewed before insertion (speed first).

### 4.6 Custom dictionary

Hand-edited list of words/names (e.g. "Gurjeet", product names). Used as an STT prompt hint (Whisper initial prompt) and as LLM cleanup context.

### 4.7 History & privacy

- Transcripts stored locally (SQLite), searchable from the menu bar, "Clear history" button.
- Audio retention **off** by default; opt-in setting.
- No telemetry/analytics. No network calls except model downloads and user-selected cloud providers.

### 4.8 Onboarding (first run)

Guided window with live ✓ per item:
1. Microphone permission.
2. Accessibility permission (insert text, drive apps).
3. Input Monitoring permission (`fn` key event tap).
4. Model download from **Hugging Face** (STT ~1.6 GB, LLM ~1.5 GB) — progress, resumable, checksum-verified, stored in `~/Library/Application Support/open-voice-flow/models/`.
5. "Try it" box to test dictation.

## 5. Models & providers

| Role | Default (local) | Alternatives |
|---|---|---|
| STT | `Trelis/whisper-hinglish-preview` converted to WhisperKit Core ML, published by this project on Hugging Face | Whisper large-v3-turbo (interim fallback until conversion exists); Parakeet via FluidAudio (English-only, faster); cloud BYOK (Deepgram, ElevenLabs, OpenAI) |
| LLM | Qwen3.5-2B 4-bit via MLX-Swift (4B when RAM allows) | Gemma 4 E2B; Ollama; cloud BYOK (Claude Haiku 4.5, OpenAI, Groq) |

All settings are stored internally as a single `Mode` (STT provider + LLM provider + prompt + language/script), so multiple Modes later is a UI change only.

## 6. Architecture

Swift packages, each depending only on those above it:

```
Core        Session pipeline, Mode, provider protocols (SpeechToText, AudioRecorder, TextInserter; LLMProvider and ActionAdapter arrive with tickets 05 and 11)
Audio       Mic capture, silence trim, waveform levels
STT         WhisperKit, FluidAudio/Parakeet, cloud providers
LLM         MLX-Swift (Qwen), Ollama, cloud providers
Insertion   AX insert, clipboard paste + restore
Actions     Cancellable step runner with progress events; SlackAdapter
NotchUI     Overlay panel, state machine, animations
App         Menu bar, hotkeys (CGEventTap), onboarding, settings, history, model downloads
```

- A **Session** = one hotkey press: start → audio → transcript → result (insert or action) → end. Future hands-free / conversational modes are new session kinds, not a rewrite.
- Every step sits behind a protocol so it can be tested with fakes. A future hosted (paid) service is just another `SpeechToText` / `LLMProvider`.
- Packages are added by the ticket that first needs them (NotchUI in 04, LLM in 05, Actions in 11) rather than created empty up front.

## 7. Quality targets

- **Latency** (on the slowest team Mac, M1 baseline): key release → text inserted **< 1.5 s** for a 10 s utterance including cleanup; command → parsed command visible **< 2 s**.
- **Accuracy**: tracked as WER on a personal eval set (§8); any model/prompt change must not regress it.

## 8. Evaluation set

- [`eval/reading-script.md`](eval/reading-script.md): numbered items read in one recording with ~2 s pauses.
- Script splits the recording on silence, pairs chunks with item text, writes `eval/clips/NN.wav` + `eval/manifest.json`.
- Second script runs a given STT (+ optional cleanup) over the set and reports WER per language and latency.
- Audio recordings are personal data: `eval/clips/` and raw recordings are git-ignored.

## 9. Open items to settle during implementation

- Exact Core ML conversion settings for the Hinglish Whisper model and its real-world latency on M1.
- Verify Qwen3.5-2B structured-output reliability for `send_message` on Hinglish input; step up to 4B if needed.
- Slack AX tree details for reading `⌘K` results and the DM header (may vary by Slack version).
