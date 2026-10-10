import Testing
@testable import Core

/// Modifier flags as macOS reports them (CGEventFlags raw values, including the left/right device bits).
private enum Flags {
    static let fn: UInt64 = 0x80_0000
    static let shift: UInt64 = 0x2_0000, control: UInt64 = 0x4_0000, option: UInt64 = 0x8_0000, command: UInt64 = 0x10_0000
    static let leftShift: UInt64 = 0x02, rightShift: UInt64 = 0x04
    static let leftCommand: UInt64 = 0x08, rightCommand: UInt64 = 0x10
    static let leftOption: UInt64 = 0x20, rightOption: UInt64 = 0x40
    static let leftControl: UInt64 = 0x01, rightControl: UInt64 = 0x2000
}

struct TriggerKeyTests {
    @Test(arguments: [
        (TriggerKey.fn, Flags.fn),
        (.rightOption, Flags.option | Flags.rightOption),
        (.rightCommand, Flags.command | Flags.rightCommand),
        (.rightControl, Flags.control | Flags.rightControl),
        (.rightShift, Flags.shift | Flags.rightShift),
    ])
    func eachKeyIsSeenWhenHeldOnItsOwn(key: TriggerKey, flags: UInt64) {
        #expect(key.state(flags: flags) == TriggerKey.State(down: true, otherModifiers: false))
    }

    @Test func theLeftSideKeyDoesNotTriggerTheRightSideBinding() {
        #expect(TriggerKey.rightOption.state(flags: Flags.option | Flags.leftOption).down == false)
        #expect(TriggerKey.rightCommand.state(flags: Flags.command | Flags.leftCommand).down == false)
    }

    @Test func anyOtherModifierMakesItAShortcutNotPushToTalk() {
        // Right ⌥ with Left ⌥, or with ⌘: someone typing a shortcut.
        #expect(TriggerKey.rightOption.state(flags: Flags.option | Flags.rightOption | Flags.leftOption).otherModifiers)
        #expect(TriggerKey.rightOption.state(flags: Flags.option | Flags.rightOption | Flags.command | Flags.leftCommand).otherModifiers)
        #expect(TriggerKey.fn.state(flags: Flags.fn | Flags.shift | Flags.leftShift).otherModifiers)
        #expect(!TriggerKey.fn.state(flags: Flags.fn).otherModifiers)
        // fn counts as another modifier for the right-side keys too.
        #expect(TriggerKey.rightOption.state(flags: Flags.option | Flags.rightOption | Flags.fn).otherModifiers)
    }

    @Test func dictateAndCommandMustBeDifferentKeys() {
        #expect(Hotkeys(dictate: .fn, command: .fn).conflict)
        #expect(!Hotkeys(dictate: .fn, command: .rightOption).conflict)
    }
}
