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

    // MARK: Numbers (v2 ticket 07): 10 and up as digits, one to nine as words except in times, decimals,
    // percentages and dates. Parakeet writes most numbers as words; the examples are from the eval clips.

    @Test func numbersFromTenUpAreWrittenAsDigits() {
        #expect(clean("Our API latency went from four hundred milliseconds to ninety milliseconds.")
                == "Our API latency went from 400 milliseconds to 90 milliseconds.")
        #expect(clean("I'll be late by fifteen minutes.") == "I'll be late by 15 minutes.")
        #expect(clean("We cut after about twenty-five seconds, or twenty five at most.")
                == "We cut after about 25 seconds, or 25 at most.")
        #expect(clean("Client ko eleven baje dikhana hai.") == "Client ko 11 baje dikhana hai.")
    }

    @Test func largeNumbersAreReadWhole() {
        #expect(clean("It costs one thousand two hundred rupees") == "It costs 1200 rupees")
        #expect(clean("Fifteen hundred users and a hundred and twenty teams") == "1500 users and 120 teams")
        #expect(clean("Twenty five thousand downloads, two million views") == "25,000 downloads, 2 million views")
    }

    @Test func numbersUnderTenStayWords() {
        let text = "For tomorrow's standup, I have three updates. One, the login bug is fixed. Let's meet at five."
        #expect(clean(text) == text)
        #expect(clean("Every time it finds one, it waits a second.") == "Every time it finds one, it waits a second.")
    }

    @Test func numberWordsInARowThatMakeNoSingleNumberStayWords() {
        #expect(clean("My code is one two three four.") == "My code is one two three four.")
        #expect(clean("Seventy eighty people came, twenty-twenty vision") == "Seventy eighty people came, twenty-twenty vision")
        // A rough count, not a time or a year (found in review).
        #expect(clean("Give me five ten minutes, or ten fifteen minutes at most") == "Give me five ten minutes, or ten fifteen minutes at most")
        #expect(clean("Twenty thirty people came, nineteen twenty people stayed") == "Twenty thirty people came, nineteen twenty people stayed")
    }

    @Test func aDurationInSecondsIsNotAnOrdinal() {
        #expect(clean("Make a thirty-second ad, with a twenty second delay") == "Make a thirty-second ad, with a twenty second delay")
        #expect(clean("Meet on the twenty-second of December") == "Meet on the 22nd of December")
    }

    @Test func atOnePointIsNotADecimal() {
        #expect(clean("At one point two engineers left.") == "At one point two engineers left.")
        #expect(clean("Prices went up by one point five percent") == "Prices went up by 1.5%")
    }

    @Test func digitsAModelWroteAreLeftAlone() {
        let text = "We'll set up the app on 10 laptops, from the 1st of December, at 11:30."
        #expect(clean(text) == text)
    }

    @Test func timesAreClockTimes() {
        #expect(clean("Hey, can we push the standup to eleven thirty tomorrow?")
                == "Hey, can we push the standup to 11:30 tomorrow?")
        #expect(clean("Let's do it around three PM, or ten oh five.") == "Let's do it around 3 PM, or 10:05.")
        #expect(clean("Wake me at five o'clock") == "Wake me at 5 o'clock")
        // Parakeet sometimes writes the hour as a word and the minutes as digits (eval clip 57).
        #expect(clean("Flight leaves at six.15 in the morning") == "Flight leaves at 6:15 in the morning")
    }

    @Test func hourAndMinutesWithoutATimeCueStayWords() {
        // Found in review: only "at", "by", "until"... before, or "tomorrow", "pm"... after, make them a time.
        let text = "Room two twelve, three twenty dollar bills, it costs one fifty and I'm five eleven"
        #expect(clean(text) == text)
        #expect(clean("Book it from nine thirty until eleven fifteen") == "Book it from 9:30 until 11:15")
        #expect(clean("Eleven forty five pm works") == "11:45 pm works")
    }

    @Test func decimalsAndPercentagesAreDigits() {
        #expect(clean("The median is about one and a half seconds.") == "The median is about 1.5 seconds.")
        #expect(clean("Version two point five is five percent faster") == "Version 2.5 is 5% faster")
    }

    @Test func datesAndOrdinalsFromTenthAreDigits() {
        #expect(clean("Beginning on Monday, the first of December.") == "Beginning on Monday, the 1st of December.")
        #expect(clean("By December twenty-first, our tenth release") == "By December 21st, our 10th release")
        #expect(clean("First, the plan. Second, the date.") == "First, the plan. Second, the date.")
    }

    @Test func spokenYearsAreYears() {
        #expect(clean("Back in nineteen ninety nine and again in twenty twenty-six") == "Back in 1999 and again in 2026")
    }

    @Test func aNumberStartingAHyphenatedWordKeepsTheRest() {
        #expect(clean("A twenty-five-year-old ran a two-week pilot") == "A 25-year-old ran a two-week pilot")
    }
}
