import Core
import Testing
@testable import NotchUI

struct NotchActionTests {
    let intent = CommandIntent.sendMessage(app: "slack", to: "Gurjeet", text: "I'll be late")
    let steps = ["Open Slack", "Find Gurjeet", "Open the DM", "Write the message", "Send"]

    func acting() -> NotchStateMachine {
        var notch = NotchStateMachine()
        notch.handle(.session(.commandParsed(intent)))
        notch.handle(.action(.started(steps)))
        return notch
    }

    @Test func eachStepIsShownAsItRuns() {
        var notch = acting()
        notch.handle(.action(.stepStarted(0)))
        notch.handle(.action(.stepFinished(0)))
        notch.handle(.action(.stepStarted(1)))

        guard case .acting(let progress) = notch.phase else {
            Issue.record("expected acting, got \(notch.phase)")
            return
        }
        #expect(progress.steps == steps)
        #expect(progress.current == 1)
        #expect(progress.done == 1)
        #expect(progress.message == "I'll be late")
    }

    @Test func theCountdownShowsWhoItsGoingTo() {
        var notch = acting()
        notch.handle(.action(.countingDown(secondsLeft: 3, to: "Gurjeet Singh")))

        guard case .acting(let progress) = notch.phase else {
            Issue.record("expected acting")
            return
        }
        #expect(progress.secondsLeft == 3)
        #expect(progress.recipient == "Gurjeet Singh")
        #expect(progress.headline == "→ Gurjeet Singh · \"I'll be late\" · sending in 3s")
    }

    @Test func sentThenTheNotchCloses() {
        var notch = acting()
        notch.handle(.action(.countingDown(secondsLeft: 1, to: "Gurjeet Singh")))

        let effect = notch.handle(.action(.finished))

        #expect(notch.phase == .sent(to: "Gurjeet Singh", confirmed: true))
        #expect(effect != nil)
    }

    @Test func stoppingSaysNothingWasSent() {
        var notch = acting()

        let effect = notch.handle(.action(.cancelled))

        #expect(notch.phase == .stopped)
        #expect(effect != nil)
    }

    @Test func aFailedStepIsNamed() {
        var notch = acting()
        notch.handle(.action(.stepStarted(1)))

        notch.handle(.action(.failed(step: 1, reason: "Couldn't find Gurjeet")))

        guard case .error(let error, false) = notch.phase else {
            Issue.record("expected an error")
            return
        }
        #expect(error.message == "Couldn't find Gurjeet")
        #expect(error.details.contains("Find Gurjeet"))
        #expect(error.details.contains("Nothing was sent"))
    }
}
