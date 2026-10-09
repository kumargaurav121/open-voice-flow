import AppKit
import Core

/// The focused text field of the frontmost app.
@MainActor
protocol FocusedField: AnyObject {
    /// Inserts at the cursor (replacing any selection) without touching the clipboard.
    func insertAtCursor(_ text: String) async -> DirectInsertResult
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
        // Without Accessibility neither path works (the synthetic ⌘V is silently dropped).
        guard isTrusted() else { throw InserterError.accessibilityNotGranted }
        let direct = await field.insertAtCursor(text)
        if InsertDecision.verdict(for: direct) == .inserted {
            onMethod(.accessibility)
            return
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
