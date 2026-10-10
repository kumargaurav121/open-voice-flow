import Core
import Testing
@testable import NotchUI

struct NotchCommandTests {
    let intent = CommandIntent.sendMessage(app: "slack", to: "Gurjeet", text: "I'll be late")

    @Test func aCommandPressListensInTheCommandColour() {
        var notch = NotchStateMachine()

        notch.handle(.session(.listening(.command)))

        #expect(notch.phase == .listening(.command))
    }

    @Test func aParsedCommandIsShownThenTheNotchCloses() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening(.command)))
        notch.handle(.session(.transcribing))

        let effect = notch.handle(.session(.commandParsed(intent)))

        #expect(notch.phase == .command(.parsed(intent)))
        guard case .returnToIdle(let delay, let token) = effect else {
            Issue.record("expected a scheduled close")
            return
        }
        #expect(delay == NotchStateMachine.commandHold)
        notch.handle(.timerFired(token))
        #expect(notch.phase == .idle)
    }

    @Test func anUnknownCommandSaysItCantDoThatYet() {
        var notch = NotchStateMachine()
        notch.handle(.session(.listening(.command)))

        let effect = notch.handle(.session(.commandUnknown(transcript: "Book a flight")))

        #expect(notch.phase == .command(.unknown))
        #expect(effect != nil)
    }

    @Test func theCommandIsShownInWords() {
        #expect(intent.summary == "→ Slack · Gurjeet · \"I'll be late\"")
        #expect(CommandIntent.unknownSummary == "Can't do that yet")
    }
}
