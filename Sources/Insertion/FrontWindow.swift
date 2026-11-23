import AppKit

/// The front app's focused window, as Accessibility reports it.
public enum FrontWindow {
    /// Its title (a browser's names the page in it, such as Gmail's), or nil when there is none or the app doesn't
    /// answer in time. Never logged: it can hold a subject or an address.
    @MainActor
    public static func title() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, AccessibilityField.messagingTimeout)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let focused = window as! AXUIElement  // type checked above
        AXUIElementSetMessagingTimeout(focused, AccessibilityField.messagingTimeout)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}
