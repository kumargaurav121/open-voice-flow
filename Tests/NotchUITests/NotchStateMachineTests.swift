import Core
import Testing
@testable import NotchUI

struct NotchStateMachineTests {
    @Test func startsIdle() {
        #expect(NotchStateMachine().phase == .idle)
    }

    @Test func aDictationPressShowsListening() {
        var notch = NotchStateMachine()

        notch.handle(.session(.listening))

        #expect(notch.phase == .listening(.dictation))
    }

    @Test func releaseShowsTranscribing() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))

        notch.handle(.session(.transcribing))

        #expect(notch.phase == .transcribing)
    }

    @Test func insertedShowsACheckThenReturnsToIdle() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))
        notch.handle(.session(.transcribing))

        let effect = notch.handle(.session(.inserted(SessionTimings(capture: 1, transcribe: 1, insert: 0))))

        #expect(notch.phase == .inserted)
        guard case .returnToIdle(let delay, let token) = effect else {
            Issue.record("expected a scheduled return to idle, got \(String(describing: effect))")
            return
        }
        #expect(delay == NotchStateMachine.insertedHold)

        notch.handle(.timerFired(token))
        #expect(notch.phase == .idle)
    }

    func insertedThenPressedAgain() -> (NotchStateMachine, staleToken: Int) {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))
        let effect = notch.handle(.session(.inserted(SessionTimings(capture: 1, transcribe: 1, insert: 0))))
        guard case .returnToIdle(_, let token) = effect else { fatalError("no timer") }
        notch.handle(.session(.listening))
        return (notch, token)
    }

    @Test func aTimerFromAnEarlierSessionDoesNotCollapseANewOne() {
        var (notch, stale) = insertedThenPressedAgain()

        notch.handle(.timerFired(stale))

        #expect(notch.phase == .listening(.dictation))
    }

    @Test(arguments: [IgnoreReason.tooShort, .noSpeech, .emptyTranscript, .cancelled])
    func ignoredPressesCollapseImmediately(reason: IgnoreReason) {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))

        let effect = notch.handle(.session(.ignored(reason)))

        #expect(notch.phase == .idle)
        #expect(effect == nil)
    }

    @Test func aFailureShowsAShortMessageThenReturnsToIdle() {
        var notch = NotchStateMachine()
        notch.handle(.session(.transcribing))

        let effect = notch.handle(.session(.failed(.transcription)))

        #expect(notch.phase == .error(NotchError(.transcription), expanded: false))
        guard case .returnToIdle(let delay, let token) = effect else {
            Issue.record("expected a scheduled return to idle")
            return
        }
        #expect(delay == NotchStateMachine.errorHold)
        notch.handle(.timerFired(token))
        #expect(notch.phase == .idle)
    }

    @Test func clickingAnErrorShowsDetailsAndHoldsItLonger() {
        var notch = NotchStateMachine()
        notch.handle(.session(.failed(.insertion)))

        let effect = notch.handle(.clicked)

        #expect(notch.phase == .error(NotchError(.insertion), expanded: true))
        guard case .returnToIdle(let delay, _) = effect else {
            Issue.record("expected a longer hold")
            return
        }
        #expect(delay == NotchStateMachine.expandedErrorHold)
    }

    @Test func clickingWhenThereIsNoErrorDoesNothing() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))

        #expect(notch.handle(.clicked) == nil)
        #expect(notch.phase == .listening(.dictation))
    }

    @Test func aNewPressReplacesAnError() {
        var notch = NotchStateMachine()
        notch.handle(.session(.failed(.microphone)))

        notch.handle(.session(.listening))

        #expect(notch.phase == .listening(.dictation))
    }

    @Test func errorsHaveAShortMessageAndActionableDetails() {
        for failure in [SessionFailure.microphone, .transcription, .insertion] {
            let error = NotchError(failure)
            #expect(!error.message.isEmpty && error.message.count <= 32, "message must fit the notch: \(error.message)")
            #expect(error.details.count > error.message.count)
        }
    }

    @Test func clickingAnExpandedErrorClosesIt() {
        var notch = NotchStateMachine()
        notch.handle(.session(.failed(.insertion)))
        notch.handle(.clicked)

        let effect = notch.handle(.clicked)

        #expect(notch.phase == .idle)
        #expect(effect == nil)
    }

    @Test func theShortErrorTimerCannotCloseAnErrorTheUserExpanded() {
        var notch = NotchStateMachine()
        guard case .returnToIdle(_, let shortTimer) = notch.handle(.session(.failed(.transcription))) else {
            Issue.record("expected a timer")
            return
        }
        notch.handle(.clicked)

        notch.handle(.timerFired(shortTimer))

        #expect(notch.phase == .error(NotchError(.transcription), expanded: true))
    }

    @Test func pressingAgainDuringTheCheckGoesStraightToListening() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening))
        notch.handle(.session(.inserted(SessionTimings(capture: 1, transcribe: 1, insert: 0))))

        let effect = notch.handle(.session(.listening))

        #expect(notch.phase == .listening(.dictation))
        #expect(effect == nil)
    }
}
