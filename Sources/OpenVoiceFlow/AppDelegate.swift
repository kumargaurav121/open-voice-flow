import AppKit
import Audio
import Cloud
import Core
import History
import Insertion
import LLM
import ModelStore
import NotchUI
import Onboarding
import STT

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Status: Equatable {
        /// Models aren't downloaded yet; onboarding installs them.
        case needsSetup
        case loadingModel
        case modelFailed
        case ready
        case listening
        case transcribing
    }

    private let log = AppLog()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hotkeys = HotkeyMonitor()
    // English mode runs turbo (best English); Hinglish mode runs the Hinglish model (bake-off, ticket 03).
    private let englishModel = WhisperKitTranscriber(model: .turbo)
    // Created on first use, after onboarding has installed the models.
    private lazy var hinglishModel: WhisperKitTranscriber = {
        let preferred = SpeechModel.preferredHinglish
        guard preferred != .turbo else { return englishModel }
        let model = WhisperKitTranscriber(model: preferred)
        model.onBreakdown = { [weak self] in self?.log.notice("STT \(preferred): \($0)") }
        return model
    }()
    private let downloader = ModelDownloader(transport: URLSessionTransport())
    private var onboarding: (window: OnboardingWindow, model: OnboardingModel)?
    private let dictionary = DictionaryStore()
    private let modes = ModeStore()
    private let keys = APIKeys()
    private lazy var settingsWindow = SettingsWindow(modes: modes, keys: keys, dictionary: dictionary, history: history,
                                                     cleanupAvailable: { [weak self] in self?.cleanupAvailable($0) ?? false })
    private lazy var cloudCleaner = OpenAICompatibleCleaner(
        llm: { [weak self] in self?.modes.mode.cloudLLM ?? CloudLLM() },
        apiKey: { [weak self] in try self?.keys.key(for: $0.keyAccount) },
        vocabulary: { [weak self] in self?.dictionary.terms ?? [] }
    )
    private lazy var history = HistoryModel(store: try? HistoryStore())
    private lazy var historyWindow = HistoryWindow(model: history)
    private let recorder = MicRecorder()
    private let inserter = Inserter()
    private lazy var notch = NotchController(
        currentDecibels: { [recorder] in recorder.currentDecibels },
        modeTitle: { [weak self] in (self?.language ?? .hinglish).displayName }
    )
    /// Speech to text plus the dictionary and English letters: what dictation and commands share.
    private lazy var transcription: SpeechToText = DictionarySpeechToText(
        // Always English letters and digits, whichever model or script (user requirement).
        wrapping: LatinScriptSpeechToText(wrapping: SelectedSpeechToText(
            local: LanguageRoutedSpeechToText(routes: [.english: englishModel, .hinglish: hinglishModel]),
            // Only called when chosen in Settings; falls back to this Mac if it fails.
            cloud: DeepgramSpeechToText(apiKey: { [weak self] in try self?.keys.key(for: .deepgram) },
                                        keyterms: { [weak self] in self?.dictionary.terms ?? [] }),
            provider: { [weak self] in self?.modes.mode.speech ?? .local },
            log: { [weak self] in self?.log.notice($0) }
        )),
        // Respells names before cleanup, so the AI sees them right too.
        terms: { [weak self] in self?.dictionary.terms ?? [] },
        isEnglishWord: { EnglishWords.contains($0) }
    )
    private lazy var session = PushToTalkSession(
        recorder: recorder,
        speechToText: CleanupSpeechToText(
            wrapping: transcription,
            selectedAI: { [weak self] in self?.activeCleaner },
            isCodeContext: { CodeContext.isCodeEditor(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") },
            timeout: .seconds(4),  // Thorough (4B) took up to 2.4 s on long eval clips
            log: { [weak self] in self?.log.notice($0) }
        ),
        inserter: inserter,
        now: { ProcessInfo.processInfo.systemUptime },
        language: { [weak self] in self?.language ?? .hinglish },
        frontmostApp: { NSWorkspace.shared.frontmostApplication?.localizedName },
        commands: CommandParser(model: { [weak self] in self?.commandModel }, log: { [weak self] in self?.log.notice($0) }),
        // Commands get the rules cleanup but never AI cleanup: it would add seconds, could reword the
        // command itself, and would send it to the cloud when Cloud cleanup is on.
        commandSpeechToText: CleanupSpeechToText(wrapping: transcription, selectedAI: { nil }, isCodeContext: { false },
                                                 timeout: .seconds(4), log: { _ in })
    )
    /// When the command key was released, for the "parsed in under 2 s" target.
    private var commandReleasedAt: TimeInterval?

    /// Commands the rules don't recognise are parsed on this Mac, never in the cloud. The 1.7B model keeps
    /// them under 2 s after release (eval: 1.7-1.8 s; the 4B took 2.7-2.9 s); the 4B if that's all there is.
    private var commandModel: LLMCleaner? { cleaner(for: .fast) ?? cleaner(for: .thorough) }

    private var status = Status.needsSetup { didSet { refreshIcon() } }
    private var permissions = SystemPermissions.current() { didSet { refreshIcon() } }
    private var lastMessage: String?
    private var permissionTimer: Timer?

    /// One cleaner per installed model, created on first use.
    private var cleaners: [CleanupMode: LLMCleaner] = [:]

    private func cleaner(for mode: CleanupMode) -> LLMCleaner? {
        if let existing = cleaners[mode] { return existing }
        guard let folder = LLMCleaner.folder(for: mode), LLMCleaner.isInstalled(at: folder) else { return nil }
        let created = LLMCleaner(folder: folder)
        created.vocabulary = { [weak self] in self?.dictionary.terms ?? [] }
        cleaners[mode] = created
        return created
    }

    /// The cleaner the pipeline uses right now; nil when AI cleanup is off.
    private var activeCleaner: TextCleaner? {
        switch cleanupMode {
        case .off: nil
        case .cloud: cloudCleaner
        case .fast, .thorough: cleaner(for: cleanupMode)
        }
    }

    /// Whether a cleanup choice can run: its local model is installed, or its cloud key is saved.
    private func cleanupAvailable(_ mode: CleanupMode) -> Bool {
        switch mode {
        case .off: true
        case .cloud: keys.hasKey(for: modes.mode.cloudLLM.service.keyAccount)
        case .fast, .thorough: cleaner(for: mode) != nil
        }
    }

    /// The menu's (and Settings') AI Cleanup choice. Only the selected local model stays in memory, plus
    /// the 1.7B once a command has needed it.
    private var cleanupMode: CleanupMode {
        get { modes.mode.cleanup }
        set { modes.mode.cleanup = newValue }
    }

    private func loadCleaner() {
        guard cleanupMode != .cloud, let cleaner = cleaner(for: cleanupMode) else { return }
        let mode = cleanupMode
        Task {
            let started = ProcessInfo.processInfo.systemUptime
            do {
                try await cleaner.prepare()
                log.notice(String(format: "AI cleanup (%@) ready in %.1fs", mode.rawValue, ProcessInfo.processInfo.systemUptime - started))
            } catch {
                log.error("AI cleanup (\(mode.rawValue)) failed to load: \(error)")
            }
        }
    }

    private var language: Language {
        get { modes.mode.language }
        set { modes.mode.language = newValue }
    }

    /// Side effects of a Mode change, from the menu or Settings.
    private func modeChanged(from old: Mode, to new: Mode) {
        if new.language != old.language { loadModel() }  // the other language's model loads on first switch
        if new.cleanup != old.cleanup {
            // The command model stays once used, so the next command isn't a cold ~1 GB load.
            for (mode, cleaner) in cleaners where mode != new.cleanup && cleaner !== commandModel { cleaner.unload() }
            loadCleaner()
        }
        if new.speech != old.speech { log.notice("Speech-to-text: \(new.speech.rawValue)") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LLMCleaner.configureGPU()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        session.onEvent = { [weak self] event in
            self?.notch.handle(event)
            self?.handle(event)
        }
        modes.onChange = { [weak self] in self?.modeChanged(from: $0, to: $1) }
        hotkeys.hotkeys = { [weak self] in self?.modes.mode.hotkeys ?? Hotkeys() }
        hotkeys.onEscape = { [weak self] in
            guard let self else { return }
            Task { await self.session.cancel() }
        }
        hotkeys.onAction = { [weak self] kind, action in
            guard let self else { return }
            switch action {
            case .press:
                if kind == .command { warmCommandModel() }
                session.keyDown(kind == .command ? .command : .dictation)
            case .release:
                if kind == .command { commandReleasedAt = ProcessInfo.processInfo.systemUptime }
                Task { await self.session.keyUp() }
            case .cancel: Task { await self.session.cancel() }
            }
        }

        englishModel.onBreakdown = { [weak self] in self?.log.notice("STT turbo: \($0)") }
        inserter.onMethod = { [weak self] in self?.log.notice($0.description) }
        session.onTranscript = { [weak self] in self?.record($0) }

        refreshPermissions()
        // Permissions are granted in System Settings while we run; pick them up without a relaunch.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }

        log.notice("Launched. Models installed: \(modelsInstalled), onboarding complete: \(onboardingComplete), selected: \(language)")
        // Also reopens when a model is missing, e.g. after an update pins a new model.
        let needsOnboarding = !(onboardingComplete && modelsInstalled)
        // Onboarding's Preparing step does the first (compiling) load itself; otherwise load now.
        if modelsInstalled, !needsOnboarding || modelsPrepared {
            loadModel()
            loadCleaner()
        }
        if needsOnboarding {
            showOnboarding()
        } else {
            SystemPermissions.requestMissing()
        }
    }

    // MARK: Commands

    /// Loads the command model while the user is still speaking, so an unusual phrasing isn't also a
    /// cold start.
    private func warmCommandModel() {
        guard let model = commandModel else { return }
        Task { try? await model.prepare() }
    }

    private func commandSeconds() -> Double {
        commandReleasedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
    }

    // MARK: History

    private func record(_ transcript: SessionTranscript) {
        do {
            try history.record(transcript)
        } catch {
            log.error("Couldn't save to history: \(error.localizedDescription)")
        }
    }

    private func recentMenu() -> NSMenuItem {
        let recent = NSMenu()
        do {
            let entries = try history.recent(10)
            if entries.isEmpty { recent.addItem(disabled("No dictations yet")) }
            for entry in entries {
                recent.addItem(recentItem(for: entry))
            }
        } catch {
            recent.addItem(disabled("History couldn't be read"))
            log.error("Couldn't read history: \(error.localizedDescription)")
        }
        recent.addItem(.separator())
        recent.addItem(item("Show All History…") { [weak self] in self?.historyWindow.show() })
        let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        return recentItem
    }

    /// One line, at most 60 characters; click to copy.
    private func recentItem(for entry: HistoryEntry) -> NSMenuItem {
        let line = entry.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let title = line.count > 60 ? line.prefix(59) + "…" : line
        let shown = entry.kind == .command ? "\(modes.mode.hotkeys.command.symbol) \(title)"
            : entry.inserted ? title : "\(title) (not inserted)"
        let entryItem = item(shown) { Clipboard.copy(entry.text) }
        entryItem.toolTip = "Click to copy"
        return entryItem
    }

    // MARK: Onboarding

    private var onboardingComplete: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingComplete") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingComplete") }
    }

    private var modelsInstalled: Bool { BuiltInModels.all.allSatisfy(downloader.isInstalled) }

    /// The pinned model revisions, recorded once their first (slow, compiling) load has completed.
    private var modelsSignature: String { BuiltInModels.all.map { "\($0.id)@\($0.revision)" }.joined(separator: ",") }

    private var modelsPrepared: Bool { UserDefaults.standard.string(forKey: "preparedModels") == modelsSignature }

    private func showOnboarding() {
        if let onboarding {
            onboarding.window.show()
            return
        }
        let model = OnboardingModel(
            services: OnboardingServices(
                permissions: { SystemPermissions.current() },
                request: { SystemPermissions.request($0) },
                downloadModels: { [downloader] progress in try await downloader.installAll(BuiltInModels.all, progress: progress) },
                prepareModels: { [weak self] in try await self?.prepareForOnboarding() },
                markComplete: { [weak self] in self?.onboardingComplete = true }
            ),
            modelsInstalled: modelsInstalled,
            modelsPrepared: modelsPrepared
        )
        let window = OnboardingWindow(model: model)
        model.onFinished = { [weak self, weak window] in
            window?.close()
            self?.onboarding = nil
            self?.log.notice("Onboarding complete")
        }
        onboarding = (window, model)
        window.show()
    }

    /// Loads both speech models (the slow first compile) and the selected AI cleanup model.
    private func prepareForOnboarding() async throws {
        status = .loadingModel
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try await englishModel.prepare()
            try await hinglishModel.prepare()
        } catch {
            status = .modelFailed
            log.error("Speech models failed to load during onboarding: \(error)")
            throw error
        }
        log.notice(String(format: "Speech models prepared in %.1fs", ProcessInfo.processInfo.systemUptime - started))
        UserDefaults.standard.set(modelsSignature, forKey: "preparedModels")
        status = .ready
        loadCleaner()
    }

    private func loadModel() {
        guard modelsInstalled else {
            status = .needsSetup
            return
        }
        status = .loadingModel
        Task {
            do {
                let started = ProcessInfo.processInfo.systemUptime
                let model = language == .english ? englishModel : hinglishModel
                try await model.prepare()
                log.notice(String(format: "Speech model for %@ ready in %.1fs", language.rawValue, ProcessInfo.processInfo.systemUptime - started))
                status = .ready
            } catch {
                log.error("Speech model failed to load: \(error)")
                status = .modelFailed
            }
        }
    }

    private func refreshPermissions() {
        let current = SystemPermissions.current()
        if current != permissions { permissions = current }
        if current.inputMonitoring, !hotkeys.isRunning {
            hotkeys.start()
        }
    }

    private func handle(_ event: SessionEvent) {
        switch event {
        case .listening:
            status = .listening
        case .transcribing:
            status = .transcribing
        case .inserted(let t):
            status = .ready
            onboarding?.model.dictationSucceeded()
            lastMessage = String(format: "Last dictation: text in %.1f s", t.transcribe + t.insert)
            log.notice(String(format: "Inserted. capture %.2fs transcribe %.2fs insert %.2fs", t.capture, t.transcribe, t.insert))
        case .ignored(let reason):
            status = .ready
            log.notice("Ignored: \(reason)")
        case .commandParsed(let intent):
            status = .ready
            // Nothing is sent yet (ticket 12): the message is ready to paste.
            Clipboard.copy(intent.messageText)
            log.notice(String(format: "Command parsed in %.2fs after release; message copied", commandSeconds()))
        case .commandUnknown(let transcript):
            status = .ready
            Clipboard.copy(transcript)  // never typed (SPEC §4.3)
            log.notice(String(format: "Command not understood (%.2fs after release); transcript copied", commandSeconds()))
        case .failed(let failure):
            status = .ready
            lastMessage = switch failure {
            case .microphone: "Couldn't start the microphone"
            case .transcription: "Couldn't transcribe that"
            case .insertion: "Couldn't paste the text"
            }
            log.error("Failed: \(failure)")
        }
    }

    // MARK: Status item

    private func refreshIcon() {
        let symbol: String
        let label: String
        if !permissions.missing.isEmpty, status != .listening {
            (symbol, label) = ("exclamationmark.triangle", "Open Voice Flow needs permissions")
        } else {
            (symbol, label) = switch status {
            case .needsSetup: ("arrow.down.circle", "Open Voice Flow needs setting up")
            case .loadingModel: ("arrow.down.circle", "Loading speech model")
            case .modelFailed: ("exclamationmark.triangle", "Speech model failed to load")
            case .ready: ("waveform", "Open Voice Flow")
            case .listening: ("mic.fill", "Listening")
            case .transcribing: ("ellipsis", "Transcribing")
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = label
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabled(statusLine))
        if let lastMessage { menu.addItem(disabled(lastMessage)) }

        if !permissions.missing.isEmpty {
            menu.addItem(.separator())
            for permission in permissions.missing {
                menu.addItem(item("Allow \(permission.displayName)…") { SystemPermissions.openSettings(for: permission) })
            }
        }
        if status == .modelFailed {
            menu.addItem(item("Retry Loading Model") { [weak self] in self?.loadModel() })
        }
        menu.addItem(item(onboardingComplete ? "Setup Guide…" : "Finish Setup…") { [weak self] in self?.showOnboarding() })

        menu.addItem(.separator())
        menu.addItem(recentMenu())
        menu.addItem(item("History…") { [weak self] in self?.historyWindow.show() })

        menu.addItem(.separator())
        let languages = NSMenu()
        for option in Language.allCases {
            let entry = item(option.title) { [weak self] in self?.language = option }
            entry.state = option == language ? .on : .off
            languages.addItem(entry)
        }
        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languages
        menu.addItem(languageItem)
        let cleanupModes = NSMenu()
        for mode in CleanupMode.allCases {
            let available = cleanupAvailable(mode)
            let entry = item(mode.menuTitle(cloud: modes.mode.cloudLLM, available: available)) { [weak self] in
                self?.cleanupMode = mode
            }
            entry.state = mode == cleanupMode ? .on : .off
            entry.isEnabled = available
            cleanupModes.addItem(entry)
        }
        let cleanupItem = NSMenuItem(title: "AI Cleanup", action: nil, keyEquivalent: "")
        cleanupItem.submenu = cleanupModes
        menu.addItem(cleanupItem)
        if [modes.mode.hotkeys.dictate, modes.mode.hotkeys.command].contains(.fn) {
            menu.addItem(item("Set Globe Key to Do Nothing…") { SystemPermissions.openKeyboardSettings() })
        }
        let settings = item("Settings…") { [weak self] in self?.settingsWindow.show() }
        settings.keyEquivalent = ","
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Open Voice Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var statusLine: String {
        if let warning = permissions.warning { return warning }
        return switch status {
        case .needsSetup: "Finish setup to start dictating."
        case .loadingModel: "Loading speech model"
        case .modelFailed: "Speech model failed to load"
        case .ready: "Ready. Hold \(modes.mode.hotkeys.dictate.displayName) to dictate."
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, handler: action)
    }
}

extension CleanupMode {
    /// How the menu and Settings name a cleanup choice, and why it's unavailable.
    func menuTitle(cloud: CloudLLM, available: Bool) -> String {
        let name = self == .cloud ? "Cloud (\(cloud.service.displayName))" : displayName
        guard !available else { return name }
        return self == .cloud ? "\(name), add a key in Settings → Providers" : "\(name), not installed"
    }
}

private extension Language {
    var title: String {
        switch self {
        case .hinglish: "Hinglish (English and Hindi)"
        case .english: "English Only"
        }
    }
}

/// Menu item that runs a closure, so menu wiring stays next to the menu it builds.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
