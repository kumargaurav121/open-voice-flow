import Foundation
import Testing
@testable import Insertion

@MainActor
final class FakeField: FocusedField {
    var result: DirectInsertResult = .refused(diagnostic: "fake")
    private(set) var attempts: [String] = []
    /// The field's text and selection (UTF-16); a nil selection can't be read.
    var text = ""
    var selection: Range<Int>? = 0..<0
    /// Where a requested selection lands: some web fields ignore it (nil) or put it elsewhere.
    var selects: (Range<Int>) -> Range<Int>? = { $0 }
    private(set) var selections: [Range<Int>] = []

    func insertAtCursor(_ text: String) async -> DirectInsertResult {
        attempts.append(text)
        return result
    }

    func reading() async -> FieldReading {
        FieldReading(diagnostic: "role AXTextArea",
                     state: selection.map { FieldState(length: text.utf16.count, selection: $0) })
    }

    func text(in range: Range<Int>) async -> String? {
        let units = Array(text.utf16)
        guard range.upperBound <= units.count else { return nil }
        return String(decoding: units[range], as: UTF16.self)
    }

    func select(_ range: Range<Int>) async -> Range<Int>? {
        selections.append(range)
        if let landed = selects(range) { selection = landed }
        return selection
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

    // MARK: Replacing the last dictation (Undo Formatting, v2 ticket 12)

    /// The field after a dictation: `pasted` just before the cursor.
    func fieldEnding(with pasted: String, after earlier: String = "Shopping list\n") {
        field.text = earlier + pasted
        field.selection = field.text.utf16.count..<field.text.utf16.count
    }

    @Test func replaceSelectsTheTextJustBeforeTheCursorAndInsertsOverIt() async throws {
        fieldEnding(with: "1. Milk\n2. Bread")
        field.result = .attempted(before: FieldState(length: 30, selection: 14..<30),
                                  after: FieldState(length: 37, selection: 37..<37), diagnostic: "")

        let replaced = try await makeInserter(Scheduler()).replace("1. Milk\n2. Bread", with: "First milk, second bread")

        #expect(replaced)
        #expect(field.selections == [14..<30])
        #expect(field.attempts == ["First milk, second bread"])
        #expect(key.presses == 0)
    }

    @Test func whereTheDirectInsertDoesNotLandTheSelectionIsPastedOver() async throws {
        fieldEnding(with: "Hi Rohan,\nThanks")
        pasteboard.replace(with: [previous])
        var clipboardAtPaste: [[String: Data]] = []
        key.onPress = { clipboardAtPaste = pasteboard.snapshot() }
        let scheduler = Scheduler()

        #expect(try await makeInserter(scheduler).replace("Hi Rohan,\nThanks", with: "Hi Rohan comma new line thanks"))

        #expect(key.presses == 1)
        #expect(clipboardAtPaste.first?["public.utf8-plain-text"] == Data("Hi Rohan comma new line thanks".utf8))
        scheduler.runAll()
        #expect(pasteboard.items == [previous])
    }

    enum Change: CaseIterable { case typedAfterIt, cursorMoved, textSelectedAfterIt, unreadable, deleted }

    @Test(arguments: Change.allCases)
    func textThatIsNoLongerJustBeforeTheCursorIsLeftAlone(_ change: Change) async throws {
        let pasted = "Hi Rohan,\nThanks"
        switch change {
        case .typedAfterIt: fieldEnding(with: pasted + "!")
        case .cursorMoved:
            fieldEnding(with: pasted)
            field.selection = 0..<0
        case .textSelectedAfterIt:
            fieldEnding(with: pasted + " see you")
            field.selection = (field.text.utf16.count - 8)..<field.text.utf16.count
        case .unreadable:
            fieldEnding(with: pasted)
            field.selection = nil
        case .deleted: fieldEnding(with: "Thanks", after: "")
        }

        #expect(try await !makeInserter(Scheduler()).replace(pasted, with: "Hi Rohan comma new line thanks"))

        #expect(field.selections.isEmpty)
        #expect(field.attempts.isEmpty)
        #expect(key.presses == 0)
    }

    @Test func aRefusalSaysWhereTheTextDiffersWithoutItsWords() async throws {
        // A web field reporting a non-breaking space where a space was pasted.
        field.text = "Hi Rohan,\u{00A0}thanks"
        field.selection = 16..<16
        let inserter = makeInserter(Scheduler())
        var notes: [String] = []
        inserter.onReplaceRefused = { notes.append($0) }

        _ = try await inserter.replace("Hi Rohan, thanks", with: "Hi Rohan comma thanks")

        #expect(notes == ["role AXTextArea, the text before the cursor differs at 9 of 16, U+00A0 for U+0020 (field length 16, cursor 16)"])
    }

    @Test func aFieldThatIgnoresTheSelectionGetsNothing() async throws {
        // Pasting without the selection would leave both texts in the field.
        fieldEnding(with: "Hi Rohan,\nThanks")
        field.selects = { _ in nil }

        #expect(try await !makeInserter(Scheduler()).replace("Hi Rohan,\nThanks", with: "Hi Rohan comma new line thanks"))

        #expect(field.attempts.isEmpty)
        #expect(key.presses == 0)
    }

    @Test func aSelectionThatLandsElsewhereIsUndoneSoNothingIsTypedOverIt() async throws {
        fieldEnding(with: "Hi Rohan,\nThanks")
        let end = field.text.utf16.count
        field.selects = { $0.isEmpty ? $0 : ($0.lowerBound + 1)..<$0.upperBound }

        #expect(try await !makeInserter(Scheduler()).replace("Hi Rohan,\nThanks", with: "Hi Rohan comma new line thanks"))

        #expect(field.attempts.isEmpty)
        #expect(field.selection == end..<end)
    }

    @Test func replaceWithoutAccessibilityIsAnError() async {
        fieldEnding(with: "Hi Rohan,\nThanks")
        let inserter = Inserter(field: field, pasteboard: pasteboard, pasteKey: key, isTrusted: { false },
                                schedule: { _, _ in })

        await #expect(throws: InserterError.accessibilityNotGranted) {
            try await inserter.replace("Hi Rohan,\nThanks", with: "Hi Rohan comma new line thanks")
        }
    }

    @Test func aClipboardThatRefusesTheTextIsAnErrorNotAStalePaste() async {
        pasteboard.refusesWrites = true

        await #expect(throws: InserterError.clipboardUnavailable) { try await makeInserter(Scheduler()).insert("hello") }
        #expect(key.presses == 0)
    }
}
