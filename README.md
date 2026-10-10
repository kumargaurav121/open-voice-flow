# Open Voice Flow

Hold a key, speak, let go: your words appear wherever you're typing. An open-source, local-first
dictation app for macOS, built for **English, Hindi and Hinglish**. It always writes English letters
(Hindi comes out as Hinglish, never translated), cleans up "um"s and false starts, and can carry out a
spoken command like *"Message Gurjeet saying I'll be late"* in Slack, visibly, with a countdown you can
stop.

Everything runs on your Mac by default. Cloud speech-to-text and AI cleanup are optional, with your own
API keys.

## Requirements

- macOS 14 or later, Apple Silicon (built and tested on an M1 Pro)
- Xcode with Swift 6 and its Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`
- An Apple ID added in Xcode (a free Personal Team is enough to sign the app)
- About 6.5 GB of disk for the models

## Build and run

```sh
scripts/build-app.sh            # builds, bundles and signs build/Open Voice Flow.app
open "build/Open Voice Flow.app"
```

The first launch opens **setup**: it asks for Microphone, Accessibility and Input Monitoring, downloads
the models from Hugging Face (pinned and checksum-verified, see ADR 0010), and lets you try a dictation.
The first load of the speech model compiles it for your Mac's Neural Engine (up to ~15 minutes, once).

## Using it

| | |
|---|---|
| **Dictate** | Hold `fn`, speak, release. Text goes into the focused field. |
| **Command** | Hold Right `⌥`, say e.g. *"Message Priya saying the deck is ready"* or *"Gurjeet ko message karo ki main meeting mein hoon"*. The notch shows the steps as Slack opens, finds the person, opens the DM and writes the message, then counts down 3 s before sending. Unknown commands say "Can't do that yet" and copy the transcript; nothing is ever typed. |
| **Stop** | `Esc`: cancels a recording, a command being understood, or an action at any step before the send. |

The menu bar icon has **Language** (Hinglish / English), **AI Cleanup** (Off / Fast / Thorough / Cloud),
**Recent** and **History…**, and **Settings…** (hotkeys, send countdown, providers and keys, dictionary,
privacy). Add names and product terms in **Settings → Dictionary** so they come out spelled your way.

Slack commands need the **Slack desktop app**. If a step can't be verified (the person isn't found, two
people match, a draft is already in that DM, Slack lost focus), it stops, says why, and puts your message
on the clipboard.

## Privacy

- Transcripts are kept in a local history (SQLite) until you clear it; audio only if you turn it on.
- No analytics. Besides model downloads, the app only contacts the cloud providers you choose
  (Deepgram, OpenAI, Groq); their keys are stored in the macOS Keychain.

## Models

| Role | Model | License |
|---|---|---|
| Hinglish speech-to-text | [Oriserve/Whisper-Hindi2Hinglish-Apex](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex), converted to Core ML by this project ([published here](https://huggingface.co/kumargaurav9013/whisper-hindi2hinglish-apex-coreml)) | Apache-2.0 |
| English speech-to-text | Whisper large-v3-turbo ([Argmax WhisperKit](https://huggingface.co/argmaxinc/whisperkit-coreml)) | MIT |
| AI cleanup and commands | Qwen3-1.7B and Qwen3-4B-Instruct, 4-bit MLX ([mlx-community](https://huggingface.co/mlx-community)) | Apache-2.0 |

## Development

```sh
swift test                                   # unit tests
cd scripts/eval && uv run pytest && uv run mypy ovf_eval tests
```

The eval tooling (`scripts/eval`, `EvalRunner`) scores speech-to-text, cleanup and command parsing on a
personal eval set; see `scripts/eval/README.md` and the reports in `docs/eval/reports/`. The design is in
`docs/SPEC.md`, decisions in `docs/adr/`, and what's next in `docs/ROADMAP.md`.

## License

GPLv3: see [LICENSE](LICENSE). Bundled and downloaded models keep their own licenses (above); why GPLv3 and what stays free: ADR 0002.
