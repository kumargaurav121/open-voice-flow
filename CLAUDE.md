# Open Voice Flow

A macOS menu-bar dictation app (Swift, SwiftPM): hold `fn`, speak English / Hindi / Hinglish, the text lands
in the focused app. Local models by default; Slack actions on Right `⌥`. Users read `README.md`; this file is
for you.

When the user asks to **install, run, update or uninstall** the app, follow **Installing for a user**. When
they ask to **change the code**, follow **Working on the code**.

## Installing for a user

Most people who open this repo with you are not developers. Be their installer: do every step a command can
do, and for the rest give short numbered GUI steps, then wait for them to say it's done.

1. **Run `scripts/install.sh`.** It checks the Mac, Xcode, the Metal Toolchain and a signing certificate,
   then builds, installs to `~/Applications/Open Voice Flow.app` and launches. It stops at the first ✗ and
   prints the fix. The first build takes several minutes; run it with a long timeout.
   - A ✗ fix that is a plain command: run it, then rerun the script.
   - A fix that needs `sudo`: show the command and ask the user to run it as `! <command>` (it prompts for
     their password, which you never handle).
   - A fix that needs the GUI (installing Xcode from the App Store, adding their Apple ID in Xcode): relay
     the script's numbered steps and wait. The Apple ID is the **user's own**, free; it signs the app on
     their Mac only, so macOS keeps the app's permissions across rebuilds.
   - Done when the script ends with "Launched".
2. **Walk them through the setup window** (opens on first launch; menu-bar wave icon → *Finish Setup…* / *Setup Guide…*
   reopens it). Tell them what to expect before each part:
   - Permissions: Microphone, Accessibility, Input Monitoring. Each *Allow…* button opens the right System
     Settings pane; the row ticks itself within a second of being switched on.
   - Model download: ~6.5 GB from Hugging Face, resumable, every file checksum-verified.
   - *Preparing*: macOS compiles the speech model for their Neural Engine once, up to ~15 minutes. The
     progress bar is an estimate; slow is normal.
   - Try it: click the box, hold `fn`, speak, release.
3. **Set the fn key**: System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing** (otherwise fn opens
   the emoji picker or starts Apple's dictation).
4. **Confirm it works**: they open TextEdit, hold `fn`, say a sentence, and the text appears. That is the
   install's completion criterion.

### When something goes wrong
Read the app log first: `~/Library/Logs/OpenVoiceFlow/OpenVoiceFlow.log` (one line per load, dictation and
error).

| Symptom | Fix |
|---|---|
| Holding fn does nothing | Input Monitoring is off or was reset: re-allow it via *Setup Guide…* in the menu, then quit and reopen the app. |
| Text doesn't appear, or "Couldn't paste" | Accessibility is off: re-allow it. After a rebuild macOS can ask again. |
| Build fails with `unable to spawn process …/metal` | `scripts/build-app.sh` clears this automatically; if it persists, `rm -rf .build/out/Intermediates.noindex/XCBuildData` and rebuild. |
| Download stopped | Click *Try Again*: it resumes where it stopped. After a checksum failure that model's download is deleted and fetched fresh. |
| Menu-bar icon shows a warning triangle | Open the menu: it names the missing permission or the model that failed. |

### Update
`git pull`, then `scripts/install.sh`. Models, settings, history and permissions are kept.

### Uninstall
Quit the app, then remove what the user wants gone:
- App: `rm -rf ~/Applications/"Open Voice Flow.app"`
- Models and history (~7 GB): `rm -rf ~/Library/Application\ Support/open-voice-flow`
- Logs: `rm -rf ~/Library/Logs/OpenVoiceFlow`
- Settings: `defaults delete dev.openvoiceflow.OpenVoiceFlow`
- Cloud API keys, if they added any: repeat `security delete-generic-password -s dev.openvoiceflow.api-keys`
  until it reports nothing found
- Permissions: `tccutil reset All dev.openvoiceflow.OpenVoiceFlow`

## Working on the code

- Modules are SwiftPM targets; `Package.swift` has a one-line comment on each. `Core` holds the session
  pipeline and provider protocols with no platform frameworks; everything else plugs into it.
- `swift test` runs the unit tests. Rebuild and reinstall the app with `scripts/install.sh`.
- Design: `docs/SPEC.md`. Decisions: `docs/adr/` (read the ADRs for the area you touch). Eval tooling:
  `scripts/eval/README.md`.

Rules this project holds to:
- **Output is always English letters and Western digits.** Hindi is transliterated to Hinglish, never
  translated (`LatinScriptSpeechToText` guarantees it whatever the model emits).
- **Model supply chain (ADR 0010):** models are pinned to full 40-character commit SHAs and contain data
  files only (safetensors, json, txt, Core ML). Every file is SHA-256-verified against the manifest built
  into the app. To add or bump a model, edit `scripts/make-manifests.py` and regenerate
  `Sources/ModelStore/BuiltInModels.swift`, then rerun the eval.
- **Test-first at agreed seams:** agree with the user which public interfaces get tests, write a failing
  test, then the code. Tests exercise behaviour through those interfaces.
- **Actions run visibly** in the real app, with a countdown and `Esc` to stop (ADR 0006).
- Match the surrounding code: its naming, comment density and idiom.
