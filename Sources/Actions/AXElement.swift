import AppKit
import ApplicationServices

/// A thin, read-mostly wrapper over an Accessibility element, enough to drive an app's UI.
@MainActor
struct AXElement {
    let element: AXUIElement

    static func application(_ app: NSRunningApplication) -> AXElement {
        AXElement(element: AXUIElementCreateApplication(app.processIdentifier))
    }

    func string(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    var role: String? { string(kAXRoleAttribute) }
    var value: String? { string(kAXValueAttribute) }
    var title: String? { string(kAXTitleAttribute) }
    var label: String? { string(kAXDescriptionAttribute) }
    var domIdentifier: String? { string("AXDOMIdentifier") }

    var children: [AXElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.map(AXElement.init)
    }

    /// The element's on-screen frame, in global (top-left origin) coordinates.
    var frame: CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size else { return nil }
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        // Checked by type ID above.
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: point, size: extent)
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    func focus() { set(kAXFocusedAttribute, kCFBooleanTrue) }

    /// Depth-first search, bounded so a huge web view can't stall a step.
    func first(maxDepth: Int = 40, where matches: (AXElement) -> Bool) -> AXElement? {
        all(maxDepth: maxDepth, limit: 1, where: matches).first
    }

    func all(maxDepth: Int = 40, limit: Int = 200, where matches: (AXElement) -> Bool) -> [AXElement] {
        var found: [AXElement] = []
        var visited = 0
        func walk(_ node: AXElement, depth: Int) {
            guard found.count < limit, depth <= maxDepth, visited < 20_000 else { return }
            visited += 1
            if matches(node) { found.append(node) }
            for child in node.children { walk(child, depth: depth + 1) }
        }
        walk(self, depth: 0)
        return found
    }
}

/// Synthetic input, posted like the user's own (visible, and stoppable at any point).
@MainActor
enum SyntheticInput {
    static let returnKey: CGKeyCode = 36
    static let kKey: CGKeyCode = 40

    /// Events carry exactly the modifiers given: a private source, so keys this app just "pressed" (⌘K,
    /// ⌘V) or the user still holds can't leak in. A leaked ⌘ turns a click on a Slack result into
    /// "open in a new window".
    private static var source: CGEventSource? { CGEventSource(stateID: .privateState) }

    static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// A plain left click (no modifiers) at a point in global coordinates.
    static func click(at point: CGPoint) {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Polls until `condition` holds; for UI that updates asynchronously. The step's own timeout bounds it.
@MainActor
func waitUntil(every interval: Duration = .milliseconds(100), _ condition: () -> Bool) async throws {
    while !condition() {
        try Task.checkCancellation()
        try await Task.sleep(for: interval)
    }
}
