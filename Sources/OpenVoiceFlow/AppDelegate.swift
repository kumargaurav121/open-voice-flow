import AppKit
import Audio
import Core
import Insertion
import STT

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Status: Equatable {
        case loadingModel
        case modelFailed
        case ready
        case listening
        case transcribing
    }

    private let log = AppLog()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hotkeys = HotkeyMonitor()
    private let transcriber = WhisperKitTranscriber(modelsDirectory: AppDelegate.modelsDirectory)
    private lazy var session = DictationSession(
        recorder: MicRecorder(),
        speechToText: transcriber,
        inserter: PasteInserter(),
        now: { ProcessInfo.processInfo.systemUptime },
        language: { [weak self] in self?.language ?? .auto }
    )

    private var status = Status.loadingModel { didSet { refreshIcon() } }
    private var permissions = SystemPermissions.current() { didSet { refreshIcon() } }
    private var lastMessage: String?
    private var permissionTimer: Timer?

    private var language: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }

    static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "open-voice-flow/models", directoryHint: .isDirectory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()

        session.onEvent = { [weak self] in self?.handle($0) }
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .press: session.keyDown()
            case .release: Task { await self.session.keyUp() }
            case .cancel: Task { await self.session.cancel() }
            }
        }

        SystemPermissions.requestMissing()
        refreshPermissions()
        // Permissions are granted in System Settings while we run; pick them up without a relaunch.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }

        log.notice("Launched")
        loadModel()
    }

    private func loadModel() {
        status = .loadingModel
        Task {
            do {
                let started = ProcessInfo.processInfo.systemUptime
                try await transcriber.prepare()
                log.notice(String(format: "Speech model ready in %.1fs", ProcessInfo.processInfo.systemUptime - started))
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
            lastMessage = String(format: "Last dictation: text in %.1f s", t.transcribe + t.insert)
            log.notice(String(format: "Inserted. capture %.2fs transcribe %.2fs insert %.2fs", t.capture, t.transcribe, t.insert))
        case .ignored(let reason):
            status = .ready
            log.notice("Ignored: \(reason)")
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
        menu.addItem(item("Set Globe Key to Do Nothing…") { SystemPermissions.openKeyboardSettings() })

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Open Voice Flow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private var statusLine: String {
        if let warning = permissions.warning { return warning }
        return switch status {
        case .loadingModel: "Loading speech model. First launch downloads about 1.6 GB."
        case .modelFailed: "Speech model failed to load"
        case .ready: "Ready. Hold fn to dictate."
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

private extension Language {
    var title: String {
        switch self {
        case .auto: "Detect Automatically"
        case .english: "English"
        case .hindi: "Hindi"
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
