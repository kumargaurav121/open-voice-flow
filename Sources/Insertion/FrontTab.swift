import AppKit

/// The front browser tab's address, asked of the browser through AppleScript. macOS asks the user once per browser
/// ("Open Voice Flow wants to control Google Chrome"), never mid-dictation: only a second after the text is in
/// (`askIfPending`), so the prompt can't freeze the dictation or take its paste.
@MainActor
public final class FrontTab {
    /// How each browser names its front tab's address: the Chromium ones (Chrome, Brave, Edge, Arc, Dia) the active
    /// tab, Safari the current tab.
    private static let queries: [String: String] = {
        let activeTab = "URL of active tab of front window"
        return ["com.google.Chrome": activeTab, "com.brave.Browser": activeTab, "com.microsoft.edgemac": activeTab,
                "company.thebrowser.Browser" /* Arc */: activeTab, "company.thebrowser.dia": activeTab,
                "com.apple.Safari": "URL of current tab of front window"]
    }()
    /// How long after the paste is sent the prompt may come: past the paste and the clipboard's restore.
    private static let askDelay: TimeInterval = 1

    private var scripts: [String: NSAppleScript] = [:]
    /// The browser this dictation couldn't ask yet: the user is asked about it once the text is in.
    private var pendingAsk: String?
    /// Browsers the user answered about, or is being asked about: macOS shows its prompt only once.
    private var asked: Set<String> = []
    private let log: (String) -> Void

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// The front browser tab's address, or nil: no browser it can ask in front, not allowed (yet), or no answer
    /// within a second. Never logged.
    public func address() -> String? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let query = Self.queries[id] else {
            return nil
        }
        let status = Self.permission(for: id, ask: false)
        guard status == noErr else {
            if status == OSStatus(errAEEventWouldRequireUserConsent) { pendingAsk = id }
            log("Browser tab address: not allowed yet (status \(status))")
            return nil
        }
        // A hung browser holds the dictation a second at most.
        let script = scripts[id] ?? NSAppleScript(source: """
            with timeout of 1 second
                tell application id "\(id)" to return \(query)
            end timeout
            """)
        scripts[id] = script
        var error: NSDictionary?
        guard let address = script?.executeAndReturnError(&error).stringValue else {
            log("Browser tab address: no answer (error \(error?[NSAppleScript.errorNumber] ?? "unknown"))")
            return nil
        }
        return address
    }

    /// A dictation is starting: an ask the last one left pending (it pasted nothing) is dropped, so the prompt never
    /// comes over another app.
    public func dictationStarting() {
        pendingAsk = nil
    }

    /// Once a dictation's text is in: asks the user to let this app read the browser's tab address, if this
    /// dictation found that still to be asked.
    public func askIfPending() {
        guard let id = pendingAsk else { return }
        pendingAsk = nil
        guard asked.insert(id).inserted else { return }
        // The answer can take as long as the user does, so a plain background queue waits for it.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.askDelay) { [weak self] in
            let status = Self.permission(for: id, ask: true)
            Task { @MainActor in self?.answered(status, for: id) }
        }
    }

    private func answered(_ status: OSStatus, for id: String) {
        log("Browser tab address: asked the user (status \(status))")
        // Not an answer (the browser quit): it may be asked again.
        if status != noErr, status != OSStatus(errAEEventNotPermitted) { asked.remove(id) }
    }

    /// Whether this app may send the browser Apple events: noErr, or not yet asked, or not allowed; `ask` shows
    /// macOS's prompt when not yet asked, and waits for the answer.
    nonisolated private static func permission(for bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let descriptor = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(descriptor, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }
}
