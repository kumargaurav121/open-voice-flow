import Foundation

/// One push-to-talk session: key down starts recording, key up transcribes, then inserts the text
/// (dictation) or parses it into an action (command, never typed). One session at a time, whichever key
/// started it. With `live`, a dictation is transcribed while the key is held (cut at the speaker's pauses),
/// so only the tail is left at release.
///
/// Hands-free: two quick taps of the dictation key keep it recording without the key held; the next clean
/// tap of it stops and pastes, Esc throws it away, other keys and key combinations are ignored, and it stops
/// by itself at `handsFreeLimit`.
@MainActor
public final class PushToTalkSession {
    /// Presses shorter than this are treated as accidental taps.
    public static let minimumPressDuration: TimeInterval = 0.25
    /// A second quick tap this soon after the first one's release starts hands-free dictation.
    public static let doubleTapWindow: TimeInterval = 0.35
    /// Hands-free dictation stops by itself after this long (so a forgotten microphone doesn't stay on) and
    /// pastes what it heard.
    public static let handsFreeLimit: TimeInterval = 10 * 60

    public var onEvent: (SessionEvent) -> Void = { _ in }
    /// Each final transcript, inserted or not (history).
    public var onTranscript: (SessionTranscript) -> Void = { _ in }

    /// Where a dictation is in the hands-free double tap.
    private enum HandsFree {
        /// Held to talk, as usual.
        case off
        /// The second press of a double tap is down: a quick release makes it hands-free, a hold doesn't.
        case secondTap
        /// Recording without the key held.
        case on
        /// The key is down to stop it: a clean release stops, a combination with another key doesn't.
        case stopTap
    }

    private struct Recording {
        var pressedAt: TimeInterval
        var app: String?
        var kind: SessionKind
        /// Fixed when the key goes down, so switching it mid-dictation can't mix models.
        var language: Language
        var handsFree = HandsFree.off
    }

    private enum State {
        case idle
        case recording(Recording)
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
    private let handsFreeLimit: TimeInterval
    private let speechReady: (Language) -> Bool
    private var state = State.idle
    /// Esc pressed while a command was being transcribed or understood: its result is dropped.
    private var commandCancelled = false
    private var processingCommand = false
    /// Esc pressed after a dictation was released, before its text was pasted.
    private var dictationCancelled = false
    /// Until the text is pasted or the command's result shown, Esc drops it. It's reported at once, since the
    /// work still running can take a while (a model still loading); that work ends silently.
    private var canStillCancel = false
    private var cancelled: Bool { dictationCancelled || commandCancelled }
    /// When the last dictation tap (too short to be a press) was released: a quick tap soon after starts
    /// hands-free.
    private var tapReleasedAt: TimeInterval?
    private var handsFreeTimer: Task<Void, Never>?

    public init(
        recorder: AudioRecorder,
        speechToText: SpeechToText,
        inserter: TextInserter,
        now: @escaping () -> TimeInterval,
        language: @escaping () -> Language,
        frontmostApp: @escaping () -> String? = { nil },
        commands: CommandParser? = nil,
        commandSpeechToText: SpeechToText? = nil,
        live: LiveTranscriber? = nil,
        handsFreeLimit: TimeInterval = PushToTalkSession.handsFreeLimit,
        speechReady: @escaping (Language) -> Bool = { _ in true }
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
        self.handsFreeLimit = handsFreeLimit
        self.speechReady = speechReady
    }

    public func keyDown(_ kind: SessionKind = .dictation) {
        if case .recording(var recording) = state {
            // While recording, only the dictation key does anything: it starts the hands-free stop tap.
            if kind == .dictation, recording.handsFree == .on {
                recording.handsFree = .stopTap
                state = .recording(recording)
            }
            return
        }
        guard case .idle = state, kind == .dictation || commands != nil else { return }
        let secondTap = kind == .dictation && tapReleasedAt.map { now() - $0 <= Self.doubleTapWindow } == true
        tapReleasedAt = nil
        let language = language()
        // Recording now would only wait for the model, with nothing on screen saying why.
        guard speechReady(language) else {
            onEvent(.modelLoading(language))
            return
        }
        // Commands are short and parsed whole; only dictation is transcribed while the key is held.
        recorder.onAudio = kind == .dictation && live != nil ? { [weak self] in self?.audioArrived() } : nil
        do {
            try recorder.start()
        } catch {
            onEvent(.failed(.microphone))
            return
        }
        if kind == .dictation { live?.begin(language: language) }
        state = .recording(Recording(pressedAt: now(), app: frontmostApp(), kind: kind, language: language,
                                     handsFree: secondTap ? .secondTap : .off))
        onEvent(.listening(kind))
    }

    /// Another key pressed while a hotkey is down: a key combination, not push-to-talk. It cancels a recording
    /// being held, as before; a hands-free recording carries on, and a stop tap that became a combination
    /// doesn't stop it.
    public func chord() async {
        if case .recording(var recording) = state, [.on, .stopTap].contains(recording.handsFree) {
            recording.handsFree = .on
            state = .recording(recording)
            return
        }
        await cancel()
    }

    /// Stops a recording in progress and throws it away, with anything already transcribed of it; also a
    /// command still being transcribed or understood, and a dictation that hasn't been pasted yet.
    public func cancel() async {
        if case .processing = state {
            guard canStillCancel else { return }
            canStillCancel = false
            if processingCommand {
                commandCancelled = true
            } else {
                dictationCancelled = true
                live?.discard()
            }
            onEvent(.ignored(.cancelled))
            return
        }
        guard case .recording = state else { return }
        state = .processing
        stopHandsFreeTimer()
        _ = await recorder.stop()
        live?.discard()
        state = .idle
        onEvent(.ignored(.cancelled))
    }

    /// New audio while dictating. After the recording ends, finish() takes what's left itself.
    private func audioArrived() {
        guard case .recording(let recording) = state, recording.kind == .dictation else { return }
        live?.listen(recorder.takeAudio())
    }

    public func keyUp() async {
        guard case .recording(var recording) = state else { return }
        switch recording.handsFree {
        case .off, .stopTap:
            await finish()
        case .secondTap where now() - recording.pressedAt < Self.minimumPressDuration:
            // The second of two quick taps: hands-free from here.
            recording.handsFree = .on
            state = .recording(recording)
            onEvent(.handsFree)
            startHandsFreeTimer()
        case .secondTap:
            await finish()  // held after all: an ordinary press
        case .on:
            break  // not a release of ours (the command key's, during hands-free)
        }
    }

    private func startHandsFreeTimer() {
        let limit = handsFreeLimit
        handsFreeTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self else { return }
            // Let go of the timer first: finish() stops it, and this task mustn't cancel itself (cleanup and
            // pasting would then run cancelled).
            handsFreeTimer = nil
            await finish()
        }
    }

    private func stopHandsFreeTimer() {
        handsFreeTimer?.cancel()
        handsFreeTimer = nil
    }

    /// Ends the recording in progress (key released, the hands-free stop tap, or its time limit) and
    /// transcribes and pastes it.
    private func finish() async {
        guard case .recording(let recording) = state else { return }
        let (pressedAt, app, kind, language) = (recording.pressedAt, recording.app, recording.kind, recording.language)
        stopHandsFreeTimer()
        state = .processing
        processingCommand = kind == .command
        commandCancelled = false
        dictationCancelled = false
        canStillCancel = true
        defer {
            state = .idle
            processingCommand = false
            canStillCancel = false
        }

        let clip = await recorder.stop()
        guard !cancelled else { return }  // Esc as the key went up
        let releasedAt = now()
        if kind == .dictation { live?.listen(recorder.takeAudio()) }  // audio that arrived as the key went up
        guard releasedAt - pressedAt >= Self.minimumPressDuration else {
            live?.discard()
            if kind == .dictation, recording.handsFree == .off { tapReleasedAt = releasedAt }
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
            if !cancelled { onEvent(.failed(.transcription)) }
            return
        }
        guard !cancelled else { return }
        if kind == .dictation { canStillCancel = false }
        guard !text.isEmpty else {
            onEvent(.ignored(.emptyTranscript))
            return
        }

        if kind == .command, let commands {
            let intent = await commands.parse(text)
            guard !commandCancelled else { return }
            canStillCancel = false
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
