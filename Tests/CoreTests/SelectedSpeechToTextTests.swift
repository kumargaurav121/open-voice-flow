import Testing
@testable import Core

@MainActor
struct SelectedSpeechToTextTests {
    let clip = AudioClip(samples: [0.1], sampleRate: 16_000)
    let local = FakeSpeechToText()
    let cloud = FakeSpeechToText()

    init() {
        local.transcript = "from this Mac"
        cloud.transcript = "from the cloud"
    }

    @Test func theCloudIsNeverContactedUnlessChosen() async throws {
        let speech = SelectedSpeechToText(local: local, cloud: cloud, provider: { .local }, log: { _ in })

        #expect(try await speech.transcribe(clip, language: .hinglish) == "from this Mac")
        #expect(cloud.requests.isEmpty)
    }

    @Test func aChangedChoiceAppliesToTheNextDictation() async throws {
        var provider = SpeechProvider.local
        let speech = SelectedSpeechToText(local: local, cloud: cloud, provider: { provider }, log: { _ in })
        _ = try await speech.transcribe(clip, language: .english)

        provider = .deepgram

        #expect(try await speech.transcribe(clip, language: .english) == "from the cloud")
        #expect(local.requests.count == 1)
    }

    @Test func aFailingCloudFallsBackToThisMacAndSaysWhy() async throws {
        cloud.error = CloudDown()
        var logged: [String] = []
        let speech = SelectedSpeechToText(local: local, cloud: cloud, provider: { .deepgram }, log: { logged.append($0) })

        #expect(try await speech.transcribe(clip, language: .hinglish) == "from this Mac")
        #expect(logged.count == 1)
        #expect(logged.first?.contains("used this Mac") == true)
    }
}

extension SelectedSpeechToTextTests {
    @Test func aSlowCloudIsCutOffAndThisMacTranscribesInstead() async throws {
        let slow = SlowSpeechToText(delay: .seconds(5))
        var logged: [String] = []
        let speech = SelectedSpeechToText(local: local, cloud: slow, provider: { .deepgram }, cloudTimeout: .milliseconds(50),
                                          log: { logged.append($0) })

        #expect(try await speech.transcribe(clip, language: .english) == "from this Mac")
        #expect(logged.first?.contains("timed out") == true)
    }

    @Test func aCancelledDictationIsNotTranscribedOnThisMacInstead() async throws {
        let slow = SlowSpeechToText(delay: .seconds(5))
        let speech = SelectedSpeechToText(local: local, cloud: slow, provider: { .deepgram }, log: { _ in })

        let task = Task { try await speech.transcribe(clip, language: .english) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(local.requests.isEmpty)
    }

    @Test func theLogNeverIncludesTheProvidersMessage() async throws {
        cloud.error = LeakyError()
        var logged: [String] = []
        let speech = SelectedSpeechToText(local: local, cloud: cloud, provider: { .deepgram }, log: { logged.append($0) })

        _ = try await speech.transcribe(clip, language: .english)

        #expect(!logged.contains { $0.contains("secret") })
    }
}

private struct CloudDown: Error {}
private struct LeakyError: Error, CustomStringConvertible { var description: String { "token secret-123 rejected" } }

@MainActor
private final class SlowSpeechToText: SpeechToText {
    let delay: Duration
    init(delay: Duration) { self.delay = delay }
    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        try await Task.sleep(for: delay)
        return "from the cloud"
    }
}
