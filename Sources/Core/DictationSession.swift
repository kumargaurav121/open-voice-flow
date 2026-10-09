import Foundation

/// One push-to-talk dictation: key down starts recording, key up transcribes and inserts.
@MainActor
public final class DictationSession {
    /// Presses shorter than this are treated as accidental taps.
    public static let minimumPressDuration: TimeInterval = 0.25

    public var onEvent: (SessionEvent) -> Void = { _ in }
    /// Each final transcript, inserted or not (history).
    public var onTranscript: (SessionTranscript) -> Void = { _ in }

    private enum State {
        case idle
        case recording(pressedAt: TimeInterval, app: String?)
        case processing
    }

    private let recorder: AudioRecorder
    private let speechToText: SpeechToText
    private let inserter: TextInserter
    private let now: () -> TimeInterval
    private let language: () -> Language
    private let frontmostApp: () -> String?
    private var state = State.idle

    public init(
        recorder: AudioRecorder,
        speechToText: SpeechToText,
        inserter: TextInserter,
        now: @escaping () -> TimeInterval,
        language: @escaping () -> Language,
        frontmostApp: @escaping () -> String? = { nil }
    ) {
        self.recorder = recorder
        self.speechToText = speechToText
        self.inserter = inserter
        self.now = now
        self.language = language
        self.frontmostApp = frontmostApp
    }

    public func keyDown() {
        guard case .idle = state else { return }
        do {
            try recorder.start()
        } catch {
            onEvent(.failed(.microphone))
            return
        }
        state = .recording(pressedAt: now(), app: frontmostApp())
        onEvent(.listening)
    }

    /// Stops a recording in progress and throws it away.
    public func cancel() async {
        guard case .recording = state else { return }
        state = .processing
        _ = await recorder.stop()
        state = .idle
        onEvent(.ignored(.cancelled))
    }

    public func keyUp() async {
        guard case .recording(let pressedAt, let app) = state else { return }
        state = .processing
        defer { state = .idle }

        let clip = await recorder.stop()
        let releasedAt = now()
        guard releasedAt - pressedAt >= Self.minimumPressDuration else {
            onEvent(.ignored(.tooShort))
            return
        }
        guard !clip.isEmpty else {
            onEvent(.ignored(.noSpeech))
            return
        }

        onEvent(.transcribing)
        let language = language()
        let text: String
        do {
            text = try await speechToText.transcribe(clip, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            onEvent(.failed(.transcription))
            return
        }
        guard !text.isEmpty else {
            onEvent(.ignored(.emptyTranscript))
            return
        }

        let transcribedAt = now()
        do {
            try await inserter.insert(text)
        } catch {
            onEvent(.failed(.insertion))
            onTranscript(SessionTranscript(text: text, language: language, app: app, inserted: false, clip: clip))
            return
        }
        // The notch hears first; saving to history comes after.
        onEvent(.inserted(SessionTimings(
            capture: releasedAt - pressedAt,
            transcribe: transcribedAt - releasedAt,
            insert: now() - transcribedAt
        )))
        onTranscript(SessionTranscript(text: text, language: language, app: app, inserted: true, clip: clip))
    }
}
