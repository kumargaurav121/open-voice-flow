import AppKit
import Core

/// The field a dictation was just pasted into, read through Accessibility so the app can learn from the user's
/// fixes (v2 ticket 15). Its text is only compared in memory, never kept or logged.
@MainActor
public final class AccessibilityPastedField: PastedField {
    /// A longer text isn't followed: it would be read in full twice a second.
    static let maxLength = 50_000

    private var followed: AXUIElement?

    public init() {}

    public func follow() async -> FieldText? {
        followed = AccessibilityField.focusedElement()
        guard let followed else { return nil }
        return Self.text(of: followed)
    }

    public func read() async -> FieldText? {
        guard let followed, let focused = AccessibilityField.focusedElement(), CFEqual(focused, followed) else {
            return nil  // focus moved
        }
        return Self.text(of: followed)
    }

    /// Its text and cursor; nil for a password field, a text too long to follow, or one that can't be read.
    private static func text(of element: AXUIElement) -> FieldText? {
        var subrole: CFTypeRef?, count: CFTypeRef?, value: CFTypeRef?, selection: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole as String else { return nil }
        // Its length first where the field gives it, so a long text isn't copied over just to be refused.
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let length = count as? Int, length > maxLength {
            return nil
        }
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, text.utf16.count <= maxLength,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection) == .success,
              let selection, CFGetTypeID(selection) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(selection as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }  // type checked above
        return FieldText(text: text, cursor: range.location + range.length)
    }
}
