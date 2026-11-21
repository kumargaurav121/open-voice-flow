import Carbon.HIToolbox

/// A system-wide keyboard shortcut, through Carbon's hot keys: it reaches this app whichever app is in front,
/// and that app never sees the keystroke (an ⌥ combination would otherwise type a character into the very
/// field being changed). Needs no permission. Kept for the life of the app, and one per app: its handler takes
/// every hot key press.
@MainActor
final class GlobalShortcut {
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// - Parameters:
    ///   - keyCode: a virtual key code (`kVK_ANSI_Z`).
    ///   - modifiers: Carbon modifier masks (`controlKey | optionKey`).
    /// Nil when the shortcut can't be registered (another app holds it).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x4F56_4655), id: 1)  // "OVFU"
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0,
                                  &hotKey) == noErr
        else {
            RemoveEventHandler(handler)
            return nil
        }
    }
}
