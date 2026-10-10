import AppKit
import ApplicationServices
import Core
import Insertion

/// Sends a Slack DM by driving the Slack desktop app, visibly (SPEC §4.4, ADR 0006). Built against what
/// Slack's Accessibility tree exposes (ticket 12 research): ⌘K opens a search dialog whose suggestions
/// are rows like "Gurjeet Singh, Direct Message" mixed with "Search for: …" and recent messages, so the
/// matched person's row is clicked (never "Return on the top row").
///
/// Safety, because this sends real messages to real people:
/// - before every key press, click or paste: Slack must still be in front, and Esc or a timeout must not
///   have stopped the step (`ActionContext.checkStopped`);
/// - the DM must visibly open: its window title changes to that person;
/// - a draft already in that DM is never touched or sent; after pasting, the composer must hold exactly
///   the message, and again right before sending;
/// - Return is the point of no return (`ActionContext.commit`), checked one last time.
@MainActor
public final class SlackAdapter {
    public static let bundleID = "com.tinyspeck.slackmacgap"

    private let inserter: Inserter

    public init(inserter: Inserter = Inserter()) {
        self.inserter = inserter
    }

    /// The steps for one message; the runner counts down before the send.
    public func steps(to spokenName: String, text: String) -> [ActionStep] {
        let session = SlackSession()
        return [
            ActionStep(title: "Open Slack", timeout: .seconds(8)) { context in
                try await session.open(context)
            },
            ActionStep(title: "Find \(spokenName)", timeout: .seconds(8)) { context in
                try await session.find(spokenName, context, inserter: self.inserter)
            },
            ActionStep(title: "Open the DM", timeout: .seconds(6)) { context in
                try await session.openDM(context)
            },
            ActionStep(title: "Write the message", timeout: .seconds(6)) { context in
                try await session.write(text, context, inserter: self.inserter)
            },
            ActionStep(title: "Send", timeout: .seconds(6), irreversible: true) { context in
                try await session.send(text, context)
            },
        ]
    }
}

/// One message's walk through Slack; holds what the steps found for the steps after.
@MainActor
private final class SlackSession {
    private static let directMessageSuffix = ", Direct Message"
    private static let suggestionPrefix = "c-search_autocomplete__suggestion_"

    private var app: AXElement?
    private var row: AXElement?
    private var titleBeforeOpening = ""
    private var composer: AXElement?

    // MARK: Steps

    func open(_ context: ActionContext) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SlackAdapter.bundleID) else {
            throw StepFailure(reason: "Slack isn't installed (the desktop app)")
        }
        try context.checkStopped()
        // Opening (not just activating) also brings back a window if Slack is running with none,
        // like clicking its Dock icon.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let launched = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        let element = AXElement.application(launched)
        // Electron apps only build their Accessibility tree when asked.
        element.set("AXManualAccessibility", kCFBooleanTrue)
        app = element
        try await waitUntil { launched.isActive && !windowTitle.isEmpty }
    }

    func find(_ spokenName: String, _ context: ActionContext, inserter: Inserter) async throws {
        try ensureInFront(context)
        SyntheticInput.press(SyntheticInput.kKey, flags: .maskCommand)
        var dialog: AXElement?
        try await waitUntil {
            dialog = window?.first { $0.role == kAXGroupRole && $0.label == "Search" }
            return dialog?.first { $0.role == kAXComboBoxRole && $0.label == "Query" } != nil
        }
        try ensureInFront(context)
        try await inserter.paste(spokenName)
        // Results have caught up once Slack offers to search for this text.
        let query = Self.letters(spokenName)
        var rows: [AXElement] = []
        try await waitUntil {
            rows = dialog?.all { ($0.domIdentifier ?? "").hasPrefix(Self.suggestionPrefix) } ?? []
            return rows.contains { ($0.value ?? "").hasPrefix("Search for:") && Self.letters($0.value ?? "").hasSuffix(query) }
        }
        let people = rows.compactMap { row -> Candidate? in
            guard let value = row.value, value.hasSuffix(Self.directMessageSuffix) else { return nil }
            return Candidate(name: String(value.dropLast(Self.directMessageSuffix.count)), row: row)
        }
        switch RecipientMatch.resolve(spokenName, among: people.map(\.name)) {
        case .found(let name):
            context.recipient = name
            row = people.first { $0.name == name }?.row
        case .notFound:
            throw StepFailure(reason: "Couldn't find \(spokenName)")
        case .ambiguous(let names):
            throw StepFailure(reason: "More than one \(spokenName): \(names.joined(separator: ", "))")
        }
    }

    func openDM(_ context: ActionContext) async throws {
        guard let row, let frame = row.frame, let name = context.recipient else {
            throw StepFailure(reason: "Lost the search result")
        }
        titleBeforeOpening = windowTitle
        try ensureInFront(context)
        SyntheticInput.click(at: CGPoint(x: frame.midX, y: frame.midY))
        // The DM must visibly open: the title changes to it. (If it was already open, it must name the
        // person in full: a title with just "Gurjeet" could be another Gurjeet's DM.)
        try await waitUntil {
            guard let shown = dmName(in: windowTitle) else { return false }
            let opened = windowTitle != titleBeforeOpening || shown == name
            return opened && Self.sameRecipient(shown, name)
        }
    }

    func write(_ text: String, _ context: ActionContext, inserter: Inserter) async throws {
        var box: AXElement?
        try await waitUntil {
            box = window?.first { $0.role == kAXGroupRole && $0.label == "composer" }?
                .first { $0.role == kAXTextAreaRole }
            return box != nil
        }
        guard let box else { throw StepFailure(reason: "Couldn't find the message box") }
        // Someone's unsent draft is theirs: never add to it, never send it.
        guard Self.trimmed(box.value).isEmpty else {
            throw StepFailure(reason: "There's already a draft in that DM; left it alone")
        }
        try ensureInFront(context)
        box.focus()
        try await Task.sleep(for: .milliseconds(150))
        try ensureInFront(context)
        try await inserter.paste(text)
        try await waitUntil { Self.trimmed(box.value) == Self.trimmed(text) }
        composer = box
    }

    func send(_ text: String, _ context: ActionContext) async throws {
        // Re-check after the countdown: still in front, still that DM, still exactly our message.
        try ensureInFront(context)
        guard let name = context.recipient, let shown = dmName(in: windowTitle), Self.sameRecipient(shown, name) else {
            throw StepFailure(reason: "Slack moved away from the DM; not sent")
        }
        guard let composer, Self.trimmed(composer.value) == Self.trimmed(text) else {
            throw StepFailure(reason: "The message was changed; not sent")
        }
        composer.focus()
        try context.commit()  // the point of no return
        SyntheticInput.press(SyntheticInput.returnKey)
        try await waitUntil { Self.trimmed(composer.value).isEmpty }
    }

    // MARK: Checks

    private struct Candidate {
        let name: String
        let row: AXElement
    }

    /// Slack's focused window: the one being driven, even when several are open.
    private var window: AXElement? {
        var value: CFTypeRef?
        guard let app, AXUIElementCopyAttributeValue(app.element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return AXElement(element: value as! AXUIElement)  // checked by type ID above
    }

    private var windowTitle: String { window?.title ?? "" }

    /// Keys only ever go to Slack: if the user switched away, or Esc / a timeout stopped the step, stop.
    private func ensureInFront(_ context: ActionContext) throws {
        try context.checkStopped()
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == SlackAdapter.bundleID else {
            throw StepFailure(reason: "Slack isn't in front anymore; stopped")
        }
    }

    /// "<Display Name> (DM) - <Workspace> - Slack" → "<Display Name>".
    private func dmName(in title: String) -> String? {
        title.range(of: " (DM)").map { String(title[..<$0.lowerBound]) }
    }

    /// The window shows a display name, which can be shorter than the full name in search ("Harpreet"
    /// for "Harpreet Kaur"): every word it shows must match the person's name.
    private static func sameRecipient(_ shown: String, _ name: String) -> Bool {
        RecipientMatch.resolve(shown, among: [name]) == .found(name)
    }

    private static func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
