import Foundation
import Testing
@testable import Core

/// Live audio goes in, finished parts come out: where the cutter cuts.
struct PauseCutterTests {
    enum Sound {
        /// A voice: a 220 Hz tone at about -14 dBFS.
        case speech(TimeInterval)
        /// The same voice, quieter (about -27 dBFS): not a pause.
        case quietSpeech(TimeInterval)
        /// Nothing but the room: about -57 dBFS of hum.
        case pause(TimeInterval)
        /// A pause in a noisy room: about -37 dBFS.
        case noisyPause(TimeInterval)
    }

    static let rate = AudioClip.speechSampleRate

    static func audio(_ sounds: [Sound]) -> [Float] {
        sounds.flatMap { sound -> [Float] in
            let (seconds, amplitude): (TimeInterval, Float) = switch sound {
            case .speech(let s): (s, 0.3)
            case .quietSpeech(let s): (s, 0.065)
            case .pause(let s): (s, 0.002)
            case .noisyPause(let s): (s, 0.02)
            }
            return (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * 220 * Double($0) / rate)) }
        }
    }

    /// Feeds the audio in chunks the size the microphone delivers (~85 ms), like a live recording.
    static func cuts(_ sounds: [Sound], chunk: Int = 1_365) -> (parts: [PauseCutter.Part], tail: PauseCutter.Part, total: Int) {
        let samples = audio(sounds)
        var cutter = PauseCutter()
        var parts: [PauseCutter.Part] = []
        for start in stride(from: 0, to: samples.count, by: chunk) {
            parts += cutter.add(Array(samples[start..<min(start + chunk, samples.count)]))
        }
        return (parts, cutter.finish(), samples.count)
    }

    static func cut(_ sounds: [Sound], chunk: Int = 1_365) -> (parts: [AudioClip], tail: AudioClip, total: Int) {
        let (parts, tail, total) = cuts(sounds, chunk: chunk)
        return (parts.map(\.audio), tail.audio, total)
    }

    @Test func halfASecondOfSilenceAfterSpeechEndsAPart() {
        let (parts, tail, total) = Self.cut([.speech(3), .pause(0.6), .speech(2)])

        #expect(parts.count == 1)
        #expect(parts.first.map { $0.duration > 3.4 && $0.duration < 3.6 } == true)  // ends inside the pause
        #expect(parts.map(\.samples.count).reduce(0, +) + tail.samples.count == total)  // nothing lost
    }

    @Test func shorterPausesDontCut() {
        let (parts, tail, total) = Self.cut([.speech(3), .pause(0.3), .speech(3)])

        #expect(parts.isEmpty)
        #expect(tail.samples.count == total)
    }

    @Test func noPartIsShorterThanTwoSeconds() {
        #expect(Self.cut([.speech(1), .pause(0.6), .speech(3)]).parts.isEmpty)
    }

    @Test func quieterSpeechIsNotAPause() {
        #expect(Self.cut([.speech(3), .quietSpeech(1), .speech(3)]).parts.isEmpty)
    }

    @Test func pausesInANoisyRoomStillCut() {
        let (parts, _, _) = Self.cut([.noisyPause(1), .speech(3), .noisyPause(0.6), .speech(2)])

        #expect(parts.count == 1)
        #expect(parts.first.map { $0.duration > 4.4 && $0.duration < 4.6 } == true)
    }

    @Test func withoutAPauseItCutsAtTheQuietestMomentBefore25Seconds() {
        let (parts, tail, total) = Self.cut([.speech(21), .quietSpeech(0.3), .speech(9)])

        #expect(parts.count == 1)
        #expect(parts.first.map { $0.duration > 21 && $0.duration < 21.3 } == true)
        #expect(parts.map(\.samples.count).reduce(0, +) + tail.samples.count == total)
    }

    @Test func silenceBeforeSpeakingIsNotAPartOfItsOwn() {
        let (parts, _, _) = Self.cut([.pause(3), .speech(3), .pause(0.6), .speech(2)])

        #expect(parts.count == 1)
        #expect(parts.first.map { $0.duration > 6.4 && $0.duration < 6.6 } == true)
    }

    @Test func chunkSizeDoesNotChangeWhereItCuts() {
        let sounds: [Sound] = [.speech(3), .pause(0.6), .speech(4), .pause(1), .speech(2)]
        let expected = Self.cut(sounds).parts.map(\.samples.count)

        #expect(expected.count == 2)
        #expect(Self.cut(sounds, chunk: 160).parts.map(\.samples.count) == expected)
        #expect(Self.cut(sounds, chunk: 1_000_000).parts.map(\.samples.count) == expected)
    }

    @Test func finishingStartsTheNextRecordingAfresh() {
        var cutter = PauseCutter()
        _ = cutter.add(Self.audio([.speech(3), .pause(0.6), .speech(1)]))
        _ = cutter.finish()

        #expect(cutter.add(Self.audio([.speech(1)])).isEmpty)
        #expect(cutter.finish().audio.samples.count == Self.audio([.speech(1)]).count)
    }

    @Test func aWordAfterALongPauseIsNotAPartOfItsOwn() {
        // The 2 s minimum counts from the first speech, not from the silence before it.
        #expect(Self.cut([.speech(3), .pause(2), .speech(0.4), .pause(0.6)]).parts.count == 1)
    }

    @Test func eachPartKnowsThePauseBeforeIt() {
        let (parts, tail, _) = Self.cuts([.speech(3), .pause(0.7), .speech(3), .pause(1.2), .speech(2)])

        #expect(parts.count == 2)
        #expect(parts[0].pauseBefore == nil)
        #expect(parts[1].pauseBefore.map { abs($0 - 0.7) < 0.05 } == true)
        #expect(tail.pauseBefore.map { abs($0 - 1.2) < 0.05 } == true)
    }

    @Test func aCutWithoutAPauseLeavesNoPauseBeforeTheNextPart() {
        let (_, tail, _) = Self.cuts([.speech(21), .quietSpeech(0.3), .speech(9)])

        #expect(tail.pauseBefore == 0)
    }

    @Test func aNoisyRoomWithNobodySpeakingIsNeverCut() {
        #expect(Self.cut([.noisyPause(30)]).parts.isEmpty)
    }

    @Test func roomNoiseAfterSpeechIsNotSentOffOnItsOwn() {
        // 30 s of nothing but the room: no forced cut without speech in the part.
        #expect(Self.cut([.speech(3), .noisyPause(30), .speech(2)]).parts.count == 1)
    }

    @Test func silenceAfterTheLastCutIsNoTail() {
        let (parts, tail, _) = Self.cut([.speech(3), .pause(1.5)])

        #expect(parts.count == 1)
        #expect(tail.isEmpty)
    }

    @Test func quietWordsAfterTheLastCutAreStillATail() {
        let (_, tail, _) = Self.cut([.speech(3), .pause(0.8), .quietSpeech(0.5), .pause(0.3)])

        #expect(tail.duration > 1)
    }
}
