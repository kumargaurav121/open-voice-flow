import Testing
@testable import Core

/// A fake adapter: steps that record when they run, optionally slow or failing.
@MainActor
final class StepLog {
    var ran: [String] = []
    func step(_ title: String, takes delay: Duration = .zero, fails: Bool = false,
              timeout: Duration = .seconds(1), irreversible: Bool = false, resolves recipient: String? = nil) -> ActionStep {
        ActionStep(title: title, timeout: timeout, irreversible: irreversible) { context in
            if delay > .zero { try await Task.sleep(for: delay) }
            if fails { throw StepFailure(reason: "\(title) didn't work") }
            if let recipient { context.recipient = recipient }
            self.ran.append(title)
        }
    }
}

@MainActor
struct ActionRunnerTests {
    let log = StepLog()

    func run(_ steps: [ActionStep], countdown: Duration = .milliseconds(30),
             during: ((ActionRunner) -> Void)? = nil) async -> (ActionOutcome, [ActionEvent]) {
        let runner = ActionRunner(countdown: countdown, tick: .milliseconds(10))
        var events: [ActionEvent] = []
        runner.onEvent = { event in
            events.append(event)
            during?(runner)
        }
        let outcome = await runner.run(steps)
        return (outcome, events)
    }

    @Test func stepsRunInOrderAndReportLive() async {
        let (outcome, events) = await run([log.step("Open Slack"), log.step("Find Gurjeet", resolves: "Gurjeet Singh"),
                                           log.step("Send", irreversible: true)])

        #expect(outcome == .done)
        #expect(log.ran == ["Open Slack", "Find Gurjeet", "Send"])
        #expect(events.first == .started(["Open Slack", "Find Gurjeet", "Send"]))
        #expect(events.contains(.stepStarted(1)) && events.contains(.stepFinished(1)))
        #expect(events.last == .finished)
    }

    @Test func anIrreversibleStepWaitsBehindACountdownWithTheResolvedName() async {
        let (_, events) = await run([log.step("Find Gurjeet", resolves: "Gurjeet Singh"), log.step("Send", irreversible: true)],
                                    countdown: .milliseconds(30))

        let countdowns = events.compactMap { if case .countingDown(let left, let to) = $0 { (left, to) } else { nil } }
        #expect(!countdowns.isEmpty)
        #expect(countdowns.allSatisfy { $0.1 == "Gurjeet Singh" })
        let countdownEnd = events.lastIndex { if case .countingDown = $0 { true } else { false } }!
        #expect(events.firstIndex(of: .stepStarted(1))! > countdownEnd)
    }

    @Test func cancellingDuringTheCountdownSendsNothing() async {
        var cancelled = false
        let (outcome, events) = await run([log.step("Find", resolves: "Gurjeet Singh"), log.step("Send", irreversible: true)],
                                          countdown: .seconds(5)) { runner in
            if !cancelled, case .countingDown = (runner.lastEvent ?? .finished) {
                cancelled = true
                runner.cancel()
            }
        }

        #expect(outcome == .cancelled)
        #expect(log.ran == ["Find"])
        #expect(events.last == .cancelled)
    }

    @Test func cancellingDuringAStepStopsBeforeTheNextOne() async {
        var cancelled = false
        let (outcome, _) = await run([log.step("Slow", takes: .milliseconds(200)), log.step("Next")]) { runner in
            if !cancelled, runner.lastEvent == .stepStarted(0) {
                cancelled = true
                runner.cancel()
            }
        }

        #expect(outcome == .cancelled)
        #expect(log.ran.isEmpty)
    }

    @Test func escRightAsTheSendStepStartsSendsNothing() async {
        // The irreversible step checks for cancellation itself, at its point of no return.
        var sent = false
        let send = ActionStep(title: "Send", timeout: .seconds(1), irreversible: true) { context in
            try context.commit()  // throws if cancelled
            sent = true
        }
        var cancelled = false
        let (outcome, _) = await run([send], countdown: .milliseconds(10)) { runner in
            if !cancelled, runner.lastEvent == .stepStarted(0) {
                cancelled = true
                runner.cancel()
            }
        }

        #expect(outcome == .cancelled)
        #expect(!sent)
    }

    @Test func afterThePointOfNoReturnItCountsAsSentWhateverHappens() async {
        // Return was pressed: Esc or a timeout now can't un-send it, so it must not say "nothing sent".
        let send = ActionStep(title: "Send", timeout: .milliseconds(50), irreversible: true) { context in
            try context.commit()
            try await Task.sleep(for: .seconds(5))  // waiting for Slack to confirm; times out
        }

        let (outcome, events) = await run([send], countdown: .milliseconds(10))

        #expect(outcome == .probablySent(reason: "Send took too long"))
        #expect(events.last == .probablySent(reason: "Send took too long"))
    }

    @Test func aFailingStepStopsTheActionAndSaysWhich() async {
        let (outcome, events) = await run([log.step("Open Slack"), log.step("Find Gurjeet", fails: true), log.step("Send", irreversible: true)])

        #expect(outcome == .failed(step: "Find Gurjeet", reason: "Find Gurjeet didn't work"))
        #expect(log.ran == ["Open Slack"])
        #expect(events.last == .failed(step: 1, reason: "Find Gurjeet didn't work"))
    }

    @Test func aStepThatTakesTooLongTimesOut() async {
        let (outcome, _) = await run([log.step("Open Slack", takes: .seconds(5), timeout: .milliseconds(30)), log.step("Next")])

        #expect(outcome == .failed(step: "Open Slack", reason: "Open Slack took too long"))
        #expect(log.ran.isEmpty)
    }
}
