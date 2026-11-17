import Testing
@testable import Core

/// The 🌐 key's own macOS action ("Press 🌐 key to"), held at Do Nothing while the app uses fn.
@MainActor
struct GlobeKeyActionTests {
    /// macOS's setting and the app's saved copy of the original, as the real ones behave.
    @MainActor
    final class FakeSystem {
        var value: Int32? = 2  // Show Emoji & Symbols; nil when the system call isn't available
        var keyExists = true
        var saved: GlobeKeyAction.Saved?
        private(set) var writes: [Int32] = []
        private(set) var cleared = false

        func action() -> GlobeKeyAction {
            GlobeKeyAction(
                current: { self.value },
                update: { self.value = $0; self.writes.append($0) },
                keyExists: { self.keyExists },
                clearKey: { self.cleared = true; self.keyExists = false },
                load: { self.saved },
                save: { self.saved = $0 }
            )
        }
    }

    let system = FakeSystem()

    @Test func usingFnSetsDoNothingAndRemembersTheOriginal() {
        system.action().take()

        #expect(system.value == GlobeKeyAction.doNothing)
        #expect(system.saved == GlobeKeyAction.Saved(original: 2, keyExisted: true))
    }

    @Test func quittingPutsTheOriginalBack() {
        let action = system.action()
        action.take()

        action.giveBack()

        #expect(system.value == 2)
        #expect(system.saved == nil)
    }

    @Test func aMacOSDefaultIsPutBackAsTheDefault() {
        system.keyExists = false
        let action = system.action()
        action.take()

        action.giveBack()

        #expect(system.value == 2)
        #expect(system.cleared)  // the key goes again, so macOS keeps choosing the default itself
    }

    @Test func aChangeTheUserMakesWhileTheAppRunsWins() {
        let action = system.action()
        action.take()
        system.value = 1  // the user picks "Change Input Source" in System Settings

        action.giveBack()

        #expect(system.value == 1)
        #expect(system.writes == [GlobeKeyAction.doNothing])
        #expect(system.saved == nil)
    }

    @Test func doNothingAlreadyIsLeftAlone() {
        system.value = GlobeKeyAction.doNothing
        let action = system.action()

        action.take()
        action.giveBack()

        #expect(system.writes.isEmpty)
        #expect(system.saved == nil)
    }

    @Test func afterACrashTheSavedOriginalIsStillPutBack() {
        system.action().take()  // a run that never quit cleanly

        let next = system.action()
        next.recover()
        next.giveBack()

        #expect(system.value == 2)
        #expect(system.saved == nil)
    }

    @Test func afterACrashANewChoiceByTheUserWins() {
        system.action().take()
        system.value = 3  // changed after the crash

        let next = system.action()
        next.recover()
        next.giveBack()

        #expect(system.value == 3)
        #expect(system.saved == nil)
    }

    @Test func withoutTheSystemCallNothingChanges() {
        system.value = nil

        system.action().take()

        #expect(system.writes.isEmpty)
        #expect(system.saved == nil)
    }
}
