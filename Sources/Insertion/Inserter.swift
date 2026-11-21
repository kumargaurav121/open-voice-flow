import AppKit
import Core

/// The focused text field of the frontmost app.
@MainActor
protocol FocusedField: AnyObject {
    /// Inserts at the cursor (replacing any selection) without touching the clipboard.
    func insertAtCursor(_ text: String) async -> DirectInsertResult
    /// Its role and state; no state when there's no focused field, it's a password field, or it can't be read.
    func reading() async -> FieldReading
    /// The text in `range` (UTF-16), or nil when it can't be read.
    func text(in range: Range<Int>) async -> String?
    /// Selects `range`; returns the selection the field then shows (nil when unreadable).
    func select(_ range: Range<Int>) async -> Range<Int>?
}

/// Sends ⌘V to the frontmost app.
@MainActor
protocol PasteKey: AnyObject {
    func press() throws
}

/// Runs `work` after `delay` (the clipboard restore).
typealias Schedule = (Duration, @escaping @MainActor () -> Void) -> Void

/// How a dictation went in, for the session log.
public enum InsertMethod: CustomStringConvertible {
    case accessibility
    /// Pasted; carries what the direct attempt saw (role, field state; never the text).
    case paste(directAttempt: String)

    public var description: String {
        switch self {
        case .accessibility: "Inserted via Accessibility"
        case .paste(let attempt): "Inserted via paste (direct insert: \(attempt))"
        }
    }
}

/// Puts dictated text into the focused app the cleanest way available: typed straight into the field via
/// Accessibility when that verifiably works (native text fields), otherwise pasted, with the user's
/// clipboard restored afterwards unless they copied something new in the meantime.
@MainActor
public final class Inserter: TextInserter {
    /// Long enough for slow apps (Electron, browsers) to read the clipboard after ⌘V, short enough that the
    /// user's own next ⌘V gets their clipboard back.
    static let restoreDelay: Duration = .milliseconds(500)

    public var onMethod: (InsertMethod) -> Void = { _ in }
    /// Why a replacement was refused, for the session log (the field's role and positions, never its text).
    public var onReplaceRefused: (String) -> Void = { _ in }

    private let field: FocusedField
    private let pasteboard: Pasteboard
    private let pasteKey: PasteKey
    private let isTrusted: () -> Bool
    private let schedule: Schedule
    /// The user's clipboard while a restore is pending. A second dictation inside the restore delay reuses
    /// it, so it never mistakes the first dictation's text for the user's clipboard.
    private var pending: (snapshot: ClipboardSnapshot, token: Int)?
    private var nextToken = 0

    init(field: FocusedField, pasteboard: Pasteboard, pasteKey: PasteKey, isTrusted: @escaping () -> Bool, schedule: @escaping Schedule) {
        self.field = field
        self.pasteboard = pasteboard
        self.pasteKey = pasteKey
        self.isTrusted = isTrusted
        self.schedule = schedule
    }

    /// The real thing: Accessibility, the system clipboard and a synthetic ⌘V.
    public convenience init() {
        self.init(field: AccessibilityField(), pasteboard: NSPasteboard.general, pasteKey: CommandV(),
                  isTrusted: { AXIsProcessTrusted() },
                  schedule: { delay, work in
                      Task { @MainActor in
                          try? await Task.sleep(for: delay)
                          work()
                      }
                  })
    }

    public func insert(_ text: String) async throws {
        try await insert(text, tryingDirectInsert: true)
    }

    /// Selects `old` if it's exactly the text just before the cursor, then inserts `new` over it the usual way
    /// (typed in, or pasted with the clipboard restored).
    public func replace(_ old: String, with new: String) async throws -> Bool {
        guard isTrusted() else { throw InserterError.accessibilityNotGranted }
        let reading = await field.reading()
        func refused(_ reason: String) -> Bool {
            onReplaceRefused("\(reading.diagnostic), \(reason)")
            return false
        }
        guard let cursor = reading.state?.selection else { return refused("field unreadable") }
        guard cursor.isEmpty else { return refused("text selected") }
        let range = (cursor.lowerBound - old.utf16.count)..<cursor.lowerBound
        let found = range.lowerBound >= 0 ? await field.text(in: range) : nil
        guard found == old else {
            let context = "field length \(reading.state?.length ?? 0), cursor \(cursor.lowerBound)"
            guard let found else { return refused("the text before the cursor is too short or unreadable (\(context))") }
            return refused("the text before the cursor differs \(Self.difference(found, from: old)) (\(context))")
        }
        // Unselected, the new text would go in next to the old.
        guard await field.select(range) == range else {
            _ = await field.select(cursor)  // a stray selection would be typed over
            return refused("the selection didn't take")
        }
        try await insert(new, tryingDirectInsert: true)
        return true
    }

    /// Where `found` first differs from `expected`, without their words: letters and digits are named only as
    /// such, other characters by code ("U+00A0" for a non-breaking space).
    static func difference(_ found: String, from expected: String) -> String {
        let (seen, wanted) = (Array(found.unicodeScalars), Array(expected.unicodeScalars))
        let position = zip(seen, wanted).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(seen.count, wanted.count)
        func named(_ index: Int, in scalars: [Unicode.Scalar]) -> String {
            guard index < scalars.count else { return "the end" }
            let scalar = scalars[index]
            if scalar.properties.isAlphabetic { return "a letter" }
            if scalar.properties.numericType != nil { return "a digit" }
            return String(format: "U+%04X", scalar.value)
        }
        return "at \(position) of \(wanted.count), \(named(position, in: seen)) for \(named(position, in: wanted))"
    }

    /// Pastes only, skipping the direct insert: for apps (Slack's Electron fields) where a direct insert can
    /// land late and then the paste fallback would add the text a second time.
    public func paste(_ text: String) async throws {
        try await insert(text, tryingDirectInsert: false)
    }

    private func insert(_ text: String, tryingDirectInsert: Bool) async throws {
        // Without Accessibility neither path works (the synthetic ⌘V is silently dropped).
        guard isTrusted() else { throw InserterError.accessibilityNotGranted }
        var direct = DirectInsertResult.refused(diagnostic: "skipped")
        if tryingDirectInsert {
            direct = await field.insertAtCursor(text)
            if InsertDecision.verdict(for: direct) == .inserted {
                onMethod(.accessibility)
                return
            }
        }

        let saved = pending?.snapshot ?? ClipboardSnapshot.take(from: pasteboard)
        guard pasteboard.writeString(text) else {
            _ = saved.restore(to: pasteboard, ifUnchangedSince: pasteboard.changeCount)
            pending = nil
            throw InserterError.clipboardUnavailable
        }
        let ourWrite = pasteboard.changeCount
        do {
            try pasteKey.press()
        } catch {
            _ = saved.restore(to: pasteboard, ifUnchangedSince: ourWrite)
            pending = nil
            throw error
        }
        onMethod(.paste(directAttempt: direct.diagnostic))

        nextToken += 1
        let token = nextToken
        pending = (saved, token)
        let pasteboard = pasteboard
        // Strong capture: the closure lives in the scheduler, not in self, so this keeps the inserter alive
        // until the restore runs rather than silently skipping it.
        schedule(Self.restoreDelay) {
            guard self.pending?.token == token else { return }  // a later dictation took over
            self.pending = nil
            _ = saved.restore(to: pasteboard, ifUnchangedSince: ourWrite)
        }
    }
}

public enum InserterError: Error, Equatable {
    case accessibilityNotGranted
    case clipboardUnavailable
    case keystrokeUnavailable
}

@MainActor
final class CommandV: PasteKey {
    private static let vKeyCode: CGKeyCode = 9

    func press() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { throw InserterError.keystrokeUnavailable }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
