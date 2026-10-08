import Foundation
import Core

/// Cuts leading and trailing silence from a clip. The silence threshold adapts to the
/// clip's own noise floor, so quiet rooms and noisy rooms both trim correctly.
public struct SilenceTrimmer: Sendable {
    /// Audio kept on each side of the detected speech, in seconds.
    public static let margin: TimeInterval = 0.15
    static let frameDuration: TimeInterval = 0.02
    /// Frames this far above the noise floor count as speech.
    static let speechAboveFloorDB: Float = 10
    /// Never treat anything this quiet as speech.
    static let absoluteFloorDB: Float = -55
    /// Level reported for digital silence (no signal at all).
    public static let silentDecibels: Float = -120

    public init() {}

    public func trim(_ clip: AudioClip) -> AudioClip {
        let frameLength = max(1, Int(Self.frameDuration * clip.sampleRate))
        let levels = stride(from: 0, to: clip.samples.count, by: frameLength).map { start in
            Self.decibels(clip.samples[start..<min(start + frameLength, clip.samples.count)])
        }
        guard let loudest = levels.max() else { return clip }

        let noiseFloor = levels.sorted()[levels.count / 10]
        // Cap below the loudest frame so a clip with no pauses (floor == speech) keeps its speech.
        let threshold = max(Self.absoluteFloorDB, min(noiseFloor, loudest - 2 * Self.speechAboveFloorDB) + Self.speechAboveFloorDB)
        guard let first = levels.firstIndex(where: { $0 > threshold }),
              let last = levels.lastIndex(where: { $0 > threshold })
        else { return AudioClip(samples: [], sampleRate: clip.sampleRate) }

        let marginSamples = Int(Self.margin * clip.sampleRate)
        let start = max(0, first * frameLength - marginSamples)
        let end = min(clip.samples.count, (last + 1) * frameLength + marginSamples)
        return AudioClip(samples: Array(clip.samples[start..<end]), sampleRate: clip.sampleRate)
    }

    static func decibels(_ frame: ArraySlice<Float>) -> Float {
        let meanSquare = frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)
        return meanSquare > 0 ? 10 * log10(meanSquare) : silentDecibels
    }
}
