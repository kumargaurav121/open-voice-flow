import Foundation

/// Turns raw keyboard events into push-to-talk actions for a modifier key such as `fn`.
public struct PushToTalkKey: Sendable {
    public enum Input: Equatable, Sendable {
        /// Modifier state changed. `trigger` is whether the push-to-talk modifier is down;
        /// `otherModifiers` is true when any other modifier is held.
        case flagsChanged(trigger: Bool, otherModifiers: Bool)
        /// A regular (non-modifier) key went down.
        case keyDown
    }

    public enum Action: Equatable, Sendable {
        case press, release, cancel
    }

    private enum State {
        case up
        /// Trigger held on its own: this is a dictation press.
        case held
        /// Trigger is (or was) part of a shortcut; ignore everything until it's released.
        case chord
    }

    private var state = State.up

    public init() {}

    public mutating func handle(_ input: Input) -> Action? {
        switch (state, input) {
        case (.up, .flagsChanged(trigger: true, let others)):
            state = others ? .chord : .held
            return others ? nil : .press
        case (.held, .keyDown), (.held, .flagsChanged(trigger: true, otherModifiers: true)):
            state = .chord
            return .cancel
        case (.held, .flagsChanged(trigger: false, _)):
            state = .up
            return .release
        case (.chord, .flagsChanged(trigger: false, _)):
            state = .up
            return nil
        default:
            return nil
        }
    }
}
