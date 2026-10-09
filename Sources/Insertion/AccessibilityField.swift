import AppKit

/// Types into the focused element by setting its selected text, which inserts at the cursor.
@MainActor
final class AccessibilityField: FocusedField {
    /// Cap on each Accessibility call, so a hung frontmost app can't freeze ours (default is ~6 s).
    static let messagingTimeout: Float = 0.25
    /// Chromium/Electron fields can apply the change a moment later; look again before giving up.
    static let recheckDelay: Duration = .milliseconds(80)

    func insertAtCursor(_ text: String) async -> DirectInsertResult {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return .refused(diagnostic: "no focused element") }
        let element = focused as! AXUIElement  // type checked above
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let role = string(element, kAXRoleAttribute) ?? "?"
        // Password fields: leave them to the paste path, and never read them.
        if string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String) {
            return .refused(diagnostic: "secure field")
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue
        else { return .refused(diagnostic: "role \(role), selected text not settable") }

        let before = state(of: element)
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard status == .success else { return .refused(diagnostic: "role \(role), set failed (\(status.rawValue))") }
        var after = state(of: element)
        if after == before {
            try? await Task.sleep(for: Self.recheckDelay)
            after = state(of: element)
        }
        return .attempted(before: before, after: after, diagnostic: "role \(role), \(describe(before)) → \(describe(after))")
    }

    private func state(of element: AXUIElement) -> FieldState? {
        guard let length = length(of: element), let selection = selection(of: element) else { return nil }
        return FieldState(length: length, selection: selection)
    }

    private func length(of element: AXUIElement) -> Int? {
        var count: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
           let number = count as? Int {
            return number
        }
        return string(element, kAXValueAttribute).map { ($0 as NSString).length }
    }

    private func selection(of element: AXUIElement) -> Range<Int>? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return range.location..<(range.location + range.length)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func describe(_ state: FieldState?) -> String {
        state.map { "length \($0.length) cursor \($0.selection.lowerBound)+\($0.selection.count)" } ?? "unreadable"
    }
}
