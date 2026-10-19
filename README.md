# Open Voice Flow

Hold a key, speak, let go: your words appear wherever you're typing. An open-source, local-first
dictation app for macOS, built for **English, Hindi and Hinglish**. It always writes English letters
(Hindi comes out as Hinglish, never translated), cleans up "um"s and false starts, and can carry out a
spoken command like *"Message Gurjeet saying I'll be late"* in Slack, visibly, with a countdown you can
stop.

Everything runs on your Mac by default. Cloud speech-to-text and AI cleanup are optional, with your own
API keys.

## Requirements

| You need | How to get it |
|---|---|
| A Mac with Apple Silicon (M1 or later) | Intel Macs aren't supported: the models run on the Neural Engine and GPU. |
| macOS 14 Sonoma or later | System Settings → General → Software Update. Tested on macOS 26. |
| Xcode (free) | [App Store](https://apps.apple.com/app/xcode/id497799835). Open it once to finish installing. Tested on Xcode 27. Command Line Tools alone aren't enough. |
| Xcode's Metal Toolchain | Installed automatically by `scripts/install.sh` (or `xcodebuild -downloadComponent MetalToolchain`). |
| Your own Apple ID in Xcode (free) | Xcode → Settings → Accounts → + → Apple ID, then *Manage Certificates… → + → Apple Development*. It signs the app on your Mac so macOS remembers its permissions. No paid developer account needed. |
| About 20 GB free disk | ~7 GB of models plus the build. |
| Internet for the first run | The models download once from Hugging Face (~6.5 GB, pinned and checksum-verified). |

## Install with Claude Code (easiest)

```sh
git clone https://github.com/kumargaurav121/open-voice-flow.git
cd open-voice-flow
claude
```

Then ask: **"Install this app."** Claude checks your Mac, installs what it can, walks you through the few
clicks only you can do (installing Xcode, adding your Apple ID, allowing permissions), builds the app and
launches it. The steps it follows are in [CLAUDE.md](CLAUDE.md).

## Install by hand

```sh
scripts/install.sh
```

It checks every requirement above (and tells you exactly how to fix anything missing), builds and signs
the app, installs it to `~/Applications/Open Voice Flow.app` and launches it. Run it again to update after
`git pull`; your models, settings and history are kept.

The first launch opens **setup**: it asks for Microphone, Accessibility and Input Monitoring, downloads
the models (see ADR 0010), and lets you try a dictation. The first load of the speech model compiles it
for your Mac's Neural Engine (up to ~15 minutes, once). Then set System Settings → Keyboard → "Press 🌐
key to" → **Do Nothing**, so holding `fn` doesn't open the emoji picker.

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
