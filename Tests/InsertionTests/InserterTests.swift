import Foundation
import Testing
@testable import Insertion

@MainActor
final class FakeField: FocusedField {
    var result: DirectInsertResult = .refused(diagnostic: "fake")
    private(set) var attempts: [String] = []

    func insertAtCursor(_ text: String) async -> DirectInsertResult {
        attempts.append(text)
        return result
    }
}

@MainActor
final class FakePasteKey: PasteKey {
    var error: Error?
    private(set) var presses = 0
    var onPress: () -> Void = {}

    func press() throws {
        if let error { throw error }
        presses += 1
        onPress()
    }
}

struct FakeError: Error {}

@MainActor
struct InserterTests {
    let field = FakeField()
    let pasteboard = FakePasteboard()
    let key = FakePasteKey()
    let previous: [String: Data] = ["public.png": Data([1, 2, 3])]

    /// Restores run when the test says so, standing in for the 0.5 s delay.
    @MainActor
    final class Scheduler {
        var pending: [(Duration, @MainActor () -> Void)] = []
        func runAll() { pending.forEach { $0.1() }; pending = [] }
    }

    func makeInserter(_ scheduler: Scheduler) -> Inserter {
        Inserter(field: field, pasteboard: pasteboard, pasteKey: key, isTrusted: { true },
                 schedule: { delay, work in scheduler.pending.append((delay, work)) })
    }

    @Test func aDirectInsertLeavesTheClipboardAlone() async throws {
        field.result = .attempted(before: FieldState(length: 0, selection: 0..<0),
                                  after: FieldState(length: 5, selection: 5..<5), diagnostic: "")
        pasteboard.replace(with: [previous])
        let countBefore = pasteboard.changeCount

        try await makeInserter(Scheduler()).insert("hello")

        #expect(key.presses == 0)
        #expect(pasteboard.changeCount == countBefore)
    }

    @Test func aRefusedInsertPastesThenRestoresTheClipboardAfterADelay() async throws {
        pasteboard.replace(with: [previous])
        var clipboardAtPaste: [[String: Data]] = []
        key.onPress = { clipboardAtPaste = pasteboard.snapshot() }
        let scheduler = Scheduler()

        try await makeInserter(scheduler).insert("नमस्ते 👋")

        #expect(key.presses == 1)
        #expect(clipboardAtPaste.first?["public.utf8-plain-text"] == Data("नमस्ते 👋".utf8))
        #expect(scheduler.pending.map(\.0) == [Inserter.restoreDelay])
        scheduler.runAll()
        #expect(pasteboard.items == [previous])
    }

    @Test func somethingCopiedBeforeTheRestoreIsKept() async throws {
        pasteboard.replace(with: [previous])
        let scheduler = Scheduler()

        try await makeInserter(scheduler).insert("hello")
        pasteboard.userCopies("my own copy")
        scheduler.runAll()

        #expect(pasteboard.items == [["public.utf8-plain-text": Data("my own copy".utf8)]])
    }

    @Test func aFailedPasteKeystrokeRestoresAtOnceAndReportsTheError() async {
        pasteboard.replace(with: [previous])
        key.error = FakeError()
        let scheduler = Scheduler()

        await #expect(throws: FakeError.self) { try await makeInserter(scheduler).insert("hello") }

        #expect(pasteboard.items == [previous])
        #expect(scheduler.pending.isEmpty)
    }

    @Test func twoQuickDictationsStillGiveBackTheUsersClipboard() async throws {
        pasteboard.replace(with: [previous])
        let scheduler = Scheduler()
        let inserter = makeInserter(scheduler)

        try await inserter.insert("first")
        try await inserter.insert("second")  // before the first restore ran
        scheduler.runAll()

        #expect(pasteboard.items == [previous])
    }

    @Test func aPasswordManagersClipboardIsClearedNotRestored() async throws {
        // Restoring it would republish a secret its manager meant to expire.
        pasteboard.replace(with: [["public.utf8-plain-text": Data("hunter2".utf8), "org.nspasteboard.ConcealedType": Data()]])
        let scheduler = Scheduler()

        try await makeInserter(scheduler).insert("hello")
        scheduler.runAll()

        #expect(pasteboard.items.isEmpty)
    }

    @Test func ourOwnWriteIsMarkedTransientSoClipboardHistoryAppsSkipIt() async throws {
        var clipboardAtPaste: [[String: Data]] = []
        key.onPress = { clipboardAtPaste = pasteboard.snapshot() }

        try await makeInserter(Scheduler()).insert("hello")

        #expect(clipboardAtPaste.first?["org.nspasteboard.TransientType"] != nil)
    }

    @Test func aClipboardThatRefusesTheTextIsAnErrorNotAStalePaste() async {
        pasteboard.refusesWrites = true

        await #expect(throws: InserterError.clipboardUnavailable) { try await makeInserter(Scheduler()).insert("hello") }
        #expect(key.presses == 0)
    }
}
