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
3. **Clean up**, in two layers:
   - **Rules, always** (~1 ms): hesitations (um, uh), stuttered English function words ("the the"), spacing and sentence capitalisation. Meaning-bearing words ("like", "so", "matlab") and Hindi reduplication ("jaldi jaldi") are left alone.
   - **AI, opt-in** from the menu: *AI Cleanup: Off (default) / Fast (Qwen3-1.7B, ~0.6 s) / Thorough (Qwen3-4B-Instruct, ~1.3 s)*, a local MLX model that also removes fillers and false starts and fixes punctuation. Its rewrite is used only if `AICleanupGuard` confirms it deleted nothing but fillers (at punctuation boundaries) and nearby repeats, added no words and stayed in English letters; otherwise, and on timeout (4 s) or failure, the rules output is used and the reason is logged.
   - **script**: output is always English letters and Western digits (user requirement). The Hinglish model writes Roman script itself; `LatinScriptSpeechToText` transliterates any Devanagari or Arabic-script run that slips through.
   - Code editors and terminals (bundle-ID list) get the raw transcript: no cleanup at all.
4. **Insert**: AX direct insert where the focused element supports it, else clipboard paste (`⌘V`) with the previous clipboard restored afterwards — unless the user changed the clipboard in the meantime.

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

Borderless, non-activating `NSPanel` (never takes focus; on all Spaces and over full-screen apps) on the screen holding the focused window of the app being dictated into.

- **MacBook (notched display):** the notch itself grows **down into a panel** (NotchNook-style). Its top corners flare into the menu bar through concave shoulders; the camera sits in the panel's top row, flanked by the target app (icon + name) and the mode chip (Hinglish / English). The body below shows the state.
- **Other displays:** the **same panel** floats just below the menu bar, with fully rounded corners and a header row in place of the camera row.

States (one state machine; one spring drives size, corners and content: opening response 0.42 / damping 0.8, closing 0.45 / 1.0; Reduce Motion → fades):

| State | Body |
|---|---|
| Idle | Hidden (collapses back into the notch / a small pill) |
| Listening | Mic badge (orange, pulsing; command mode gets its own colour, ticket 11), scrolling live waveform, timer |
| Transcribing | The same bars roll as a wave; "Transcribing" |
| Inserted | Badge morphs into a green ✓, bars flatten, "Inserted"; collapses after 0.9 s |
| Acting | (ticket 11) parsed command, step list, countdown |
| Error | Red badge with a short shake, message in place of the waveform, "Details"; click expands the details, click "Close" dismisses |

`Esc` while `fn` is held cancels (it's a chord, see ticket 01); the keyboard tap is listen-only, so the focused app also receives the `Esc`. The dictation transcript is *not* previewed before insertion (speed first).

### 4.6 Custom dictionary

Hand-edited list of words/names (e.g. "Gurjeet", product names). Used as an STT prompt hint (Whisper initial prompt) and as LLM cleanup context.

### 4.7 History & privacy

- Transcripts stored locally (SQLite), searchable from the menu bar, "Clear history" button.
- Audio retention **off** by default; opt-in setting.
- No telemetry/analytics. No network calls except model downloads and user-selected cloud providers.

### 4.8 Onboarding (first run)

Guided window, one step at a time. It opens on first launch and whenever a pinned model is missing (e.g. after an update pins a new one), and can be reopened from the menu ("Setup Guide…"):
1. Welcome.
2. Permissions with a live ✓ each and an Allow… button (system prompt, else the right System Settings pane): Microphone, Accessibility (insert text, drive apps), Input Monitoring (`fn` key event tap).
3. Download of **everything** from **Hugging Face** (~6.5 GB: Whisper turbo 1.6 GB, the Hinglish model 1.6 GB, cleanup Fast 1.0 GB and Thorough 2.3 GB): progress with time left, resumable after quitting or a dropped connection (Try Again), every file SHA-256-verified against the manifest built into the app (ADR 0010), stored in `~/Library/Application Support/open-voice-flow/models/`.
4. Preparing: the first load, where Core ML compiles the speech models for this Mac's Neural Engine (up to ~15 min once, cached afterwards), shown as an estimated progress bar with elapsed time.
5. "Try it": Done unlocks once a dictation has gone through the real pipeline (Skip available).

## 5. Models & providers

| Role | Default (local) | Alternatives |
|---|---|---|
| STT | Two modes from a picker: **Hinglish** (default) = `Oriserve/Whisper-Hindi2Hinglish-Apex` (turbo-sized, Roman-script output) converted by this project to WhisperKit Core ML from pinned weights; **English** = Whisper large-v3-turbo | Cloud BYOK (Deepgram, ElevenLabs, OpenAI); Parakeet via FluidAudio (English) |
| LLM | Cleanup: opt-in Fast = Qwen3-1.7B / Thorough = Qwen3-4B-Instruct (4-bit, MLX-Swift); intents (ticket 11) TBD | Gemma 4 E2B; Ollama; cloud BYOK (Claude Haiku 4.5, OpenAI, Groq) |

All settings are stored internally as a single `Mode` (STT provider + LLM provider + prompt + language/script), so multiple Modes later is a UI change only.

## 6. Architecture

Swift packages, each depending only on those above it:

```
Core        Session pipeline, Mode, provider protocols (SpeechToText, AudioRecorder, TextInserter, TextCleaner; ActionAdapter arrives with ticket 11), cleanup rules and guard
Audio       Mic capture, silence trim, current input level
STT         WhisperKit, FluidAudio/Parakeet, cloud providers
LLM         MLX-Swift (Qwen), Ollama, cloud providers
Insertion   AX insert, clipboard paste + restore
ModelStore  Pinned model manifests (generated by scripts/make-manifests.py), resumable checksum-verified downloads
Onboarding  First-run flow (state machine), window and views
Actions     Cancellable step runner with progress events; SlackAdapter
NotchUI     Overlay panel, state machine, geometry, waveform levels, animations
App         Menu bar, hotkeys (CGEventTap), wiring (onboarding services), settings, history
EvalRunner  Dev tool: runs the app's pipeline (Audio + STT + cleanup) over the eval clips for scripts/eval (not shipped)
```

- A **Session** = one hotkey press: start → audio → transcript → result (insert or action) → end. Future hands-free / conversational modes are new session kinds, not a rewrite.
- Every step sits behind a protocol so it can be tested with fakes. A future hosted (paid) service is just another `SpeechToText` / `TextCleaner`.
- Packages are added by the ticket that first needs them (NotchUI in 04, LLM in 05, ModelStore and Onboarding in 07, Actions in 11) rather than created empty up front.

## 7. Quality targets

- **Latency** (on the slowest team Mac, M1 baseline): key release → text inserted **< 1.5 s** for a 10 s utterance with AI cleanup off (the default; Fast adds ~0.6 s, Thorough ~1.3 s); command → parsed command visible **< 2 s**.
- **Accuracy**: tracked as WER on a personal eval set (§8); any model/prompt change must not regress it.

## 8. Evaluation set

- [`eval/reading-script.md`](eval/reading-script.md): numbered items read in one recording with ~2 s pauses.
- Script splits the recording on silence, pairs chunks with item text, writes `eval/clips/NN.wav` + `eval/clips/manifest.json`.
- Second script runs a given STT (+ optional cleanup) over the set and reports WER per language and latency.
- Audio recordings are personal data: `eval/clips/` and raw recordings are git-ignored.

## 9. Open items to settle during implementation

- Exact Core ML conversion settings for the Hinglish Whisper model and its real-world latency on M1.
- Verify structured-output reliability for `send_message` on Hinglish input (MLXGuidedGeneration; Qwen3-4B-Instruct is the starting point).
- Slack AX tree details for reading `⌘K` results and the DM header (may vary by Slack version).
