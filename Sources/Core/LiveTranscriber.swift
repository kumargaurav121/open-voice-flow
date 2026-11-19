import Foundation

/// Transcribes a dictation while it's being spoken. The session hands it the live audio; it cuts it at the
/// speaker's pauses (`PauseCutter`), trims each finished part and transcribes it in the background, so at
/// release only the tail is left. The parts' text is joined into one, without the full stop Whisper puts at
/// the end of every part when the cut came mid-sentence.
///
/// Everything the pipeline transcribes goes through here, commands included, one clip at a time and in
/// order: the speech engine must never run two transcriptions at once, not even while a discarded part is
/// still finishing.
@MainActor
public final class LiveTranscriber: SpeechToText {
    /// A cut at a shorter pause than this (or without one) is taken to be mid-sentence.
    public static let sentencePause: TimeInterval = 1.0

    /// How a dictation was cut: parts transcribed while speaking, and seconds of speech left at release.
    public struct Cut: Equatable, Sendable {
        public var parts: Int
        public var tail: TimeInterval
    }

    /// A part's transcription, and the silence before it (see `PauseCutter.Part`).
    private struct Spoken {
        var text: Task<String, Error>
        var pauseBefore: TimeInterval?
    }

    /// One dictation's transcriptions: once one fails, the rest are skipped instead of keeping the engine busy.
    private final class Batch {
        var failed = false
    }

    private let model: SpeechToText
    private let sentencePause: TimeInterval
    private let partLengths: (Language) -> PauseCutter.Lengths
    private let trimmer = SilenceTrimmer()
    private var cutter = PauseCutter()
    /// The last transcription queued; each new one waits for it.
    private var queue: Task<Void, Never>?
    /// The dictation in progress: its language and its finished parts, in the order they were spoken.
    private var dictation: (language: Language, spoken: [Spoken], batch: Batch)?
    /// The transcriptions being joined at release, so a late Esc can still stop them.
    private var joining: [Task<String, Error>] = []

    /// How the last transcription was cut, for the session's log.
    public private(set) var lastCut = Cut(parts: 0, tail: 0)

    /// - Parameter partLengths: how long a dictation's parts get in each language, read when it starts: the
    ///   model the language uses decides (see `PauseCutter.Lengths`).
    public init(wrapping model: SpeechToText, sentencePause: TimeInterval = LiveTranscriber.sentencePause,
                partLengths: @escaping (Language) -> PauseCutter.Lengths = { _ in .short }) {
        self.model = model
        self.sentencePause = sentencePause
        self.partLengths = partLengths
    }

    /// Starts a dictation (dropping anything left of the last one).
    public func begin(language: Language) {
        discard()
        cutter = PauseCutter(lengths: partLengths(language))
        dictation = (language, [], Batch())
    }

    /// Live audio of the dictation in progress: finished parts go off to be transcribed.
    public func listen(_ samples: [Float]) {
        guard let (language, _, batch) = dictation else { return }
        for part in cutter.add(samples) {
            let speech = trimmer.trim(part.audio)
            guard !speech.isEmpty else { continue }
            dictation?.spoken.append(Spoken(text: enqueue(speech, language: language, batch: batch),
                                            pauseBefore: part.pauseBefore))
        }
    }

    /// Drops the dictation in progress, including transcriptions queued for it. One already running may run
    /// to the end, but its text is never used.
    public func discard() {
        dictation?.spoken.forEach { $0.text.cancel() }
        joining.forEach { $0.cancel() }
        dictation = nil
        joining = []
    }

    /// For a dictation that was cut while it was spoken: its parts' text and the tail's, joined (`clip` is
    /// then only the session's record of it). Otherwise, with nothing cut or for a command: a plain
    /// transcription of `clip`, still queued behind any work in progress.
    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        let live = dictation
        dictation = nil
        var spoken: [Spoken]
        if let live, !live.spoken.isEmpty {
            let tail = cutter.finish()
            let speech = trimmer.trim(tail.audio)
            spoken = live.spoken
            if !speech.isEmpty {
                spoken.append(Spoken(text: enqueue(speech, language: live.language, batch: live.batch),
                                     pauseBefore: tail.pauseBefore))
            }
            lastCut = Cut(parts: live.spoken.count, tail: speech.duration)
        } else {
            _ = cutter.finish()
            spoken = [Spoken(text: enqueue(clip, language: language, batch: Batch()), pauseBefore: nil)]
            lastCut = Cut(parts: 0, tail: clip.duration)
        }
        joining = spoken.map(\.text)
        defer { joining = [] }
        var texts: [(text: String, pauseBefore: TimeInterval?)] = []
        for part in spoken {
            texts.append((try await part.text.value, part.pauseBefore))
        }
        return Self.join(texts, sentencePause: sentencePause)
    }

    private func enqueue(_ clip: AudioClip, language: Language, batch: Batch) -> Task<String, Error> {
        let previous = queue, model = model
        let task = Task { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            guard !batch.failed else { throw CancellationError() }
            do {
                return try await model.transcribe(clip, language: language)
            } catch {
                batch.failed = true
                throw error
            }
        }
        queue = Task { @MainActor in _ = try? await task.value }
        return task
    }

    // MARK: Joining

    /// Joins the parts' text with spaces. Where the pause before a part was shorter than `sentencePause` (or
    /// there was none), the cut was mid-sentence: the full stop ending the text before it goes, and its first
    /// word loses the capital the model gave it, unless it's "I", an acronym, or capitalised elsewhere in the
    /// dictation too (a name).
    static func join(_ texts: [(text: String, pauseBefore: TimeInterval?)], sentencePause: TimeInterval) -> String {
        let capitalisedInside = Set(texts.flatMap { $0.text.split(separator: " ").dropFirst().map(bare) }
            .filter { $0.first?.isUppercase == true })
        var joined = ""
        for (raw, pause) in texts {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if joined.isEmpty {
                joined = text
                continue
            }
            if let pause, pause < sentencePause {
                if joined.hasSuffix("."), !joined.hasSuffix("..") { joined.removeLast() }
                text = lowercasingFirstWord(text, keeping: capitalisedInside)
            }
            joined += " " + text
        }
        return joined
    }

    private static func bare(_ word: Substring) -> String {
        String(word).trimmingCharacters(in: .punctuationCharacters)
    }

    private static func lowercasingFirstWord(_ text: String, keeping names: Set<String>) -> String {
        let first = bare(text.prefix { !$0.isWhitespace })
        let isAcronym = first.count > 1 && first.allSatisfy { !$0.isLetter || $0.isUppercase }
        guard let initial = text.first, initial.isUppercase,
              first != "I", !first.hasPrefix("I'"), !isAcronym, !names.contains(first)
        else { return text }
        return initial.lowercased() + text.dropFirst()
    }
}
