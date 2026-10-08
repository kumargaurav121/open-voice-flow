import Foundation
@testable import Core

@MainActor
final class FakeRecorder: AudioRecorder {
    var clip = AudioClip(samples: Array(repeating: 0.5, count: 16_000), sampleRate: 16_000)
    var startError: Error?
    private(set) var isRecording = false
    private(set) var startCount = 0

    func start() throws {
        if let startError { throw startError }
        isRecording = true
        startCount += 1
    }

    var onStop: (() -> Void)?

    func stop() async -> AudioClip {
        onStop?()
        isRecording = false
        return clip
    }
}

@MainActor
final class FakeSpeechToText: SpeechToText {
    var transcript = ""
    var error: Error?
    private(set) var requests: [(clip: AudioClip, language: Language)] = []
    var onTranscribe: (() -> Void)?

    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        requests.append((clip, language))
        onTranscribe?()
        if let error { throw error }
        return transcript
    }
}

@MainActor
final class FakeInserter: TextInserter {
    private(set) var inserted: [String] = []
    var onInsert: (() -> Void)?
    var error: Error?

    func insert(_ text: String) async throws {
        onInsert?()
        if let error { throw error }
        inserted.append(text)
    }
}

@MainActor
final class FakeClock {
    private var current: TimeInterval = 1_000

    func advance(by seconds: TimeInterval) { current += seconds }

    var now: @MainActor () -> TimeInterval { { [unowned self] in current } }
}

struct FakeError: Error, Equatable {}
