import AppKit
import Core

/// Inserts text by putting it on the clipboard and sending ⌘V to the focused app.
/// Needs Accessibility permission to post the keystroke.
@MainActor
public final class PasteInserter: TextInserter {
    private static let vKeyCode: CGKeyCode = 9

    public init() {}

    public func insert(_ text: String) async throws {
        // Without Accessibility the synthetic ⌘V is silently dropped.
        guard AXIsProcessTrusted() else { throw PasteInserterError.accessibilityNotGranted }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw PasteInserterError.clipboardUnavailable }

        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        else { throw PasteInserterError.keystrokeUnavailable }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

public enum PasteInserterError: Error {
    case accessibilityNotGranted
    case clipboardUnavailable
    case keystrokeUnavailable
}
