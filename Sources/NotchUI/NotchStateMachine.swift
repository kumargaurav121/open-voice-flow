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
        /// `expanded` once clicked: shows `NotchError.details` under the message.
        case error(NotchError, expanded: Bool)
    }

    public enum Input: Sendable, Equatable {
        case session(SessionEvent)
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
    public static let expandedErrorHold: TimeInterval = 10

    public private(set) var phase = Phase.idle
    private var timerToken = 0

    public init() {}

    @discardableResult
    public mutating func handle(_ input: Input) -> Effect? {
        // Any new session event supersedes a pending collapse (e.g. pressing again during the ✓).
        if case .session = input { timerToken += 1 }
        switch input {
        case .session(.listening(let kind)):
            phase = .listening(kind == .command ? .command : .dictation)
        case .session(.commandParsed(let intent)):
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

    private mutating func scheduleReturn(after delay: TimeInterval) -> Effect {
        timerToken += 1
        return .returnToIdle(after: delay, token: timerToken)
    }
}

/// A failure as the notch shows it: a few words, plus what to do about it on click.
public struct NotchError: Sendable, Equatable {
    public let message: String
    public let details: String

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
