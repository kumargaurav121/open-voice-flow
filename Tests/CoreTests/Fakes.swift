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

    struct Replacement: Equatable {
        var old: String
        var new: String
    }

    private(set) var replacements: [Replacement] = []
    /// Whether the field still has the text to replace just before the cursor.
    var fieldUnchanged = true

    var onReplace: (() -> Void)?

    func replace(_ old: String, with new: String) async throws -> Bool {
        onReplace?()
        if let error { throw error }
        guard fieldUnchanged else { return false }
        replacements.append(Replacement(old: old, new: new))
        return true
    }
}

/// The field a dictation was pasted into: the paste with `before` and `after` around it, then on each later read
/// the next of `reads`; once they run out, focus has left it.
@MainActor
final class FakePastedField: PastedField {
    var before = ""
    var after = ""
    var reads: [String] = []
    /// What was pasted (the inserter's last text).
    var pasted: () -> String? = { nil }
    /// How many reads after the first show the field before the paste landed (a ⌘V the app hasn't applied yet);
    /// the last of them shows it landed.
    var readsBeforeThePasteLands = 0
    private(set) var followed = 0

    func follow() async -> FieldText? {
        followed += 1
        return shown(landed: readsBeforeThePasteLands == 0)
    }

    func read() async -> FieldText? {
        if readsBeforeThePasteLands > 0 {
            readsBeforeThePasteLands -= 1
            return shown(landed: readsBeforeThePasteLands == 0)
        }
        guard !reads.isEmpty else { return nil }
        let text = reads.removeFirst()
        return FieldText(text: text, cursor: text.utf16.count)
    }

    private func shown(landed: Bool) -> FieldText? {
        guard let pasted = pasted() else { return nil }
        let shown = landed ? pasted : ""
        return FieldText(text: before + shown + after, cursor: (before + shown).utf16.count)
    }
}

@MainActor
final class FakeClock {
    private var current: TimeInterval = 1_000

    func advance(by seconds: TimeInterval) { current += seconds }

    var now: @MainActor () -> TimeInterval { { [unowned self] in current } }
}

struct FakeError: Error, Equatable {}
