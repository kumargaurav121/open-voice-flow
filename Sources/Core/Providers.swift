import Foundation

/// Mono PCM audio captured for one session.
public struct AudioClip: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: TimeInterval { Double(samples.count) / sampleRate }
    public var isEmpty: Bool { samples.isEmpty }
}

/// Spoken language hint passed to speech-to-text.
public enum Language: String, CaseIterable, Sendable {
    case auto, english, hindi
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
