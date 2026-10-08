import Foundation

/// Mono PCM audio captured for one session.
public struct AudioClip: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Whisper's input rate; recorders and loaders produce clips at this rate.
    public static let speechSampleRate = 16_000.0

    public var duration: TimeInterval { Double(samples.count) / sampleRate }
    public var isEmpty: Bool { samples.isEmpty }
}

/// What the user speaks. Hinglish covers English, Hindi and the two mixed; English-only trades
/// Hindi support for better English accuracy.
public enum Language: String, CaseIterable, Sendable {
    case hinglish, english

    public var displayName: String {
        switch self {
        case .hinglish: "Hinglish"
        case .english: "English"
        }
    }
}

@MainActor
public protocol AudioRecorder: AnyObject {
    func start() throws
    /// Stops capture and returns the recorded clip with leading/trailing silence trimmed.
    func stop() async -> AudioClip
}

@MainActor
public protocol SpeechToText: AnyObject {
    func transcribe(_ clip: AudioClip, language: Language) async throws -> String
}

@MainActor
public protocol TextInserter: AnyObject {
    func insert(_ text: String) async throws
}
