import Core
import Foundation
import Testing
@testable import History

@MainActor
struct HistoryStoreTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "ovf-history-\(UUID().uuidString)")
    let clip = AudioClip(samples: Array(repeating: 0.25, count: 16_000), sampleRate: 16_000)

    func transcript(_ text: String, inserted: Bool = true, language: Language = .hinglish, app: String? = nil) -> SessionTranscript {
        SessionTranscript(text: text, language: language, app: app, inserted: inserted, clip: clip)
    }

    @Test func savedTranscriptsComeBackNewestFirstAfterReopening() throws {
        let store = try HistoryStore(folder: folder)
        try store.save(transcript("First", app: "Slack"), at: Date(timeIntervalSince1970: 100), keepAudio: false)
        try store.save(transcript("Second", inserted: false, language: .english), at: Date(timeIntervalSince1970: 200), keepAudio: false)

        let entries = try HistoryStore(folder: folder).entries()

        #expect(entries.map(\.text) == ["Second", "First"])
        #expect(entries[0].inserted == false && entries[0].language == .english && entries[0].app == nil)
        #expect(entries[1].inserted == true && entries[1].language == .hinglish && entries[1].app == "Slack")
        #expect(entries[1].date == Date(timeIntervalSince1970: 100))
    }

    @Test func searchMatchesAnyPartOfTheTextIgnoringCase() throws {
        let store = try HistoryStore(folder: folder)
        try store.save(transcript("Message Gurjeet saying I'm late"), at: .now, keepAudio: false)
        try store.save(transcript("Deploy to Vercel"), at: .now, keepAudio: false)
        try store.save(transcript("100% done_ok"), at: .now, keepAudio: false)

        #expect(try store.entries(matching: "gurj").map(\.text) == ["Message Gurjeet saying I'm late"])
        #expect(try store.entries(matching: "%").map(\.text) == ["100% done_ok"])  // wildcards are literal
        #expect(try store.entries(matching: "e_o").map(\.text) == ["100% done_ok"])
        #expect(try store.entries(matching: "_").map(\.text) == ["100% done_ok"])
        #expect(try store.entries(matching: "nothing like this").isEmpty)
    }

    @Test func audioIsKeptOnlyWhenTurnedOn() throws {
        let store = try HistoryStore(folder: folder)
        let without = try store.save(transcript("No audio"), at: .now, keepAudio: false)
        let with = try store.save(transcript("With audio"), at: .now, keepAudio: true)

        #expect(without.audio == nil)
        let audio = try #require(with.audio)
        let wav = try Data(contentsOf: audio)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav.count == 44 + 16_000 * 2)  // 16-bit mono
    }

    @Test func anEntryIsSavedEvenIfItsRecordingCannotBeWritten() throws {
        let store = try HistoryStore(folder: folder)
        let audioFolder = folder.appending(path: "audio")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: audioFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: audioFolder.path) }

        let entry = try store.save(transcript("Keep the words"), at: .now, keepAudio: true)

        #expect(entry.audio == nil)
        #expect(try store.entries().map(\.audio) == [nil])
        #expect(try FileManager.default.contentsOfDirectory(atPath: audioFolder.path).isEmpty)
    }

    @Test func historyIsLeftOutOfBackups() throws {
        _ = try HistoryStore(folder: folder)

        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func deletingAnEntryDeletesItsAudio() throws {
        let store = try HistoryStore(folder: folder)
        let entry = try store.save(transcript("With audio"), at: .now, keepAudio: true)
        try store.save(transcript("Keep me"), at: .now, keepAudio: false)

        try store.delete(entry)

        #expect(try store.entries().map(\.text) == ["Keep me"])
        #expect(!FileManager.default.fileExists(atPath: entry.audio!.path))
    }

    @Test func clearingDeletesEveryTranscriptAndAllAudio() throws {
        let store = try HistoryStore(folder: folder)
        let entry = try store.save(transcript("One"), at: .now, keepAudio: true)
        try store.save(transcript("Two"), at: .now, keepAudio: false)

        try store.clear()

        #expect(try store.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: entry.audio!.path))
        #expect(try HistoryStore(folder: folder).entries().isEmpty)
    }
}
