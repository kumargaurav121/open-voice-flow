import AppKit
import Core

/// Watches the keyboard system-wide for the push-to-talk keys (dictate and command, chosen in Settings).
/// Listen-only: events still reach the focused app. Requires Input Monitoring permission.
@MainActor
final class HotkeyMonitor {
    enum Kind { case dictate, command }

    var onAction: (Kind, PushToTalkKey.Action) -> Void = { _, _ in }
    /// Esc, at any time: cancels a command still being understood after its key was released (while a
    /// key is held, any key press cancels through `onAction`).
    var onEscape: () -> Void = {}
    private static let escapeKeyCode: Int64 = 53
    /// The current bindings, read on every event so a change in Settings applies straight away.
    var hotkeys: () -> Hotkeys = { Hotkeys() }

    private var dictateKey = PushToTalkKey()
    private var commandKey = PushToTalkKey()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Does nothing when the tap can't be created (usually missing Input Monitoring); call again later.
    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let hotkeys = hotkeys()
        func input(for trigger: TriggerKey) -> PushToTalkKey.Input? {
            switch type {
            case .flagsChanged:
                let state = trigger.state(flags: event.flags.rawValue)
                return .flagsChanged(trigger: state.down, otherModifiers: state.otherModifiers)
            case .keyDown:
                return .keyDown
            default:
                return nil
            }
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode {
            onEscape()
        }
        if let input = input(for: hotkeys.dictate), let action = dictateKey.handle(input) { onAction(.dictate, action) }
        if let input = input(for: hotkeys.command), let action = commandKey.handle(input) { onAction(.command, action) }
    }
}
