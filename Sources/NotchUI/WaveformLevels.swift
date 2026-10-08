/// Turns mic loudness into waveform levels (0...1). Rises instantly and falls gradually, so the
/// bars respond the moment you speak but don't flicker between words.
public struct WaveformLevels: Sendable {
    /// Bars never drop below this, so the waveform reads as "listening" even in silence.
    public static let floor: Float = 0.08
    static let silenceDB: Float = -55
    static let loudDB: Float = -10
    /// Fraction of the level kept per update (~30 Hz) once the voice drops.
    static let release: Float = 0.8

    public private(set) var level: Float = floor
    private var recent: [Float] = []
    static let historyLimit = 64

    public init() {}

    public mutating func update(decibels: Float) {
        let normalized = (decibels - Self.silenceDB) / (Self.loudDB - Self.silenceDB)
        let target = Swift.max(Self.floor, Swift.min(1, normalized))
        level = target > level ? target : Swift.max(target, level * Self.release)
        recent.append(level)
        if recent.count > Self.historyLimit { recent.removeFirst(recent.count - Self.historyLimit) }
    }

    /// The last `count` levels, oldest first, padded with the floor: a waveform that scrolls left as you speak.
    public func history(count: Int) -> [Float] {
        let tail = Array(recent.suffix(count))
        return Array(repeating: Self.floor, count: count - tail.count) + tail
    }
}
