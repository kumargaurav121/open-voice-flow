import Testing
@testable import Core

struct RecipientMatchTests {
    @Test func aSpokenFirstNameFindsTheFullName() {
        #expect(RecipientMatch.resolve("Gurjeet", among: ["Gurjeet Singh", "Rohan Mehta"]) == .found("Gurjeet Singh"))
    }

    @Test func spellingAsHeardStillMatches() {
        #expect(RecipientMatch.resolve("Gurjit", among: ["Gurjeet Singh"]) == .found("Gurjeet Singh"))
        #expect(RecipientMatch.resolve("priya", among: ["Priya Sharma"]) == .found("Priya Sharma"))
    }

    @Test func someoneElseIsNotAMatch() {
        #expect(RecipientMatch.resolve("Gurjeet", among: ["Rohan Mehta", "Garima Jain"]) == .notFound)
        #expect(RecipientMatch.resolve("Gurjeet", among: []) == .notFound)
    }

    @Test func twoPeopleWhoBothMatchIsAmbiguous() {
        #expect(RecipientMatch.resolve("Priya", among: ["Priya Sharma", "Priya Nair", "Rohan Mehta"])
                == .ambiguous(["Priya Sharma", "Priya Nair"]))
    }

    @Test func aFullNameSettlesIt() {
        #expect(RecipientMatch.resolve("Priya Nair", among: ["Priya Sharma", "Priya Nair"]) == .found("Priya Nair"))
    }

    @Test func slackDecorationsAreIgnored() {
        // Quick-switcher rows carry extras: display names, "(you)", status, pronouns.
        #expect(RecipientMatch.resolve("Rohan", among: ["Rohan Mehta (he/him)", "#rohan-team"]) == .found("Rohan Mehta (he/him)"))
    }

    @Test func aGroupConversationIsNotAPerson() {
        #expect(RecipientMatch.resolve("Gurjeet", among: ["Gurjeet Singh, Harpreet Kaur"]) == .notFound)
    }

    @Test func namesWithoutEnglishLettersNeverMatchByAccident() {
        // Their sound keys are empty, which would otherwise be a perfect "match".
        #expect(RecipientMatch.resolve("गुरजीत", among: ["हरप्रीत"]) == .notFound)
        #expect(RecipientMatch.resolve("Gurjeet", among: ["हरप्रीत"]) == .notFound)
    }
}
