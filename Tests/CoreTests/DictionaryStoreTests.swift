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
