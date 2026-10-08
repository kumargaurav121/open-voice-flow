import Testing
@testable import Core

@MainActor
struct LanguageRoutedSpeechToTextTests {
    let clip = AudioClip(samples: [0.1, 0.2], sampleRate: 16_000)

    @Test func eachLanguageGoesToItsOwnModel() async throws {
        let english = FakeSpeechToText()
        english.transcript = "from turbo"
        let hinglish = FakeSpeechToText()
        hinglish.transcript = "from oriserve"
        let routed = LanguageRoutedSpeechToText(routes: [.english: english, .hinglish: hinglish])

        #expect(try await routed.transcribe(clip, language: .english) == "from turbo")
        #expect(try await routed.transcribe(clip, language: .hinglish) == "from oriserve")
        #expect(english.requests.count == 1)
        #expect(hinglish.requests.count == 1)
    }

    @Test func passesTheLanguageThrough() async throws {
        let model = FakeSpeechToText()
        let routed = LanguageRoutedSpeechToText(routes: [.english: model, .hinglish: model])

        _ = try await routed.transcribe(clip, language: .hinglish)

        #expect(model.requests.map(\.language) == [.hinglish])
    }

    @Test func aLanguageWithoutAModelIsAnError() async {
        let routed = LanguageRoutedSpeechToText(routes: [.english: FakeSpeechToText()])

        await #expect(throws: LanguageRoutedSpeechToText.NoModel.self) {
            try await routed.transcribe(clip, language: .hinglish)
        }
    }
}
