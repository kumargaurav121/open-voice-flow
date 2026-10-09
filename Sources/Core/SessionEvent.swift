import Foundation

/// What a dictation session reports as it moves through its stages.
public enum SessionEvent: Equatable, Sendable {
    case listening
    case transcribing
    case inserted(SessionTimings)
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

    public init(text: String, language: Language, app: String?, inserted: Bool, clip: AudioClip) {
        self.text = text
        self.language = language
        self.app = app
        self.inserted = inserted
        self.clip = clip
    }
}

public enum SessionFailure: Equatable, Sendable {
    case microphone
    case transcription
    case insertion
}

public enum IgnoreReason: Equatable, Sendable {
    /// Key released before `DictationSession.minimumPressDuration`.
    case tooShort
    /// Nothing left after trimming silence.
    case noSpeech
    /// Speech-to-text returned only whitespace.
    case emptyTranscript
    /// Recording stopped via `DictationSession.cancel()`.
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
