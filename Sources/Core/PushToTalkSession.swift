import Foundation

/// One push-to-talk session: key down starts recording, key up transcribes, then inserts the text
/// (dictation) or parses it into an action (command, never typed). One session at a time, whichever key
/// started it.
@MainActor
public final class PushToTalkSession {
    /// Presses shorter than this are treated as accidental taps.
    public static let minimumPressDuration: TimeInterval = 0.25

    public var onEvent: (SessionEvent) -> Void = { _ in }
    /// Each final transcript, inserted or not (history).
    public var onTranscript: (SessionTranscript) -> Void = { _ in }

    private enum State {
        case idle
        case recording(pressedAt: TimeInterval, app: String?, kind: SessionKind)
        case processing
    }

    private let recorder: AudioRecorder
    private let speechToText: SpeechToText
    private let inserter: TextInserter
    private let now: () -> TimeInterval
    private let language: () -> Language
    private let frontmostApp: () -> String?
    private let commands: CommandParser?
    private let commandSpeechToText: SpeechToText?
    private var state = State.idle
    /// Esc pressed while a command was being transcribed or understood: its result is dropped.
    private var commandCancelled = false
    private var processingCommand = false

    public init(
        recorder: AudioRecorder,
        speechToText: SpeechToText,
        inserter: TextInserter,
        now: @escaping () -> TimeInterval,
        language: @escaping () -> Language,
        frontmostApp: @escaping () -> String? = { nil },
        commands: CommandParser? = nil,
        commandSpeechToText: SpeechToText? = nil
    ) {
        self.recorder = recorder
        self.speechToText = speechToText
        self.inserter = inserter
        self.now = now
        self.language = language
        self.frontmostApp = frontmostApp
        self.commands = commands
        self.commandSpeechToText = commandSpeechToText
    }

    public func keyDown(_ kind: SessionKind = .dictation) {
        guard case .idle = state, kind == .dictation || commands != nil else { return }
        do {
            try recorder.start()
        } catch {
            onEvent(.failed(.microphone))
            return
        }
        state = .recording(pressedAt: now(), app: frontmostApp(), kind: kind)
        onEvent(.listening(kind))
    }

    /// Stops a recording in progress and throws it away; for a command, also one still being
    /// transcribed or understood (dictation past release can't be stopped halfway through typing).
    public func cancel() async {
        if case .processing = state, processingCommand {
            commandCancelled = true
            return
        }
        guard case .recording = state else { return }
        state = .processing
        _ = await recorder.stop()
        state = .idle
        onEvent(.ignored(.cancelled))
    }

    public func keyUp() async {
        guard case .recording(let pressedAt, let app, let kind) = state else { return }
        state = .processing
        processingCommand = kind == .command
        commandCancelled = false
        defer {
            state = .idle
            processingCommand = false
        }

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
        // Commands can have their own pipeline (the app's skips AI cleanup).
        let transcriber = kind == .command ? commandSpeechToText ?? speechToText : speechToText
        do {
            text = try await transcriber.transcribe(clip, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            onEvent(.failed(.transcription))
            return
        }
        guard !text.isEmpty else {
            onEvent(.ignored(.emptyTranscript))
            return
        }

        if kind == .command, let commands {
            let intent = commandCancelled ? nil : await commands.parse(text)
            guard !commandCancelled else {
                onEvent(.ignored(.cancelled))
                return
            }
            onEvent(intent.map { .commandParsed($0) } ?? .commandUnknown(transcript: text))
            onTranscript(SessionTranscript(text: text, language: language, app: app, inserted: false, clip: clip,
                                           kind: .command, outcome: intent?.summary ?? CommandIntent.unknownSummary))
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
