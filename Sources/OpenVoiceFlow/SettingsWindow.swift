import AppKit
import Cloud
import Core
import SwiftUI

/// Menu bar → Settings… (⌘,): hotkeys, language and AI cleanup; speech and AI providers with the user's
/// own keys; the dictionary; privacy. Everything except the keys is one `Mode` value.
@MainActor
final class SettingsWindow {
    private let modes: ModeStore
    private let keys: APIKeys
    private let dictionary: DictionaryStore
    private let history: HistoryModel
    private let cleanupAvailable: (CleanupMode) -> Bool
    private var window: NSWindow?

    init(modes: ModeStore, keys: APIKeys, dictionary: DictionaryStore, history: HistoryModel,
         cleanupAvailable: @escaping (CleanupMode) -> Bool) {
        self.modes = modes
        self.keys = keys
        self.dictionary = dictionary
        self.history = history
        self.cleanupAvailable = cleanupAvailable
    }

    func show() {
        if window == nil {
            let view = SettingsView(modes: modes, keys: keys, dictionary: dictionary, history: history,
                                    cleanupAvailable: cleanupAvailable)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let modes: ModeStore
    let keys: APIKeys
    let dictionary: DictionaryStore
    @Bindable var history: HistoryModel
    let cleanupAvailable: (CleanupMode) -> Bool

    var body: some View {
        TabView {
            // `keys` is read inside so saving a key in Providers updates the AI Cleanup choices.
            GeneralTab(modes: modes, keys: keys, cleanupAvailable: cleanupAvailable)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersTab(modes: modes, keys: keys)
                .tabItem { Label("Providers", systemImage: "cloud") }
            DictionaryView(store: dictionary)
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            PrivacyTab(history: history, modes: modes)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: General

private struct GeneralTab: View {
    @Bindable var modes: ModeStore
    let keys: APIKeys
    let cleanupAvailableCheck: (CleanupMode) -> Bool

    init(modes: ModeStore, keys: APIKeys, cleanupAvailable: @escaping (CleanupMode) -> Bool) {
        self.modes = modes
        self.keys = keys
        cleanupAvailableCheck = cleanupAvailable
    }

    /// Reads the observed key cache first, so SwiftUI redraws when a key is saved or removed.
    private func cleanupAvailable(_ mode: CleanupMode) -> Bool {
        _ = keys.hasKey(for: modes.mode.cloudLLM.service.keyAccount)
        return cleanupAvailableCheck(mode)
    }
    @State private var conflict = false

    var body: some View {
        Form {
            Section {
                Picker("Dictate", selection: hotkey(\.dictate)) {
                    ForEach(TriggerKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Command", selection: hotkey(\.command)) {
                    ForEach(TriggerKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if conflict {
                    Label("Dictate and Command need different keys.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Hold to Talk")
            } footer: {
                Text("Hold the key while you speak; let go to finish. Esc cancels. Commands (e.g. messaging someone on Slack) arrive in a later version.")
                    .foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Picker("Language", selection: $modes.mode.language) {
                    Text("Hinglish (English and Hindi)").tag(Language.hinglish)
                    Text("English only").tag(Language.english)
                }
                // Only choices that can run are offered (a menu picker can't disable one item).
                Picker("AI Cleanup", selection: $modes.mode.cleanup) {
                    ForEach(CleanupMode.allCases.filter { cleanupAvailable($0) || $0 == modes.mode.cleanup }, id: \.self) { mode in
                        Text(mode.menuTitle(cloud: modes.mode.cloudLLM, available: cleanupAvailable(mode))).tag(mode)
                    }
                }
                let unavailable = CleanupMode.allCases.filter { !cleanupAvailable($0) }
                if !unavailable.isEmpty {
                    Text(unavailable.map { $0.menuTitle(cloud: modes.mode.cloudLLM, available: false) }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Your words always come out in English letters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// A binding that refuses a key already used by the other action.
    private func hotkey(_ path: WritableKeyPath<Hotkeys, TriggerKey>) -> Binding<TriggerKey> {
        Binding {
            modes.mode.hotkeys[keyPath: path]
        } set: { key in
            var hotkeys = modes.mode.hotkeys
            hotkeys[keyPath: path] = key
            conflict = hotkeys.conflict
            if !hotkeys.conflict { modes.mode.hotkeys = hotkeys }
        }
    }
}

// MARK: Providers

private struct ProvidersTab: View {
    @Bindable var modes: ModeStore
    let keys: APIKeys

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $modes.mode.speech) {
                    Text("This Mac (WhisperKit)").tag(SpeechProvider.local)
                    Text("Deepgram Nova-3").tag(SpeechProvider.deepgram)
                }
                if modes.mode.speech == .deepgram {
                    KeyField(account: .deepgram, keys: keys)
                    CloudNotice(text: "Each recording is sent to Deepgram to be transcribed, under your own account. If Deepgram fails or takes over 8 seconds, this Mac transcribes instead.")
                }
            } header: {
                Text("Speech to Text")
            }

            Section {
                Picker("Service", selection: $modes.mode.cloudLLM.service) {
                    ForEach(CloudLLM.Service.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                TextField("Model", text: $modes.mode.cloudLLM.model.orEmpty, prompt: Text(modes.mode.cloudLLM.service.defaultModel))
                KeyField(account: modes.mode.cloudLLM.service.keyAccount, keys: keys)
                    .id(modes.mode.cloudLLM.service)
                CloudNotice(text: "Used only when AI Cleanup is set to Cloud: each transcript's text is sent to \(modes.mode.cloudLLM.service.displayName). If it fails or changes the meaning, the basic rules cleanup is used instead.")
            } header: {
                Text("Cloud AI Cleanup")
            }
        }
        .formStyle(.grouped)
    }
}

private extension Binding where Value == String? {
    /// A text field over an optional: empty means nil (the service's default model).
    var orEmpty: Binding<String> {
        Binding<String> { wrappedValue ?? "" } set: { wrappedValue = $0.isEmpty ? nil : $0 }
    }
}

/// A key goes straight to the Keychain; the field never shows a saved key back.
private struct KeyField: View {
    let account: APIKeys.Account
    let keys: APIKeys
    @State private var entered = ""
    @State private var error: String?

    private var saved: Bool { keys.hasKey(for: account) }

    var body: some View {
        LabeledContent("\(account.displayName) API Key") {
            HStack {
                SecureField("Paste your key", text: $entered, prompt: Text(saved ? "Saved in Keychain" : "Paste your key"))
                    .labelsHidden()
                    .onSubmit(save)
                if !entered.isEmpty {
                    Button("Save", action: save)
                } else if saved {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .help("Saved in the Keychain")
                    Button("Remove") { change { try keys.remove(account) } }
                }
            }
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func save() {
        // The pasted text is kept if saving fails, so it can be retried.
        if change({ try keys.save(entered, for: account) }) { entered = "" }
    }

    @discardableResult
    private func change(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

private struct CloudNotice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "network")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: Privacy

private struct PrivacyTab: View {
    @Bindable var history: HistoryModel
    let modes: ModeStore

    var body: some View {
        Form {
            Section {
                Toggle("Keep audio recordings", isOn: $history.keepAudio)
                Text("Saves each dictation's audio on this Mac next to its text in History, deleted with it. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("History")
            }

            Section("What Leaves This Mac") {
                LabeledContent("Speech to text", value: modes.mode.speech == .local ? "Nothing" : "Recordings, to Deepgram")
                LabeledContent("AI Cleanup", value: modes.mode.cleanup == .cloud
                               ? "Transcript text, to \(modes.mode.cloudLLM.service.displayName)" : "Nothing")
                Text("No analytics or telemetry. Besides model downloads, Open Voice Flow only contacts the cloud providers you pick here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
