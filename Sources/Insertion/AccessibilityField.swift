import AppKit

/// Types into the focused element by setting its selected text, which inserts at the cursor.
@MainActor
final class AccessibilityField: FocusedField {
    /// Cap on each Accessibility call, so a hung frontmost app can't freeze ours (default is ~6 s).
    static let messagingTimeout: Float = 0.25
    /// Chromium/Electron fields can apply the change a moment later; look again before giving up.
    static let recheckDelay: Duration = .milliseconds(80)

    /// Electron apps (Slack) and Chromium browsers build their accessibility tree only once asked, a moment
    /// later: how long to keep looking for their focused field.
    static let wakeWait: Duration = .seconds(1)
    static let wakeInterval: Duration = .milliseconds(100)

    func insertAtCursor(_ text: String) async -> DirectInsertResult {
        guard let element = Self.focusedElement() else { return .refused(diagnostic: "no focused element") }
        let role = string(element, kAXRoleAttribute) ?? "?"
        // Password fields: leave them to the paste path, and never read them.
        if isSecure(element) { return .refused(diagnostic: "secure field") }
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

    // MARK: Undo Formatting

    func reading() async -> FieldReading {
        var element = Self.focusedElement()
        var asked: Bool?
        if element == nil {
            asked = wakeFrontmostApp()
            var waited = Duration.zero
            while asked == true, element == nil, waited < Self.wakeWait {
                try? await Task.sleep(for: Self.wakeInterval)
                waited += Self.wakeInterval
                element = Self.focusedElement()
            }
        }
        guard let element else {
            let diagnostic = asked == true ? "no focused field, even after the app took the request for its fields"
                : "no focused field, and the app refused the request for its fields"
            return FieldReading(diagnostic: diagnostic, state: nil)
        }
        guard !isSecure(element) else { return FieldReading(diagnostic: "secure field", state: nil) }
        return FieldReading(diagnostic: "role \(string(element, kAXRoleAttribute) ?? "?")", state: state(of: element))
    }

    func text(in range: Range<Int>) async -> String? {
        guard let element = Self.focusedElement(), !isSecure(element) else { return nil }
        var cfRange = CFRange(location: range.lowerBound, length: range.count)
        if let parameter = AXValueCreate(.cfRange, &cfRange) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                          parameter, &value) == .success,
               let text = value as? String {
                return text
            }
        }
        // Fields without ranged reads: the whole text.
        guard let whole = string(element, kAXValueAttribute).map({ $0 as NSString }), range.upperBound <= whole.length
        else { return nil }
        return whole.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    func select(_ range: Range<Int>) async -> Range<Int>? {
        guard let element = Self.focusedElement(), !isSecure(element) else { return nil }
        var cfRange = CFRange(location: range.lowerBound, length: range.count)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return nil }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        var shown = selection(of: element)
        if shown != range {
            try? await Task.sleep(for: Self.recheckDelay)
            shown = selection(of: element)
        }
        return shown
    }

    /// Asks the frontmost app to build its accessibility tree (Electron's flag, which Slack's action also
    /// sets); false when it doesn't take it (native apps).
    private func wakeFrontmostApp() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
    }

    // MARK: Reading the field

    /// The focused element, with the messaging timeout set; nil when there's none.
    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement  // type checked above
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    private func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
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
