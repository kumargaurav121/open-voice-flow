import Testing
@testable import Core

struct RulesCleanupTests {
    func clean(_ text: String) -> String { RulesCleanup.clean(text) }

    @Test func dropsHesitationSounds() {
        #expect(clean("Um, I think we should, uh, ship it.") == "I think we should ship it.")
        #expect(clean("So umm the build is hmm green") == "So the build is green")
    }

    @Test func keepsWordsThatAreOnlySometimesFillers() {
        // Meaning-bearing in many sentences; only the AI pass may judge them.
        #expect(clean("I like it, so ship it") == "I like it, so ship it")
        #expect(clean("Iska matlab hai ki basically done hai") == "Iska matlab hai ki basically done hai")
    }

    @Test func collapsesStutteredEnglishFunctionWords() {
        #expect(clean("Push the the fix to to main") == "Push the fix to main")
    }

    @Test func keepsHindiReduplication() {
        #expect(clean("Jaldi jaldi karo, bahut bahut shukriya") == "Jaldi jaldi karo, bahut bahut shukriya")
    }

    @Test func capitalisesSentenceStartsAndTheWordI() {
        #expect(clean("um, i will call you. then i leave") == "I will call you. Then I leave")
    }

    @Test func tidiesSpacingAroundPunctuation() {
        #expect(clean("  hello ,  world  !  ") == "Hello, world!")
    }

    @Test func leavesCleanTextExactlyAsItIs() {
        let text = "Bhai, kal ka demo ready hai. Client ko 11 baje dikhana hai."
        #expect(clean(text) == text)
    }

    @Test func emptyStaysEmpty() {
        #expect(clean("  um  ") == "")
    }

    @Test func doesNotCapitaliseAfterDecimalsOrAbbreviations() {
        #expect(clean("version 3.5 is out, e.g. this one") == "Version 3.5 is out, e.g. this one")
    }

    @Test func aFillerAfterAQuestionLeavesTheQuestionMarkAlone() {
        #expect(clean("Really? um.") == "Really?")
    }
}
