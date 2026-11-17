import Foundation

/// One push-to-talk session: key down starts recording, key up transcribes, then inserts the text
/// (dictation) or parses it into an action (command, never typed). One session at a time, whichever key
/// started it. With `live`, a dictation is transcribed while the key is held (cut at the speaker's pauses),
/// so only the tail is left at release.
@MainActor
public final class PushToTalkSession {
    /// Presses shorter than this are treated as accidental taps.
    public static let minimumPressDuration: TimeInterval = 0.25

    public var onEvent: (SessionEvent) -> Void = { _ in }
    /// Each final transcript, inserted or not (history).
    public var onTranscript: (SessionTranscript) -> Void = { _ in }

    private enum State {
        case idle
        /// The language is fixed when the key goes down, so switching it mid-dictation can't mix models.
        case recording(pressedAt: TimeInterval, app: String?, kind: SessionKind, language: Language)
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
    /// The pipeline's live transcriber, for transcribing while the user speaks. It must be inside
    /// `speechToText`, which returns the dictation's text.
    private let live: LiveTranscriber?
    private var state = State.idle
    /// Esc pressed while a command was being transcribed or understood: its result is dropped.
    private var commandCancelled = false
    private var processingCommand = false
    /// Esc pressed after a dictation was released, before its text was pasted.
    private var dictationCancelled = false

    public init(
        recorder: AudioRecorder,
        speechToText: SpeechToText,
        inserter: TextInserter,
        now: @escaping () -> TimeInterval,
        language: @escaping () -> Language,
        frontmostApp: @escaping () -> String? = { nil },
        commands: CommandParser? = nil,
        commandSpeechToText: SpeechToText? = nil,
        live: LiveTranscriber? = nil
    ) {
        self.recorder = recorder
        self.speechToText = speechToText
        self.inserter = inserter
        self.now = now
        self.language = language
        self.frontmostApp = frontmostApp
        self.commands = commands
        self.commandSpeechToText = commandSpeechToText
        self.live = live
    }

    public func keyDown(_ kind: SessionKind = .dictation) {
        guard case .idle = state, kind == .dictation || commands != nil else { return }
        // Commands are short and parsed whole; only dictation is transcribed while the key is held.
        recorder.onAudio = kind == .dictation && live != nil ? { [weak self] in self?.audioArrived() } : nil
        do {
            try recorder.start()
        } catch {
            onEvent(.failed(.microphone))
            return
        }
        let language = language()
        if kind == .dictation { live?.begin(language: language) }
        state = .recording(pressedAt: now(), app: frontmostApp(), kind: kind, language: language)
        onEvent(.listening(kind))
    }

    /// Stops a recording in progress and throws it away, with anything already transcribed of it; also a
    /// command still being transcribed or understood, and a dictation that hasn't been pasted yet.
    public func cancel() async {
        if case .processing = state {
            if processingCommand {
                commandCancelled = true
            } else {
                dictationCancelled = true
                live?.discard()
            }
            return
        }
        guard case .recording = state else { return }
        state = .processing
        _ = await recorder.stop()
        live?.discard()
        state = .idle
        onEvent(.ignored(.cancelled))
    }

    /// New audio while the dictation key is held. After release, keyUp takes what's left itself.
    private func audioArrived() {
        guard case .recording(_, _, .dictation, _) = state else { return }
        live?.listen(recorder.takeAudio())
    }

    public func keyUp() async {
        guard case .recording(let pressedAt, let app, let kind, let language) = state else { return }
        state = .processing
        processingCommand = kind == .command
        commandCancelled = false
        dictationCancelled = false
        defer {
            state = .idle
            processingCommand = false
        }

        let clip = await recorder.stop()
        let releasedAt = now()
        if kind == .dictation { live?.listen(recorder.takeAudio()) }  // audio that arrived as the key went up
        guard releasedAt - pressedAt >= Self.minimumPressDuration else {
            live?.discard()
            onEvent(.ignored(.tooShort))
            return
        }
        onEvent(.released(kind))
        guard !clip.isEmpty else {
            live?.discard()
            onEvent(.ignored(.noSpeech))
            return
        }

        onEvent(.transcribing)
        let text: String
        // Commands can have their own pipeline (the app's skips AI cleanup).
        let transcriber = kind == .command ? commandSpeechToText ?? speechToText : speechToText
        do {
            text = try await transcriber.transcribe(clip, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            onEvent(dictationCancelled ? .ignored(.cancelled) : .failed(.transcription))
            return
        }
        guard !dictationCancelled else {
            onEvent(.ignored(.cancelled))
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
            insert: now() - transcribedAt,
            parts: live?.lastCut.parts ?? 0,
            tail: live?.lastCut.tail ?? clip.duration
        )))
        onTranscript(SessionTranscript(text: text, language: language, app: app, inserted: true, clip: clip))
    }
}
