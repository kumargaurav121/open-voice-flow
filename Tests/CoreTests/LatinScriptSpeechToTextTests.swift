import Testing
@testable import Core

@MainActor
struct LatinScriptSpeechToTextTests {
    let clip = AudioClip(samples: [0.1], sampleRate: 16_000)

    func transcribe(_ text: String) async throws -> String {
        let model = FakeSpeechToText()
        model.transcript = text
        return try await LatinScriptSpeechToText(wrapping: model).transcribe(clip, language: .hinglish)
    }

    func isLatinOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.isASCII }
    }

    @Test func englishPassesThroughUntouched() async throws {
        #expect(try await transcribe("I hope you're doing fine. Meeting at 11:30!") == "I hope you're doing fine. Meeting at 11:30!")
    }

    @Test func urduComesOutInEnglishLetters() async throws {
        // From a real session: turbo's auto-detect picked Urdu for Hinglish speech.
        let text = try await transcribe("I hope you're doing fine. ادھر بھائی ہو رہے کر آپ")

        #expect(isLatinOnly(text))
        #expect(text.hasPrefix("I hope you're doing fine."))
    }

    @Test func devanagariComesOutInEnglishLetters() async throws {
        let text = try await transcribe("मैं आज थोड़ा देर से आऊंगा, traffic बहुत है")

        #expect(isLatinOnly(text))
        #expect(text.contains("traffic"))
        #expect(text.lowercased().hasPrefix("m"))
    }

    @Test func indianAndArabicDigitsBecomeWesternDigits() async throws {
        #expect(try await transcribe("११ बजे") .hasPrefix("11"))
        #expect(try await transcribe("meeting ٣ pm") == "meeting 3 pm")
    }

    @Test func passesTheLanguageThrough() async throws {
        let model = FakeSpeechToText()
        _ = try await LatinScriptSpeechToText(wrapping: model).transcribe(clip, language: .english)

        #expect(model.requests.map(\.language) == [.english])
    }

    @Test func devanagariReadsLikeEverydayRomanHindi() async throws {
        // Silent final "a" dropped, the nasal dot written as n, no ICU apostrophes.
        let text = try await transcribe("मैं आज देर से आऊंगा बहुत")
        #expect(text == "main aj der se aunga bahut")
    }

    @Test func englishWordsInsideHindiAreLeftAlone() async throws {
        #expect(try await transcribe("गुरजीत को message करो, it's urgent") .hasSuffix("message karo, it's urgent"))
    }

    @Test(arguments: [
        "Let’s grab a café at 5…",
        "He said “hello” — then left.",
        "Budget is ₹500, not €500.",
    ])
    func latinScriptOutputIsNeverRewritten(text: String) async throws {
        // Only Devanagari and Arabic script are transliterated; English punctuation and accents stay.
        #expect(try await transcribe(text) == text)
    }

    @Test func mixedScriptWordsKeepTheirEnglishPart() async throws {
        #expect(try await transcribe("राम's laptop") == "ram's laptop")
    }

    @Test func theHindiFullStopBecomesAFullStop() async throws {
        #expect(try await transcribe("देर हो गई।") == "der ho gai.")
        #expect(try await transcribe("बहुत देर।") == "bahut der.")
    }

    @Test func lineBreaksArePreserved() async throws {
        let text = try await transcribe("पहला\nदूसरा")

        #expect(text.contains("\n"))
        #expect(isLatinOnly(text))
    }

    @Test func aDecomposedNuktaStillDropsTheSilentA() async throws {
        // ज + ़ (U+093C) written as two code points, as some models emit it.
        #expect(try await transcribe("तेज\u{093C}") == "tez")
    }
}
