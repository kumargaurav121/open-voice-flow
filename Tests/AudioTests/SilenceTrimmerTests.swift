import Foundation
import Testing
import Core
@testable import Audio

struct SilenceTrimmerTests {
    static let rate = 16_000.0

    /// A 200 Hz tone at the given level in dBFS.
    func tone(seconds: Double, db: Float) -> [Float] {
        let amplitude = pow(10, db / 20) * sqrt(2) // sine RMS = peak / √2
        return (0..<Int(seconds * Self.rate)).map { amplitude * sin(2 * .pi * 200 * Float($0) / Float(Self.rate)) }
    }

    func silence(seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * Self.rate)) }

    /// Deterministic hiss at roughly the given level in dBFS.
    func noise(seconds: Double, db: Float) -> [Float] {
        var generator = SplitMix(seed: 42)
        let amplitude = pow(10, db / 20) * sqrt(3) // uniform RMS = peak / √3
        return (0..<Int(seconds * Self.rate)).map { _ in amplitude * generator.nextSigned() }
    }

    func clip(_ parts: [Float]...) -> AudioClip { AudioClip(samples: parts.flatMap { $0 }, sampleRate: Self.rate) }

    @Test func removesLeadingAndTrailingSilenceKeepingAShortMargin() {
        let input = clip(silence(seconds: 1), tone(seconds: 2, db: -20), silence(seconds: 1))

        let trimmed = SilenceTrimmer().trim(input)

        #expect(abs(trimmed.duration - (2 + 2 * SilenceTrimmer.margin)) < 0.05)
    }

    @Test func pausesInsideSpeechAreKept() {
        let input = clip(tone(seconds: 1, db: -20), silence(seconds: 1), tone(seconds: 1, db: -20))

        let trimmed = SilenceTrimmer().trim(input)

        #expect(abs(trimmed.duration - 3) < 0.05)
    }

    @Test func allSilenceBecomesEmpty() {
        #expect(SilenceTrimmer().trim(clip(silence(seconds: 2))).isEmpty)
    }

    @Test func steadyBackgroundNoiseCountsAsSilence() {
        let input = clip(noise(seconds: 1, db: -45), tone(seconds: 2, db: -30), noise(seconds: 1, db: -45))

        let trimmed = SilenceTrimmer().trim(input)

        #expect(abs(trimmed.duration - (2 + 2 * SilenceTrimmer.margin)) < 0.05)
    }

    @Test func quietSpeechInAQuietRoomIsKept() {
        let input = clip(silence(seconds: 1), tone(seconds: 2, db: -40), silence(seconds: 1))

        let trimmed = SilenceTrimmer().trim(input)

        #expect(abs(trimmed.duration - (2 + 2 * SilenceTrimmer.margin)) < 0.05)
    }

    @Test func clipThatIsAllSpeechIsUntouched() {
        let input = clip(tone(seconds: 2, db: -25))

        #expect(SilenceTrimmer().trim(input) == input)
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func nextSigned() -> Float { Float(next() >> 40) / Float(1 << 24) * 2 - 1 }
}
