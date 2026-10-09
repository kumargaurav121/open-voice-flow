import Testing
@testable import Core

@MainActor
struct DictionarySpeechToTextTests {
    let clip = AudioClip(samples: [0.1], sampleRate: 16_000)
    let model = FakeSpeechToText()

    @Test func spellsDictionaryTermsTheUsersWay() async throws {
        model.transcript = "Gurjit ko message karo"
        let dictionary = DictionarySpeechToText(wrapping: model, terms: { ["Gurjeet"] })

        #expect(try await dictionary.transcribe(clip, language: .hinglish) == "Gurjeet ko message karo")
    }

    @Test func usesTheDictionaryAsItIsWhenTranscribing() async throws {
        model.transcript = "check the super base logs"
        var terms: [String] = []
        let dictionary = DictionarySpeechToText(wrapping: model, terms: { terms })
        #expect(try await dictionary.transcribe(clip, language: .english) == "check the super base logs")

        terms = ["Supabase"]

        #expect(try await dictionary.transcribe(clip, language: .english) == "check the Supabase logs")
    }

    @Test func anEmptyDictionaryPassesTheTranscriptThroughUntouched() async throws {
        model.transcript = "  Message gurujit,  saying I'll be late!! "
        let dictionary = DictionarySpeechToText(wrapping: model, terms: { [] })

        #expect(try await dictionary.transcribe(clip, language: .hinglish) == "  Message gurujit,  saying I'll be late!! ")
    }

    @Test func aiCleanupSeesTheCorrectedNames() async throws {
        // As the app wires it: the dictionary runs before cleanup, so the AI (and its guard) see "Gurjeet".
        model.transcript = "um message gurujit saying I'm late"
        let ai = FakeCleaner()
        ai.reply = { _ in "Message Gurjeet saying I'm late." }
        let pipeline = CleanupSpeechToText(
            wrapping: DictionarySpeechToText(wrapping: model, terms: { ["Gurjeet"] }),
            selectedAI: { ai }, isCodeContext: { false }, timeout: .seconds(1), log: { _ in }
        )

        let text = try await pipeline.transcribe(clip, language: .english)

        #expect(ai.inputs.first?.contains("Gurjeet") == true)
        #expect(text == "Message Gurjeet saying I'm late.")
    }
}
