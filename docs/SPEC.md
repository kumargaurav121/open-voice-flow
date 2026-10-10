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

Push-to-talk only. Very short presses (< ~250 ms) are ignored. In Settings → General, Dictate and Command can each be any of fn, Right ⌥, Right ⌘, Right ⌃, Right ⇧ (held alone, so they never type or clash with app shortcuts); the two must differ. Cancel isn't rebindable: Esc, or any other key pressed while a hotkey is held.

### 4.2 Dictation pipeline

1. **Capture** mic audio (16 kHz mono) while key held; trim leading/trailing silence.
2. **Transcribe** with the configured STT provider (default: Hinglish Whisper via WhisperKit, local). Optional cloud: Deepgram Nova-3 with the user's own key (Hinglish mode asks for its multilingual code-switching, English mode for English; the dictionary goes as key terms). If it fails or takes over 8 s, the dictation is transcribed locally instead and the reason logged.
3. **Clean up**, in two layers:
   - **Rules, always** (~1 ms): hesitations (um, uh), stuttered English function words ("the the"), spacing and sentence capitalisation. Meaning-bearing words ("like", "so", "matlab") and Hindi reduplication ("jaldi jaldi") are left alone.
   - **AI, opt-in** from the menu or Settings: *AI Cleanup: Off (default) / Fast (Qwen3-1.7B, ~0.6 s) / Thorough (Qwen3-4B-Instruct, ~1.3 s) / Cloud (OpenAI or Groq with the user's own key, same instructions)*, a local MLX model that also removes fillers and false starts and fixes punctuation. Its rewrite is used only if `AICleanupGuard` confirms it deleted nothing but fillers (at punctuation boundaries) and nearby repeats, added no words and stayed in English letters; otherwise, and on timeout (4 s) or failure, the rules output is used and the reason is logged.
   - **script**: output is always English letters and Western digits (user requirement). The Hinglish model writes Roman script itself; `LatinScriptSpeechToText` transliterates any Devanagari or Arabic-script run that slips through.
   - Code editors and terminals (bundle-ID list) get the raw transcript: no cleanup at all.
4. **Insert**: AX direct insert where the focused element supports it, else clipboard paste (`⌘V`) with the previous clipboard restored afterwards — unless the user changed the clipboard in the meantime.

### 4.3 Command pipeline

1. Capture + transcribe as above, with the dictionary, English letters and the rules cleanup, but **no AI cleanup** (it would add up to ~1.3 s, could reword the command itself, and would send it to the cloud with Cloud cleanup on). Deepgram still applies if chosen for speech-to-text. Esc cancels until the result is shown.
2. **Parse intent**: direct phrasings by rule ("Message Gurjeet saying …", "Send a message to Priya on Slack: …", "Gurjeet ko message karo ki …"), instant and exact; anything else (reported speech like "Tell Rohan he can merge", "Priya ko bolo ki … jaaye") by the local LLM (Qwen3-1.7B, on this Mac, never the cloud) as JSON validated against the schema (not grammar-constrained): invalid, a recipient the speaker didn't name, or any other app means unknown, and the message gets the dictation text rules. Accuracy and timing: docs/eval/reports/2026-10-10-commands.md (1.7B: under 2 s, lenient 4/5; the 4B: 5/5 but over 3 s). The model loads while the key is held. The structured output is:
   ```
   send_message(app: "slack", to: String, text: String)
   ```
   The LLM only extracts the *name as spoken*; it never resolves people.
3. Notch shows the parsed command in the Command colour: `→ Slack · Gurjeet · "I'll be late"`. Until the adapter exists (ticket 12) the message text is copied to the clipboard. Commands are saved to history with what they did.
4. **Run the adapter** (§4.4), streaming step progress to the notch.
5. Unknown / unparseable command → notch: "Can't do that yet", transcript copied to the clipboard. Never fall back to typing it.

### 4.4 Slack adapter (v1's only action)

Targets the **Slack desktop app** only (`com.tinyspeck.slackmacgap`). If not installed → error state.

Scripted, visible UI automation via Accessibility + synthetic input, run by `ActionRunner` (each step has a timeout; the notch lists the steps live). Before every key press, click or paste, Slack must still be in front and the step not stopped (Esc or timeout); keys never go to another app. Built against what Slack's Accessibility tree really exposes (Electron: `AXManualAccessibility` turns it on):

1. **Open Slack** (opening, not just activating, so a window comes back if none is open); wait for its main window.
2. **Find the person**: `⌘K` opens Slack's search; the spoken name is pasted (Slack ignores synthetic typing). Suggestions mix people ("Gurjeet Singh, Direct Message"), "Search for: …" and recent messages, and nothing marks the highlighted row, so `Enter` on the top row is never used. The person rows are matched to the spoken name by sound (`RecipientMatch`): none → "Couldn't find <name>"; **more than one** (e.g. two "Gurpreet Singh") → "More than one <name>: …" (user decision: strict); exactly one → its full name.
3. **Open the DM** by clicking that row (a plain click from a private event source; a leaked ⌘ makes Slack open a new window); the focused window's title must change to `<Display Name> (DM) - …` naming that person (a DM already open counts only if it shows the full name).
4. **Write the message**: a draft already in that DM is left alone and the action stops; otherwise paste (paste only, so it can't land twice) and require the composer to hold exactly the message.
5. **Countdown** in the notch: `→ Gurjeet Singh · "I'll be late" · sending in 3s` with Esc (Settings → General, 1-10 s, default 3).
6. **Send**: re-check it's still that DM with exactly that message, check for Esc one last time (the point of no return), press `Return`, confirm the composer emptied. After Return the outcome is never "nothing sent": an unconfirmed send is reported as "probably sent".

`Esc` at any step, including the countdown, stops and leaves the screen as it is (a pasted draft stays unsent). Any failure shows the reason, names the step on click, and copies the message to the clipboard so it isn't lost. While an action runs, the hotkeys are ignored. History records what happened ("· Sent on Slack", "· Stopped, nothing sent", "· Not sent: …").

### 4.5 Notch overlay

Borderless, non-activating `NSPanel` (never takes focus; on all Spaces and over full-screen apps) on the screen holding the focused window of the app being dictated into.

- **MacBook (notched display):** the notch itself grows **down into a panel** (NotchNook-style). Its top corners flare into the menu bar through concave shoulders; the camera sits in the panel's top row, flanked by the target app (icon + name) and the mode chip (Hinglish / English). The body below shows the state.
- **Other displays:** the **same panel** floats just below the menu bar, with fully rounded corners and a header row in place of the camera row.

States (one state machine; one spring drives size, corners and content: opening response 0.42 / damping 0.8, closing 0.45 / 1.0; Reduce Motion → fades):

| State | Body |
|---|---|
| Idle | Hidden (collapses back into the notch / a small pill) |
| Listening | Mic badge (orange, pulsing; cyan for a command), scrolling live waveform, timer |
| Transcribing | The same bars roll as a wave; "Transcribing" |
| Inserted | Badge morphs into a green ✓, bars flatten, "Inserted"; collapses after 0.9 s |
| Command | Cyan: parsed command (`→ Slack · Gurjeet · "…"`), or "Can't do that yet" with "Copied" (the transcript); 3 s, then closes |
| Acting | The panel grows to list the action's steps: ✓ done, a spinner on the running step, hollow circles for the rest; the header shows who (the resolved full name once found) and the message, with an `esc` key cap. The send row becomes the countdown: a draining ring and "Sending in 3s" |
| Sent / Stopped | Green ✓ "Sent to Gurjeet Singh", or "Stopped, nothing sent" after Esc; "Probably sent: check Slack" (orange) if Return was pressed but Slack didn't confirm |
| Error | Red badge with a short shake, message in place of the waveform, "Details"; click expands the details, click "Close" dismisses |

`Esc` while a hotkey is held cancels the recording (a chord, see ticket 01); `Esc` on its own stops a command being understood or an action at any step before the send. The keyboard tap is listen-only, so the focused app also receives the `Esc`. The dictation transcript is *not* previewed before insertion (speed first).

### 4.6 Custom dictionary

Hand-edited list of words/names (e.g. "Gurjeet", product names), edited in Settings → Dictionary and stored locally. After speech-to-text, anything that sounds like a term is respelled the user's way (both modes); the list is also LLM cleanup context. Not a Whisper prompt: the Hinglish model ignores it (ADR 0011).

### 4.7 History & privacy

- Each dictation's final text, time, frontmost app and mode stored locally (SQLite, `~/Library/Application Support/open-voice-flow/history/`), kept until cleared. Text that couldn't be inserted is saved too, marked "Not inserted", so it isn't lost.
- Menu bar: **Recent** (last 10, click to copy) and **History…** (the newest 500; search covers everything; copy, delete, "Clear History…" with confirmation).
- Deleted text is overwritten in the database (SQLite secure delete), and the history folder is excluded from Time Machine, so deleting really removes it.
- Audio retention **off** by default; opt-in ("Keep audio recordings" in Settings → Privacy): a WAV per dictation, deleted with its entry and by Clear History.
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
| STT | Two modes from a picker: **Hinglish** (default) = `Oriserve/Whisper-Hindi2Hinglish-Apex` (turbo-sized, Roman-script output) converted by this project to WhisperKit Core ML from pinned weights; **English** = Whisper large-v3-turbo | **Cloud BYOK (ticket 10): Deepgram Nova-3**. Later: ElevenLabs, OpenAI; Parakeet via FluidAudio (English) |
| LLM | Cleanup: opt-in Fast = Qwen3-1.7B / Thorough = Qwen3-4B-Instruct (4-bit, MLX-Swift); intents (ticket 11): rules first, then local Qwen3-1.7B | **Cloud BYOK (ticket 10): OpenAI-compatible, OpenAI or Groq**, as AI Cleanup "Cloud". Later: Claude Haiku 4.5; Gemma 4 E2B; Ollama |

Settings are stored as a single `Mode` value: language, AI cleanup choice, STT provider, cloud LLM (service + model) and hotkeys, as versioned, leniently decoded JSON (unknown values fall back to defaults; settings from before Modes were migrated). The cleanup prompt is shared (`CleanupPrompt`), not per Mode yet. App-wide settings stay outside the Mode: dictionary, audio retention, onboarding state. API keys live only in the Keychain (`APIKeys`), never in preferences or logs; logs record a provider's status code, never its message. So multiple Modes later is a UI change only.

## 6. Architecture

Swift packages, each depending only on those above it:

```
Core        Session pipeline, Mode, provider protocols (SpeechToText, AudioRecorder, TextInserter, TextCleaner, CommandModel; ActionAdapter arrives with ticket 12), PushToTalkSession, command rules and schema, cleanup rules and guard
Audio       Mic capture, silence trim, current input level
STT         WhisperKit (local); FluidAudio/Parakeet later
LLM         MLX-Swift (Qwen), local; Ollama later
Cloud       Opt-in providers with the user's own keys: Deepgram STT, OpenAI-compatible cleanup; Keychain key storage
Insertion   AX insert, clipboard paste + restore
History     Local transcript history (system SQLite) and opt-in audio
ModelStore  Pinned model manifests (generated by scripts/make-manifests.py), resumable checksum-verified downloads
Onboarding  First-run flow (state machine), window and views
Actions     Cancellable step runner with progress events; SlackAdapter
NotchUI     Overlay panel, state machine, geometry, waveform levels, animations
App         Menu bar, hotkeys (CGEventTap), wiring (onboarding services), Settings window, history window
EvalRunner  Dev tool: runs the app's pipeline (Audio + STT + cleanup) over the eval clips for scripts/eval (not shipped)
```

- A **Session** = one hotkey press: start → audio → transcript → result (insert or action) → end. Future hands-free / conversational modes are new session kinds, not a rewrite.
- Every step sits behind a protocol so it can be tested with fakes. A future hosted (paid) service is just another `SpeechToText` / `TextCleaner`.
- Packages are added by the ticket that first needs them (NotchUI in 04, LLM in 05, ModelStore and Onboarding in 07, History in 09, Actions in 11) rather than created empty up front.

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
