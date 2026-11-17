import Core
import Foundation

/// Plays an eval clip into the app's own push-to-talk session as if it were spoken while holding the key,
/// so the eval cuts and transcribes it exactly as the app would.
@MainActor
final class Dictation {
    /// The microphone hands over audio about this often (4096 frames at 48 kHz, converted to 16 kHz).
    static let chunk = 1_365

    private let recorder = FileRecorder()
    private let inserter = CapturingInserter()
    private let session: PushToTalkSession
    /// Seconds of audio played so far: the session's clock, so each clip is "held" for exactly its length.
    private let played = Played()
    private var timings: SessionTimings?

    init(transcriber: SpeechToText, live: LiveTranscriber, language: Language) {
        session = PushToTalkSession(recorder: recorder, speechToText: transcriber, inserter: inserter,
                                    now: { [played] in played.seconds }, language: { language }, live: live)
        session.onEvent = { [weak self] in if case .inserted(let t) = $0 { self?.timings = t } }
    }

    /// Dictates `clip` (untrimmed, as recorded). With `realtime`, the audio arrives at speaking pace, so parts
    /// are transcribed while it plays, as in the app; `seconds` is then the time from release to text.
    /// Returns "" when the session pastes nothing.
    func run(_ clip: AudioClip, realtime: Bool) async throws -> (text: String, seconds: Double, timings: SessionTimings?) {
        inserter.last = nil
        timings = nil
        session.keyDown()
        for start in stride(from: 0, to: clip.samples.count, by: Self.chunk) {
            recorder.deliver(Array(clip.samples[start..<min(start + Self.chunk, clip.samples.count)]))
            if realtime { try await Task.sleep(for: .seconds(Double(Self.chunk) / clip.sampleRate)) }
        }
        played.seconds += clip.duration
        let elapsed = await ContinuousClock().measure { await session.keyUp() }
        return (inserter.last ?? "", elapsed / .seconds(1), timings)
    }
}

@MainActor
private final class Played {
    var seconds: TimeInterval = 0
}

/// A recorder whose "microphone" is an audio file, handed over in chunks.
@MainActor
private final class FileRecorder: AudioRecorder {
    var onAudio: (() -> Void)?
    private let trimmer = SilenceTrimmer()
    private var recorded: [Float] = []
    private var waiting: [Float] = []

    func start() throws {
        recorded = []
        waiting = []
    }

    func deliver(_ samples: [Float]) {
        recorded += samples
        waiting += samples
        onAudio?()
    }

    func stop() async -> AudioClip {
        trimmer.trim(AudioClip(samples: recorded, sampleRate: AudioClip.speechSampleRate))
    }

    func takeAudio() -> [Float] {
        defer { waiting = [] }
        return waiting
    }
}

@MainActor
private final class CapturingInserter: TextInserter {
    var last: String?

    func insert(_ text: String) async throws {
        last = text
    }
}
