import Core
import Foundation

/// What the notch shows, driven by dictation session events (SPEC §4.5).
public struct NotchStateMachine: Sendable {
    public enum Mode: Sendable, Equatable {
        case dictation
        /// The command hotkey; gets its own colour.
        case command
    }

    /// What a command came to, shown in the Command colour.
    public enum CommandResult: Sendable, Equatable {
        case parsed(CommandIntent)
        /// "Can't do that yet" (the transcript went to the clipboard).
        case unknown

        public var text: String {
            switch self {
            case .parsed(let intent): intent.summary
            case .unknown: CommandIntent.unknownSummary
            }
        }
    }

    public enum Phase: Sendable, Equatable {
        case idle
        case listening(Mode)
        case transcribing
        case inserted
        case command(CommandResult)
        /// An action running in the app, step by step (ticket 12).
        case acting(ActionProgress)
        /// `confirmed` false: the send went out but Slack's confirmation didn't arrive (Esc or a timeout after Return).
        case sent(to: String?, confirmed: Bool)
        /// Esc stopped the action; nothing was sent.
        case stopped
        /// `expanded` once clicked: shows `NotchError.details` under the message.
        case error(NotchError, expanded: Bool)
    }

    public enum Input: Sendable, Equatable {
        case session(SessionEvent)
        case action(ActionEvent)
        /// A scheduled `Effect.returnToIdle` came due.
        case timerFired(Int)
        case clicked
    }

    public enum Effect: Sendable, Equatable {
        /// Fire `.timerFired(token)` after `delay`; stale tokens are ignored.
        case returnToIdle(after: TimeInterval, token: Int)
    }

    /// How long the ✓ stays before the notch collapses.
    public static let insertedHold: TimeInterval = 0.9
    /// Long enough to read a 3-4 word message.
    public static let errorHold: TimeInterval = 3
    /// Long enough to read who and what.
    public static let commandHold: TimeInterval = 3
    public static let sentHold: TimeInterval = 1.5
    public static let expandedErrorHold: TimeInterval = 10

    public private(set) var phase = Phase.idle
    private var timerToken = 0
    /// The command an action is carrying out, for its progress line.
    private var intent: CommandIntent?

    public init() {}

    @discardableResult
    public mutating func handle(_ input: Input) -> Effect? {
        // Any new session event supersedes a pending collapse (e.g. pressing again during the ✓).
        if case .session = input { timerToken += 1 }
        if case .action = input { timerToken += 1 }
        switch input {
        case .action(let event):
            return handle(event)
        case .session(.listening(let kind)):
            intent = nil  // a new session; any earlier command is done with
            phase = .listening(kind == .command ? .command : .dictation)
        case .session(.commandParsed(let intent)):
            self.intent = intent
            phase = .command(.parsed(intent))
            return scheduleReturn(after: Self.commandHold)
        case .session(.commandUnknown):
            phase = .command(.unknown)
            return scheduleReturn(after: Self.commandHold)
        case .session(.transcribing):
            phase = .transcribing
        case .session(.inserted):
            phase = .inserted
            return scheduleReturn(after: Self.insertedHold)
        case .session(.ignored):
            phase = .idle
        case .session(.failed(let failure)):
            phase = .error(NotchError(failure), expanded: false)
            return scheduleReturn(after: Self.errorHold)
        case .clicked:
            guard case .error(let error, let expanded) = phase else { return nil }
            timerToken += 1  // supersede the pending collapse either way
            if expanded {
                phase = .idle  // the "Close" label
                return nil
            }
            phase = .error(error, expanded: true)
            return scheduleReturn(after: Self.expandedErrorHold)
        case .timerFired(let token):
            if token == timerToken { phase = .idle }
        }
        return nil
    }

    private mutating func handle(_ event: ActionEvent) -> Effect? {
        var progress: ActionProgress
        if case .acting(let current) = phase {
            progress = current
        } else {
            progress = ActionProgress(steps: [], message: intent?.messageText ?? "", spokenName: intent?.recipientName ?? "")
        }
        switch event {
        case .started(let steps):
            phase = .acting(ActionProgress(steps: steps, message: intent?.messageText ?? "", spokenName: intent?.recipientName ?? ""))
        case .stepStarted(let index):
            progress.current = index
            progress.secondsLeft = nil
            phase = .acting(progress)
        case .stepFinished(let index):
            progress.done = index + 1
            phase = .acting(progress)
        case .countingDown(let seconds, let recipient):
            progress.countdownTotal = max(progress.countdownTotal, seconds)
            progress.secondsLeft = seconds
            progress.recipient = recipient
            phase = .acting(progress)
        case .finished:
            phase = .sent(to: progress.recipient, confirmed: true)
            return scheduleReturn(after: Self.sentHold)
        case .cancelled:
            phase = .stopped
            return scheduleReturn(after: Self.sentHold)
        case .probablySent:
            phase = .sent(to: progress.recipient, confirmed: false)
            return scheduleReturn(after: Self.errorHold)
        case .failed(let index, let reason):
            let step = progress.steps.indices.contains(index) ? progress.steps[index] : "a step"
            phase = .error(NotchError(message: reason,
                                      details: "Stopped at “\(step)”. Nothing was sent; the message is on the clipboard."),
                           expanded: false)
            return scheduleReturn(after: Self.errorHold)
        }
        return nil
    }

    private mutating func scheduleReturn(after delay: TimeInterval) -> Effect {
        timerToken += 1
        return .returnToIdle(after: delay, token: timerToken)
    }
}

/// An action in progress, as the notch shows it.
public struct ActionProgress: Sendable, Equatable {
    public var steps: [String]
    /// The step running now.
    public var current = 0
    /// How many steps are finished.
    public var done = 0
    public var secondsLeft: Int?
    /// The countdown's starting value, for the draining ring.
    public var countdownTotal = 0
    /// The full name the search resolved, once known.
    public var recipient: String?
    /// The name as spoken, shown until the search resolves it.
    public var spokenName: String
    public var message: String

    public init(steps: [String], message: String, spokenName: String = "") {
        self.steps = steps
        self.message = message
        self.spokenName = spokenName
    }

    /// Who it's going to, as well as it's known so far.
    public var recipientName: String { recipient ?? spokenName }

    /// The line under the badge: the step running, or the countdown.
    public var headline: String {
        if let secondsLeft {
            return "→ \(recipient ?? "?") · \"\(message)\" · sending in \(secondsLeft)s"
        }
        return steps.indices.contains(current) ? steps[current] : ""
    }
}

/// A failure as the notch shows it: a few words, plus what to do about it on click.
public struct NotchError: Sendable, Equatable {
    public let message: String
    public let details: String

    public init(message: String, details: String) {
        self.message = message
        self.details = details
    }

    public init(_ failure: SessionFailure) {
        switch failure {
        case .microphone:
            message = "Microphone unavailable"
            details = "Check that a microphone is connected and that Open Voice Flow is allowed in System Settings › Privacy & Security › Microphone."
        case .transcription:
            message = "Couldn't transcribe that"
            details = "The speech model failed on that recording. Try again; if it keeps failing, use Retry Loading Model in the menu bar."
        case .insertion:
            message = "Couldn't paste the text"
            details = "Open Voice Flow needs Accessibility permission to paste. Allow it in System Settings › Privacy & Security › Accessibility."
        }
    }
}
