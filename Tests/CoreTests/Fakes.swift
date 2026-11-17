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
        waiting = []
    }

    var onAudio: (() -> Void)?
    private var waiting: [Float] = []

    /// Audio arriving while recording: queued, then announced, as the microphone does.
    func deliver(_ samples: [Float]) {
        waiting += samples
        onAudio?()
    }

    /// Audio recorded but not announced yet (it arrives just as the key goes up).
    func record(_ samples: [Float]) {
        waiting += samples
    }

    func takeAudio() -> [Float] {
        defer { waiting = [] }
        return waiting
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
    /// Replies to successive requests, in order; `transcript` once they run out.
    var replies: [String] = []
    var error: Error?
    /// Requests (by position, from 0) that fail.
    var failing: Set<Int> = []
    private(set) var requests: [(clip: AudioClip, language: Language)] = []
    var onTranscribe: (() -> Void)?

    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        requests.append((clip, language))
        onTranscribe?()
        if let error { throw error }
        if failing.contains(requests.count - 1) { throw FakeError() }
        return replies.isEmpty ? transcript : replies.removeFirst()
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
