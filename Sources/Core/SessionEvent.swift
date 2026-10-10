import Foundation

/// Which hotkey started a session.
public enum SessionKind: String, Equatable, Sendable {
    /// Text goes into the focused app.
    case dictation
    /// Parsed into an action (SPEC §4.3); never typed.
    case command
}

/// What a push-to-talk session reports as it moves through its stages.
public enum SessionEvent: Equatable, Sendable {
    case listening(SessionKind)
    case transcribing
    case inserted(SessionTimings)
    /// A command understood as a known action (not run yet; ticket 12).
    case commandParsed(CommandIntent)
    /// A command that isn't a known action; carries the transcript so it isn't lost.
    case commandUnknown(transcript: String)
    case ignored(IgnoreReason)
    case failed(SessionFailure)
}

/// A dictation's final text, for history. Reported whether or not it reached the app, so text that
/// couldn't be inserted isn't lost.
public struct SessionTranscript: Equatable, Sendable {
    public var text: String
    public var language: Language
    /// The app in front when recording started.
    public var app: String?
    public var inserted: Bool
    public var clip: AudioClip
    public var kind: SessionKind
    /// For a command, what it did ("→ Slack · Gurjeet · "Hi"", "Can't do that yet").
    public var outcome: String?

    public init(text: String, language: Language, app: String?, inserted: Bool, clip: AudioClip,
                kind: SessionKind = .dictation, outcome: String? = nil) {
        self.text = text
        self.language = language
        self.app = app
        self.inserted = inserted
        self.clip = clip
        self.kind = kind
        self.outcome = outcome
    }
}

public enum SessionFailure: Equatable, Sendable {
    case microphone
    case transcription
    case insertion
}

public enum IgnoreReason: Equatable, Sendable {
    /// Key released before `PushToTalkSession.minimumPressDuration`.
    case tooShort
    /// Nothing left after trimming silence.
    case noSpeech
    /// Speech-to-text returned only whitespace.
    case emptyTranscript
    /// Recording stopped via `PushToTalkSession.cancel()`.
    case cancelled
}

/// Seconds spent in each stage of a completed session.
public struct SessionTimings: Equatable, Sendable {
    public var capture: TimeInterval
    public var transcribe: TimeInterval
    public var insert: TimeInterval

    public init(capture: TimeInterval, transcribe: TimeInterval, insert: TimeInterval) {
        self.capture = capture
        self.transcribe = transcribe
        self.insert = insert
    }
}
