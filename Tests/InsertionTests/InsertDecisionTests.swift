import Testing
@testable import Insertion

struct InsertDecisionTests {
    let empty = FieldState(length: 0, selection: 0..<0)

    @Test func aFieldThatGrewWasInsertedInto() {
        let result = DirectInsertResult.attempted(before: FieldState(length: 10, selection: 10..<10),
                                                  after: FieldState(length: 21, selection: 21..<21), diagnostic: "")

        #expect(InsertDecision.verdict(for: result) == .inserted)
    }

    @Test func replacingASelectionOfTheSameLengthStillCountsAsInserted() {
        // Select "hello", dictate "world": the length stays 11, but the cursor moves past the new word.
        let result = DirectInsertResult.attempted(before: FieldState(length: 11, selection: 0..<5),
                                                  after: FieldState(length: 11, selection: 5..<5), diagnostic: "")

        #expect(InsertDecision.verdict(for: result) == .inserted)
    }

    @Test func aFieldThatDidNotChangeAtAllNeedsAPaste() {
        // Electron apps and browsers often report success and do nothing.
        let state = FieldState(length: 1, selection: 1..<1)

        #expect(InsertDecision.verdict(for: .attempted(before: state, after: state, diagnostic: "")) == .fallBackToPaste)
    }

    @Test func aFieldWhoseStateCannotBeReadNeedsAPaste() {
        #expect(InsertDecision.verdict(for: .attempted(before: nil, after: nil, diagnostic: "")) == .fallBackToPaste)
    }

    @Test func noFocusedFieldOrARefusalNeedsAPaste() {
        #expect(InsertDecision.verdict(for: .refused(diagnostic: "no focused element")) == .fallBackToPaste)
    }
}
