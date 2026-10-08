import AppKit
import Core

/// Watches the keyboard system-wide for the push-to-talk key. Listen-only: events still
/// reach the focused app. Requires Input Monitoring permission.
@MainActor
final class HotkeyMonitor {
    var onAction: (PushToTalkKey.Action) -> Void = { _ in }

    private var key = PushToTalkKey()
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
        let input: PushToTalkKey.Input
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .flagsChanged:
            let flags = event.flags
            let others: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            input = .flagsChanged(trigger: flags.contains(.maskSecondaryFn), otherModifiers: !flags.intersection(others).isEmpty)
        case .keyDown:
            input = .keyDown
        default:
            return
        }
        if let action = key.handle(input) { onAction(action) }
    }
}
