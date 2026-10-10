import Foundation
import Testing
@testable import Cloud

@MainActor
@Suite(.serialized) struct APIKeysTests {
    // A throwaway Keychain service, removed at the end of each test.
    let keys = APIKeys(service: "dev.openvoiceflow.tests.\(UUID().uuidString)")
    let secret = "dg_test_\(UUID().uuidString)"

    @Test func aSavedKeyComesBackFromTheKeychain() throws {
        defer { try? keys.remove(.deepgram) }
        try keys.save(secret, for: .deepgram)

        #expect(try keys.key(for: .deepgram) == secret)
        #expect(try keys.key(for: .openAI) == nil)
    }

    @Test func savingAgainReplacesTheKeyAndRemovingDeletesIt() throws {
        defer { try? keys.remove(.groq) }
        try keys.save("first", for: .groq)
        try keys.save("  second \n", for: .groq)
        #expect(try keys.key(for: .groq) == "second")

        try keys.remove(.groq)
        #expect(try keys.key(for: .groq) == nil)
    }

    @Test func aBlankKeyRemovesTheSavedOne() throws {
        defer { try? keys.remove(.openAI) }
        try keys.save("sk-something", for: .openAI)
        try keys.save("   ", for: .openAI)

        #expect(try keys.key(for: .openAI) == nil)
    }

    @Test func knowsWhichKeysAreSavedWithoutAskingTheKeychainAgain() throws {
        defer { try? keys.remove(.groq) }
        #expect(!keys.hasKey(for: .groq))

        try keys.save("gsk-1", for: .groq)
        #expect(keys.hasKey(for: .groq))
        // Another instance (e.g. after relaunch) finds it in the Keychain.
        #expect(APIKeys(service: keys.service).hasKey(for: .groq))

        try keys.remove(.groq)
        #expect(!keys.hasKey(for: .groq))
    }

    @Test func keysNeverLandInPreferences() throws {
        defer { try? keys.remove(.deepgram) }
        try keys.save(secret, for: .deepgram)

        let preferences = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }
        #expect(!preferences.contains { $0.contains(secret) })
    }
}
