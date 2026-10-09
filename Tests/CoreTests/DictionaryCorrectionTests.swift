import Foundation
import Testing
@testable import Core

struct DictionaryCorrectionTests {
    let terms = ["Gurjeet", "Priya", "Rohan", "Supabase", "WhisperKit", "Qwen", "Vercel", "Next.js"]

    /// Real English words the stand-in spell checker knows (the app uses macOS's).
    static let english: Set<String> = ["vessel", "korean", "cron", "can", "queue", "version", "super", "base"]

    func correct(_ text: String, terms: [String]? = nil) -> String {
        DictionaryCorrection.correct(text, terms: terms ?? self.terms, isEnglishWord: { Self.english.contains($0.lowercased()) })
    }

    @Test func fixesHinglishSpellingsOfAName() {
        // What the Hinglish model wrote for "Gurjeet" on the eval set.
        #expect(correct("Message gurujit saying I will be late") == "Message Gurjeet saying I will be late")
        #expect(correct("Gurjit ko message karo") == "Gurjeet ko message karo")
        #expect(correct("The meeting with gurujood is on Thursday") == "The meeting with Gurjeet is on Thursday")
    }

    @Test func restoresTheDictionarySpellingOfAnExactSoundMatch() {
        #expect(correct("Send it to priya, rohan and gurujit.") == "Send it to Priya, Rohan and Gurjeet.")
        #expect(correct("Deploy the next.JS app") == "Deploy the Next.js app")
    }

    @Test func joinsATermThatWasHeardAsTwoWords() {
        #expect(correct("check the super base logs") == "check the Supabase logs")
        #expect(correct("We are using whisper kit and MLX") == "We are using WhisperKit and MLX")
    }

    @Test func keepsThePunctuationAroundAFixedWord() {
        #expect(correct("Ask gurujit, then Rohan.") == "Ask Gurjeet, then Rohan.")
        #expect(correct("Is it on super base?") == "Is it on Supabase?")
    }

    @Test func leavesOrdinaryWordsAlone() {
        let sentences = [
            "Can you queue them for the green team?",           // short words: Qwen needs an exact sound
            "Main super busy hoon, guru ji se baat karunga.",   // close to Supabase / Gurjeet, but not enough
            "The new version is ready, ship it.",               // version ≠ Vercel: different last sound
            "Next week we review the whisper network.",         // "next" alone isn't Next.js
            "Garage door is open and the girl is singing.",
        ]
        for sentence in sentences {
            #expect(correct(sentence) == sentence)
        }
    }

    @Test func shortTermsNeedTheSameSound() {
        // Short words are everywhere; one vowel apart is a different word.
        let terms = ["C++", "AI", "3M", "Ravi", "Asha", "Dev", "Raj", "Amit", "Priya"]
        for sentence in ["Gurjit ka phone aaya, usko ki bolna.", "Is it a bug?", "Me too.", "The raw data, a rave party.",
                         "Ash, Asia, as a rule.", "Deva aaya.", "Raja ji se baat karo.", "I am it.", "Per ya nahi?"] {
            #expect(correct(sentence, terms: terms) == sentence)
        }
        #expect(correct("ravi aur asha aaye", terms: terms) == "Ravi aur Asha aaye")
    }

    @Test func otherWordsAndNamesThatSoundCloseStayAsTheyAre() {
        #expect(correct("the vessel sank", terms: ["Vercel"]) == "the vessel sank")  // an English word
        #expect(correct("Korean food and a cron job", terms: ["Kiran"]) == "Korean food and a cron job")
        #expect(correct("Rohini is here", terms: ["Rohan"]) == "Rohini is here")
    }

    @Test func fixesPossessivesAndLongTerms() {
        #expect(correct("Gurjit's laptop and rohan's") == "Gurjeet's laptop and Rohan's")
        #expect(correct("open the visual studio code window", terms: ["Visual Studio Code Insiders"]) == "open the visual studio code window")
        #expect(correct("open visual studio code insiders now", terms: ["Visual Studio Code Insiders"]) == "open Visual Studio Code Insiders now")
    }

    @Test func aBigDictionaryStaysFast() {
        let terms = (0..<200).map { "Name\($0)x" } + ["Gurjeet"]
        let text = Array(repeating: "Gurjit ko message karo ki main meeting mein hoon aur baad mein call karta hoon.", count: 200).joined(separator: " ")
        let clock = ContinuousClock()
        var corrected = ""
        let took = clock.measure { corrected = correct(text, terms: terms) }
        #expect(corrected.hasPrefix("Gurjeet ko"))
        #expect(took < .milliseconds(300))
    }

    @Test func anEmptyDictionaryChangesNothing() {
        let text = "Message gurujit saying I will be late."
        #expect(DictionaryCorrection.correct(text, terms: []) == text)
        #expect(DictionaryCorrection.correct(text, terms: ["  ", ""]) == text)
    }
}
