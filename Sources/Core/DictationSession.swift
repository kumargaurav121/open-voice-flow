import Foundation

/// One push-to-talk dictation: key down starts recording, key up transcribes and inserts.
@MainActor
public final class DictationSession {
    /// Presses shorter than this are treated as accidental taps.
    public static let minimumPressDuration: TimeInterval = 0.25

    public var onEvent: (SessionEvent) -> Void = { _ in }

    private enum State {
        case idle
        case recording(pressedAt: TimeInterval)
        case processing
    }

    private let recorder: AudioRecorder
    private let speechToText: SpeechToText
    private let inserter: TextInserter
    private let now: () -> TimeInterval
    private let language: () -> Language
    private var state = State.idle

    public init(
        recorder: AudioRecorder,
        speechToText: SpeechToText,
        inserter: TextInserter,
        now: @escaping () -> TimeInterval,
        language: @escaping () -> Language
    ) {
        self.recorder = recorder
        self.speechToText = speechToText
        self.inserter = inserter
        self.now = now
        self.language = language
    }

    public func keyDown() {
        guard case .idle = state else { return }
        do {
            try recorder.start()
        } catch {
            onEvent(.failed(.microphone))
            return
        }
        state = .recording(pressedAt: now())
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
        guard case .recording(let pressedAt) = state else { return }
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
        let text: String
        do {
            text = try await speechToText.transcribe(clip, language: language())
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
            return
        }
        onEvent(.inserted(SessionTimings(
            capture: releasedAt - pressedAt,
            transcribe: transcribedAt - releasedAt,
            insert: now() - transcribedAt
        )))
    }
}
