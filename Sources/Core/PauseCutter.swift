import Foundation

/// Cuts live audio at the speaker's pauses, so finished stretches can be transcribed while they're still
/// talking and only the last stretch is left when the key is released. Pauses are judged against the
/// recording's own noise floor, the way `SilenceTrimmer` finds speech, so quiet and noisy rooms both work.
public struct PauseCutter: Sendable {
    /// A finished stretch of the recording, and how it was separated from the one before.
    public struct Part: Equatable, Sendable {
        public var audio: AudioClip
        /// The silence before it, in seconds: nil for the first part, 0 when the cut before it wasn't at a pause.
        public var pauseBefore: TimeInterval?
    }

    /// Silence this long, after speech, ends a part.
    public static let pause: TimeInterval = 0.5
    /// Without a pause, a part is cut at its quietest moment once it reaches this length (Whisper reads 30 s
    /// at a time).
    public static let longestPart: TimeInterval = 25
    /// Parts are never shorter than this, counted from their first speech: given a word or two, a model loses
    /// the context around them.
    public static let shortestPart: TimeInterval = 2
    /// A forced cut looks for the quietest moment in this last stretch of the part.
    static let forcedCutSearch: TimeInterval = 10
    /// The quietest moment is the quietest stretch of this many frames (100 ms).
    static let quietestFrames = 5

    private let sampleRate: Double
    private let frameLength: Int
    /// Audio of the part in progress, from its start.
    private var pending: [Float] = []
    /// Loudness of each complete frame of `pending`, in dBFS.
    private var levels: [Float] = []
    /// Loudness of every frame heard so far, in 1 dB bins from -120 to 0, for the noise floor.
    private var histogram = [Int](repeating: 0, count: 121)
    private var framesHeard = 0
    private var loudest = SilenceTrimmer.silentDecibels
    /// How the part in progress was separated from the previous one: nil before the first cut, true after a
    /// cut at a pause.
    private var cutAtPause: Bool?

    public init(sampleRate: Double = AudioClip.speechSampleRate) {
        self.sampleRate = sampleRate
        frameLength = max(1, Int(SilenceTrimmer.frameDuration * sampleRate))
    }

    /// Adds newly recorded audio; returns the parts it finished, in order.
    public mutating func add(_ samples: [Float]) -> [Part] {
        pending += samples
        var parts: [Part] = []
        while (levels.count + 1) * frameLength <= pending.count {
            let start = levels.count * frameLength
            let level = SilenceTrimmer.decibels(pending[start..<start + frameLength])
            levels.append(level)
            hear(level)
            if let (cut, atPause) = cutPoint() {
                parts.append(Part(audio: AudioClip(samples: Array(pending[..<cut]), sampleRate: sampleRate),
                                  pauseBefore: pauseBeforePending))
                pending.removeFirst(cut)
                levels.removeFirst(cut / frameLength)
                cutAtPause = atPause
            }
        }
        return parts
    }

    /// The audio after the last cut: what's left to transcribe at release, or nothing when all of it is
    /// silence (as when the speaker paused before letting go). Quiet trailing words still count: once the
    /// room has been heard, anything 10 dB above its noise does. The cutter then starts afresh.
    public mutating func finish() -> Part {
        defer { self = PauseCutter(sampleRate: sampleRate) }
        let threshold = threshold
        let heard = levels.contains { $0 > threshold } || levels.isEmpty
        return Part(audio: AudioClip(samples: heard ? pending : [], sampleRate: sampleRate), pauseBefore: pauseBeforePending)
    }

    /// The silence before the part in progress: the part of the pause before the cut, plus the silence at
    /// the start of this part up to its first speech.
    private var pauseBeforePending: TimeInterval? {
        guard let cutAtPause else { return nil }
        guard cutAtPause else { return 0 }
        let threshold = threshold
        let leading = levels.firstIndex { $0 > threshold } ?? levels.count
        return Self.pause + Double(leading) * SilenceTrimmer.frameDuration
    }

    // MARK: Loudness

    private mutating func hear(_ level: Float) {
        histogram[Int(min(max(level, -120), 0) + 120)] += 1
        framesHeard += 1
        loudest = max(loudest, level)
    }

    /// The 10th-percentile loudness of the whole recording so far.
    private var noiseFloor: Float { percentile(10) }

    /// Speech has been heard once something stood out from the quietest of the recording; until then (a
    /// silent or noisy room), nothing is cut.
    private var heardSpeech: Bool { loudest - percentile(1) >= SilenceTrimmer.speechAboveFloorDB }

    private func percentile(_ percent: Int) -> Float {
        var remaining = framesHeard * percent / 100
        for (bin, count) in histogram.enumerated() {
            remaining -= count
            if remaining < 0 { return Float(bin) - 120 }
        }
        return loudest
    }

    /// Frames at or below this are silence: within 10 dB of the room's noise and at least 20 dB below the
    /// loudest speech. Stricter than `SilenceTrimmer` (which only trims the ends), so a speaker trailing off
    /// mid-sentence isn't a pause, even before any real silence has shown the room's noise level.
    private var threshold: Float {
        max(SilenceTrimmer.absoluteFloorDB, min(noiseFloor + SilenceTrimmer.speechAboveFloorDB,
                                                loudest - 2 * SilenceTrimmer.speechAboveFloorDB))
    }

    // MARK: Cutting

    private func frames(_ seconds: TimeInterval) -> Int { Int((seconds / SilenceTrimmer.frameDuration).rounded()) }

    /// Where the part should end, in samples (on a frame boundary), and whether that's at a pause, if it
    /// should end now. A part always holds speech.
    private func cutPoint() -> (sample: Int, atPause: Bool)? {
        guard heardSpeech else { return nil }
        let threshold = threshold
        guard let firstSpeech = levels.firstIndex(where: { $0 > threshold }),
              levels.count - firstSpeech >= frames(Self.shortestPart)
        else { return nil }
        let pauseFrames = frames(Self.pause)
        // A pause: the latest frames are silent, after the part's speech.
        if firstSpeech < levels.count - pauseFrames, levels.suffix(pauseFrames).allSatisfy({ $0 <= threshold }) {
            return (levels.count * frameLength, true)
        }
        // No pause for too long since the part's first speech: cut at the quietest moment of the last stretch,
        // leaving at least `shortestPart` of speech in the part.
        guard levels.count - firstSpeech >= frames(Self.longestPart) else { return nil }
        let window = Self.quietestFrames
        let earliest = max(levels.count - frames(Self.forcedCutSearch), firstSpeech + frames(Self.shortestPart))
        guard earliest <= levels.count - window else { return nil }
        let candidates = earliest...(levels.count - window)
        guard let quietest = candidates.min(by: { levels[$0..<$0 + window].reduce(0, +) < levels[$1..<$1 + window].reduce(0, +) })
        else { return nil }
        return ((quietest + window / 2) * frameLength, false)
    }
}
