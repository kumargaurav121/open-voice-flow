import Foundation

/// Keeps macOS from running its own 🌐 key action (the emoji picker, by default) when fn is tapped for
/// dictation, such as the double tap that starts hands-free. macOS runs that action in the window server
/// ahead of every event tap, so the key press can't be swallowed; the only lever is the setting itself
/// (System Settings → Keyboard → "Press 🌐 key to"), the approach OpenWhispr takes. While the app uses fn
/// it's held at Do Nothing, and it's put back afterwards. If the user picks another action while the app
/// runs, their choice wins. The original is saved first, so it survives a crash.
@MainActor
public final class GlobeKeyAction {
    /// The setting's value for "Do Nothing" (1 changes input source, 2 shows emoji, 3 starts dictation).
    public static let doNothing: Int32 = 0

    /// What to put back: the user's value, and whether it was set at all (otherwise macOS was choosing a
    /// default by itself, and should again).
    public struct Saved: Codable, Equatable, Sendable {
        public var original: Int32
        public var keyExisted: Bool

        public init(original: Int32, keyExisted: Bool) {
            self.original = original
            self.keyExisted = keyExisted
        }
    }

    private let current: () -> Int32?
    private let update: (Int32) -> Void
    private let keyExists: () -> Bool
    private let clearKey: () -> Void
    private let load: () -> Saved?
    private let save: (Saved?) -> Void
    /// Set while the app is holding the setting at Do Nothing.
    private var owned: Saved?

    /// - Parameters:
    ///   - current: the setting as macOS applies it; nil when it can't be read (nothing is then changed).
    ///   - update: changes it the way System Settings does, so it applies straight away.
    ///   - keyExists, clearKey: whether the user (rather than macOS's default) set it, and unsetting it.
    ///   - load, save: the saved original, kept where it survives a crash.
    public init(current: @escaping () -> Int32?, update: @escaping (Int32) -> Void,
                keyExists: @escaping () -> Bool, clearKey: @escaping () -> Void,
                load: @escaping () -> Saved?, save: @escaping (Saved?) -> Void) {
        self.current = current
        self.update = update
        self.keyExists = keyExists
        self.clearKey = clearKey
        self.load = load
        self.save = save
    }

    /// At launch, after a run that didn't quit cleanly: keep owning the setting if it's still at Do Nothing,
    /// otherwise the user has chosen since and the saved original is dropped.
    public func recover() {
        guard let saved = load() else { return }
        if current() == Self.doNothing {
            owned = saved
        } else {
            save(nil)
        }
    }

    /// Holds the setting at Do Nothing, saving the original first. Returns the original when it changed it.
    @discardableResult
    public func take() -> Int32? {
        guard owned == nil, let original = current(), original != Self.doNothing else { return nil }
        let saved = Saved(original: original, keyExisted: keyExists())
        save(saved)
        owned = saved
        update(Self.doNothing)
        return original
    }

    /// Puts the original back, unless the user changed the setting meanwhile.
    public func giveBack() {
        guard let saved = owned else { return }
        owned = nil
        if current() == Self.doNothing {
            update(saved.original)
            if !saved.keyExisted { clearKey() }
        }
        save(nil)
    }
}
