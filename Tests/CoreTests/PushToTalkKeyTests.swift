import Testing
@testable import Core

struct PushToTalkKeyTests {
    @Test func pressingAndReleasingFnAloneIsAPressThenARelease() {
        var key = PushToTalkKey()

        #expect(key.handle(.flagsChanged(trigger: true, otherModifiers: false)) == .press)
        #expect(key.handle(.flagsChanged(trigger: false, otherModifiers: false)) == .release)
    }

    @Test func anotherKeyWhileFnIsHeldCancelsAndTheReleaseIsSwallowed() {
        var key = PushToTalkKey()

        _ = key.handle(.flagsChanged(trigger: true, otherModifiers: false))
        #expect(key.handle(.keyDown) == .cancel)
        #expect(key.handle(.keyDown) == nil)
        #expect(key.handle(.flagsChanged(trigger: false, otherModifiers: false)) == nil)
    }

    @Test func addingAnotherModifierWhileFnIsHeldCancels() {
        var key = PushToTalkKey()

        _ = key.handle(.flagsChanged(trigger: true, otherModifiers: false))
        #expect(key.handle(.flagsChanged(trigger: true, otherModifiers: true)) == .cancel)
        #expect(key.handle(.flagsChanged(trigger: false, otherModifiers: false)) == nil)
    }

    @Test func fnPressedWhileAnotherModifierIsHeldDoesNothing() {
        var key = PushToTalkKey()

        #expect(key.handle(.flagsChanged(trigger: true, otherModifiers: true)) == nil)
        #expect(key.handle(.flagsChanged(trigger: false, otherModifiers: false)) == nil)
    }

    @Test func worksAgainAfterACancelledChord() {
        var key = PushToTalkKey()

        _ = key.handle(.flagsChanged(trigger: true, otherModifiers: false))
        _ = key.handle(.keyDown)
        _ = key.handle(.flagsChanged(trigger: false, otherModifiers: false))

        #expect(key.handle(.flagsChanged(trigger: true, otherModifiers: false)) == .press)
    }

    @Test func typingWithoutFnDoesNothing() {
        var key = PushToTalkKey()

        #expect(key.handle(.keyDown) == nil)
        #expect(key.handle(.flagsChanged(trigger: false, otherModifiers: true)) == nil)
    }
}
