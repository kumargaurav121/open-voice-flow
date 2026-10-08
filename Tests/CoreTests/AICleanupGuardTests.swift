import Testing
@testable import Core

struct AICleanupGuardTests {
    func accepts(_ original: String, _ rewritten: String) -> Bool {
        AICleanupGuard.accepts(original: original, rewritten: rewritten)
    }

    @Test func acceptsAFillerTrimAndPunctuationFix() {
        // Ambiguous fillers are only deletable at punctuation boundaries, as transcripts punctuate them.
        #expect(accepts("so basically, i think we should, like, ship it today",
                        "I think we should ship it today."))
    }

    @Test func acceptsHinglishCleanedInPlace() {
        #expect(accepts("matlab bhai kal ka demo ready hai na, client ko dikhana hai",
                        "Bhai, kal ka demo ready hai, client ko dikhana hai."))
    }

    @Test func rejectsAnAnswerInsteadOfACleanup() {
        #expect(!accepts("can you send me the deck by tomorrow",
                         "Sure! Here is a polite version: Could you please share the presentation deck with me by tomorrow?"))
    }

    @Test func rejectsATranslation() {
        #expect(!accepts("bhai kal ka demo ready hai client ko dikhana hai",
                         "Brother, tomorrow's demo is ready and we need to show it to the client."))
    }

    @Test func rejectsHindiScriptOutput() {
        #expect(!accepts("kal milte hain", "कल मिलते हैं।"))
    }

    @Test func rejectsEmptyOrNearlyEmptyOutput() {
        #expect(!accepts("please review the pull request before end of day", ""))
        #expect(!accepts("please review the pull request before end of day", "Review."))
    }

    @Test func rejectsDroppingWordsThatCarryMeaning() {
        // Real Qwen3-1.7B outputs: "mujhe lagta hai ki" (I think that) and "Okay thanks" were dropped.
        #expect(!accepts("Yaar matlab mujhe lagta hai ki budget thoda thoda kam hai, like seriously",
                         "Yaar, budget thoda thoda kam hai, like seriously."))
        #expect(!accepts("Okay thanks, see you tomorrow", "See you tomorrow."))
    }

    @Test func acceptsRemovingFillersAndRepeatsOnly() {
        #expect(accepts("So the release is basically blocked on QA, you know, and I mean we can't we can't ship",
                        "The release is blocked on QA, and we can't ship."))
    }

    @Test func acceptsPunctuationAndCasingChangesAlone() {
        #expect(accepts("the meeting with gurjeet is on thursday", "The meeting with Gurjeet is on Thursday."))
    }

    @Test func acceptsNumbersWrittenAsDigitsAndOkSpelledShort() {
        // A real Thorough-mode rewrite the guard wrongly rejected.
        #expect(accepts("Okay I want three items, first is milk, second is tea, third is coffee",
                        "Ok, I want 3 items, first is milk, second is tea, third is coffee."))
    }

    @Test func stillRejectsAChangedNumber() {
        #expect(!accepts("Book the room for four people", "Book the room for 5 people."))
    }

    @Test func rejectsDroppingOneCopyOfAWordThatWasNotARepeat() {
        #expect(!accepts("I do not want it, not now", "I do want it, not now."))
    }

    @Test func rejectsDroppingAmbiguousFillersWhereTheyCarryMeaning() {
        #expect(!accepts("I like it a lot", "I it a lot."))
        #expect(!accepts("I love it so much", "I love it much."))
        #expect(!accepts("I mean it", "It."))
    }

    @Test func acceptsAmbiguousFillersRemovedAtSentenceOrCommaBoundaries() {
        #expect(accepts("So the build is green, like, seriously", "The build is green, seriously."))
        #expect(accepts("Okay, you know, we ship today", "Okay, we ship today."))
    }

    @Test func curlyApostrophesAreTheSameWord() {
        #expect(accepts("I don't know", "I don’t know."))
    }
}
