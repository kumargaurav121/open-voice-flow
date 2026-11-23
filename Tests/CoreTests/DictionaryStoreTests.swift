import Foundation
import Testing
@testable import Core

@MainActor
struct DictionaryStoreTests {
    let defaults = UserDefaults(suiteName: "ovf-dictionary-\(UUID().uuidString)")!

    @Test func addedTermsAreTrimmedAndKeptAcrossLaunches() {
        let store = DictionaryStore(defaults: defaults)

        #expect(store.add("  Gurjeet ") == true)
        #expect(store.add("Supabase") == true)

        #expect(DictionaryStore(defaults: defaults).terms == ["Gurjeet", "Supabase"])
    }

    @Test func blankAndDuplicateTermsAreRefused() {
        let store = DictionaryStore(defaults: defaults)
        store.add("Gurjeet")

        #expect(store.add("   ") == false)
        #expect(store.add("gurjeet") == false)
        #expect(store.terms == ["Gurjeet"])
    }

    @Test func termsWithoutEnglishLettersAreRefused() {
        // Transcripts are always in English letters, so these could never match.
        let store = DictionaryStore(defaults: defaults)

        #expect(store.add("प्रिया") == false)
        #expect(store.add("😀") == false)
        #expect(store.add("C++") == true)
    }

    @Test func duplicatesSavedEarlierAreDroppedOnLoad() {
        defaults.set(["Gurjeet", "gurjeet", " ", "Supabase"], forKey: DictionaryStore.key)

        #expect(DictionaryStore(defaults: defaults).terms == ["Gurjeet", "Supabase"])
    }

    @Test func termsCanBeEditedAndRemoved() {
        let store = DictionaryStore(defaults: defaults)
        store.add("Gurjit")
        store.add("Supabase")
        store.add("Qwen")

        #expect(store.update("Gurjit", to: "Gurjeet") == true)
        #expect(store.update("Qwen", to: "supabase") == false)  // would duplicate
        store.remove("Supabase")

        #expect(DictionaryStore(defaults: defaults).terms == ["Gurjeet", "Qwen"])
    }

    @Test func startsEmpty() {
        #expect(DictionaryStore(defaults: defaults).terms.isEmpty)
    }
}

/// Learning from corrections (v2 ticket 15): the same one-word fix twice within 7 days suggests the word.
@MainActor
struct DictionaryLearningTests {
    let defaults = UserDefaults(suiteName: "ovf-learning-\(UUID().uuidString)")!
    var today = Date(timeIntervalSince1970: 1_800_000_000)
    /// Ordinary English, as the app's spell check knows it.
    static let english: Set = ["there", "their", "the", "message", "karo"]

    func store() -> DictionaryStore {
        let today = today
        return DictionaryStore(defaults: defaults, now: { today }, isEnglishWord: { Self.english.contains($0) })
    }

    mutating func days(_ count: Double) { today += count * 24 * 60 * 60 }

    @Test mutating func theSameFixTwiceWithinSevenDaysSuggestsTheWord() {
        #expect(store().learn([WordFix(from: "gurujit", to: "Gurjeet")]).isEmpty)
        days(6)
        #expect(store().learn([WordFix(from: "Gurujit", to: "Gurjeet")]) == ["Gurjeet"])

        #expect(store().suggestions == ["Gurjeet"])  // kept across launches
        #expect(store().terms.isEmpty)  // only offered
    }

    @Test mutating func aFixOnceOrEightDaysApartSuggestsNothing() {
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])
        days(8)
        #expect(store().learn([WordFix(from: "gurujit", to: "Gurjeet")]).isEmpty)
        // Another fix of the same word to something else isn't the same fix.
        days(1)
        #expect(store().learn([WordFix(from: "gurujit", to: "Gurjit")]).isEmpty)
        #expect(store().suggestions.isEmpty)
    }

    @Test mutating func anAcceptedSuggestionBecomesADictionaryWord() {
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])

        store().accept("Gurjeet")

        #expect(store().terms == ["Gurjeet"])
        #expect(store().suggestions.isEmpty)
    }

    @Test mutating func aDismissedSuggestionIsNeverOfferedAgain() {
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])

        store().dismiss("Gurjeet")
        days(1)
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])

        #expect(store().suggestions.isEmpty)
        #expect(store().terms.isEmpty)
    }

    /// The user's choice (2026-11-23): a fix to ordinary English wouldn't help the dictionary.
    @Test mutating func onlyNamesAndTermsAreSuggested() {
        let fixes = [WordFix(from: "there", to: "their"), WordFix(from: "the", to: "The"),
                     WordFix(from: "supa", to: "Supabase"), WordFix(from: "प्रिया", to: "प्रियं")]
        let first = store()
        first.add("Supabase")  // already a dictionary word
        first.learn(fixes)

        #expect(store().learn(fixes).isEmpty)
    }

    /// Settings → Privacy's switch turned off: the fixes kept so far go.
    @Test mutating func forgottenFixesDontCount() {
        store().learn([WordFix(from: "gurujit", to: "Gurjeet")])

        store().forgetFixes()

        #expect(store().learn([WordFix(from: "gurujit", to: "Gurjeet")]).isEmpty)
    }

    @Test mutating func severalFixesInOneDictationEachCount() {
        store().learn([WordFix(from: "gurujit", to: "Gurjeet"), WordFix(from: "supabass", to: "Supabase")])

        #expect(store().learn([WordFix(from: "gurujit", to: "Gurjeet"), WordFix(from: "supabass", to: "Supabase")])
                == ["Gurjeet", "Supabase"])
    }
}
