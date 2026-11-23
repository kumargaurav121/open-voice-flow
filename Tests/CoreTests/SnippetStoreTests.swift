import Foundation
import Testing
@testable import Core

@MainActor
struct SnippetStoreTests {
    let defaults = UserDefaults(suiteName: "ovf-snippets-\(UUID().uuidString)")!

    /// Each snippet's cue and text, which is what the user sees.
    func saved(_ store: SnippetStore) -> [[String]] {
        store.snippets.map { [$0.cue, $0.text] }
    }

    @Test func addedSnippetsAreTrimmedAndKeptAcrossLaunches() {
        let store = SnippetStore(defaults: defaults)

        #expect(store.add(cue: "  my address ", text: "Kumar Gaurav\n42, MG Road\n") == true)
        #expect(store.add(cue: "my email", text: "kumar@example.com") == true)

        let reloaded = SnippetStore(defaults: defaults)
        #expect(saved(reloaded) == [["my address", "Kumar Gaurav\n42, MG Road"], ["my email", "kumar@example.com"]])
        #expect(reloaded.snippets.map(\.id) == store.snippets.map(\.id))
    }

    @Test func blankCuesBlankTextsAndCuesAlreadyTakenAreRefused() {
        let store = SnippetStore(defaults: defaults)
        store.add(cue: "my email", text: "kumar@example.com")

        #expect(store.add(cue: "   ", text: "Hello") == false)
        #expect(store.add(cue: "?!", text: "Hello") == false)  // nothing to say
        #expect(store.add(cue: "sign off", text: " \n ") == false)
        #expect(store.add(cue: "My Email!", text: "other@example.com") == false)  // said the same way
        #expect(saved(store) == [["my email", "kumar@example.com"]])
    }

    @Test func cuesNoTranscriptCouldMatchAreRefused() {
        // Transcripts are always in English letters, and fillers never reach the match.
        let store = SnippetStore(defaults: defaults)

        #expect(store.add(cue: "मेरा पता", text: "42, MG Road") == false)
        #expect(store.add(cue: "um", text: "Hello") == false)
        #expect(store.add(cue: "mera pata", text: "42, MG Road") == true)
    }

    @Test func aSnippetCanBeEditedButNotOntoAnotherCue() {
        let store = SnippetStore(defaults: defaults)
        store.add(cue: "my email", text: "kumar@example.com")
        store.add(cue: "work email", text: "kumar@work.example")
        let first = store.snippets[0].id, second = store.snippets[1].id

        #expect(store.update(first, cue: "home email", text: "kumar@home.example") == true)
        #expect(store.update(second, cue: "Home email.", text: "x") == false)
        #expect(store.update(second, cue: "work email", text: "  ") == false)

        #expect(saved(SnippetStore(defaults: defaults))
                == [["home email", "kumar@home.example"], ["work email", "kumar@work.example"]])
    }

    @Test func removedSnippetsStayRemoved() {
        let store = SnippetStore(defaults: defaults)
        store.add(cue: "my email", text: "kumar@example.com")

        store.remove(store.snippets[0].id)

        #expect(SnippetStore(defaults: defaults).snippets.isEmpty)
    }

    @Test func unreadableSavedSnippetsAreDroppedOnLoad() {
        defaults.set(Data("not snippets".utf8), forKey: SnippetStore.key)

        #expect(SnippetStore(defaults: defaults).snippets.isEmpty)
    }

    @Test func oneUnreadableOrDuplicateSnippetDoesntLoseTheRest() {
        let id = UUID().uuidString
        defaults.set(Data("""
            [{"id": "\(id)", "cue": "my email", "text": "kumar@example.com"},
             {"cue": "no id", "text": "x"},
             {"id": "\(UUID().uuidString)", "cue": "My Email!", "text": "other@example.com"},
             {"id": "\(UUID().uuidString)", "cue": "my address", "text": "42, MG Road"}]
            """.utf8), forKey: SnippetStore.key)

        let store = SnippetStore(defaults: defaults)

        #expect(saved(store) == [["my email", "kumar@example.com"], ["my address", "42, MG Road"]])
        #expect(store.snippets.first?.id.uuidString == id)
    }
}
