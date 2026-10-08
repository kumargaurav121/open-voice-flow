import Foundation

/// What a dictation session reports as it moves through its stages.
public enum SessionEvent: Equatable, Sendable {
    case listening
    case transcribing
    case inserted(SessionTimings)
    case ignored(IgnoreReason)
    case failed(SessionFailure)
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
