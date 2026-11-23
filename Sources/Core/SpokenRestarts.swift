import Foundation

/// A phrase the speaker restarted, in English (v2 ticket 19): the first try goes, the second stays. Parakeet writes
/// restarts as said ("dropped from the from about"). Three kinds, each narrow, so ordinary speech stays ("very,
/// very", "I know, I know", "I think I can", "the end of the week or the end of the month", "per person"):
/// - an abandoned start: a function word, a word or two, then that word again, where the words dropped come back in
///   order right after, or were an article given up before a function word ("We also we are also", "from the from
///   about"); the same words twice are meant;
/// - a word broken off: a lowercase run of consonants the next word starts with ("tw twenty-eighth"), never a word;
/// - the same words written two ways, within a sentence ("e mail email").
/// Restarts shaped like ordinary speech stay as said (the user's choice): "lap laptops" is "per person"'s shape,
/// "next js. Next.js" is "log in. Login"'s, "to the team, to the beta group" a list's.
enum SpokenRestarts {
    static func remove(_ words: [String]) -> [String] {
        var kept: [String] = []
        var index = 0
        while index < words.count {
            if let firstTry = abandonedStart(at: index, in: words) ?? brokenOff(at: index, in: words)
                ?? writtenTwice(at: index, in: words) {
                index += firstTry
            } else {
                kept.append(words[index])
                index += 1
            }
        }
        return kept
    }

    /// Words a restart starts again from.
    private static let functionWords: Set<String> = [
        "i", "we", "you", "they", "he", "she", "it", "us", "me", "a", "an", "the", "this", "that", "my", "our", "your",
        "from", "to", "in", "on", "at", "for", "with", "of", "by", "about", "into", "over", "up", "out", "off", "and",
        "but", "or", "so", "is", "are", "was", "were", "be", "will", "can", "would", "should", "have", "has", "all",
        "any", "some", "no", "not",
    ]
    private static let articles: Set<String> = ["a", "an", "the"]
    /// Lowercase runs of consonants that are words of their own.
    private static let titles: Set<String> = ["mr", "mrs", "ms", "dr", "st", "jr", "sr"]

    /// "We also we are also": the length of the first try, when a function word comes back within three words and
    /// what it dropped comes back right after, in order. An article given up counts when the second try goes on with
    /// a function word or a number ("from the from about"), so "to the to do list" and "for a for loop" stay.
    private static func abandonedStart(at start: Int, in words: [String]) -> Int? {
        let word = core(words[start])
        guard functionWords.contains(word) else { return nil }
        for length in 2...3 {
            let again = start + length
            guard again < words.count, core(words[again]) == word else { continue }
            // A sentence that ended isn't a restart ("…fix it. It is…").
            guard !words[start..<again].contains(where: endsSentence) else { return nil }
            let dropped = words[(start + 1)..<again].map(core)
            let after = words[(again + 1)...].prefix(length + 1).map(core)
            // The same words twice are meant ("I know, I know", "over and over and").
            if Array(after.prefix(dropped.count)) == dropped { return nil }
            if isInOrder(dropped, in: after) { return length }
            if dropped.allSatisfy(articles.contains), let next = after.first,
               functionWords.contains(next) || next.first?.isNumber == true {
                return length
            }
        }
        return nil
    }

    /// "tw twenty-eighth": a lowercase run of consonants, not a title, that the next word starts with (as said: "28th"
    /// starts "tw"). A word never counts: "per person", "six sixteen" and "PR process" stay.
    private static func brokenOff(at index: Int, in words: [String]) -> Int? {
        let fragment = words[index]
        guard index + 1 < words.count, fragment.count >= 2, !titles.contains(fragment),
              fragment.allSatisfy({ $0.isLetter && $0.isLowercase && !"aeiouy".contains($0) })
        else { return nil }
        let next = spelledStart(of: core(words[index + 1]))
        return next.hasPrefix(fragment) && next.count > fragment.count ? 1 : nil
    }

    /// "e mail email": one to three words, then the same letters again written another way, within a sentence ("log
    /// in. Login" isn't one). Written the same way twice ("bye bye", "thank you thank you"), or with only an
    /// apostrophe between them ("it's its own"), the repeat is meant.
    private static func writtenTwice(at start: Int, in words: [String]) -> Int? {
        for first in 1...3 where start + first < words.count {
            let firstTry = words[start..<(start + first)]
            guard !firstTry.contains(where: endsSentence) else { return nil }
            for second in 1...3 where start + first + second <= words.count {
                let secondTry = words[(start + first)..<(start + first + second)]
                // Every word a word: a lone dash isn't ("2 - 2").
                guard (firstTry + secondTry).allSatisfy({ $0.contains { $0.isLetter || $0.isNumber } }) else { continue }
                if letters(firstTry) == letters(secondTry), !letters(firstTry).isEmpty,
                   firstTry.map(withoutApostrophes) != secondTry.map(withoutApostrophes) {
                    return first
                }
            }
        }
        return nil
    }

    /// Whether `words` appear in `others` in the same order, not necessarily side by side.
    private static func isInOrder(_ words: [String], in others: [String]) -> Bool {
        var rest = others[...]
        for word in words {
            guard let found = rest.firstIndex(of: word) else { return false }
            rest = rest[(found + 1)...]
        }
        return true
    }

    /// A word without the punctuation around it, in lowercase.
    private static func core(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private static func withoutApostrophes(_ word: String) -> String {
        core(word).replacingOccurrences(of: #"['’]"#, with: "", options: .regularExpression)
    }

    private static func letters(_ words: ArraySlice<String>) -> String {
        String(words.joined().lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func endsSentence(_ word: String) -> Bool {
        word.last.map { ".?!".contains($0) } == true
    }

    /// A word as it starts when said: a number's word ("28th" starts "twenty"), anything else itself.
    private static func spelledStart(of word: String) -> String {
        let digits = word.prefix(while: \.isNumber).filter(\.isASCII)
        guard let value = Int(digits) else { return word }
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
                     "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        let leading = value < 100 ? value : Int(String(digits.prefix(digits.count % 3 == 0 ? 3 : digits.count % 3)))!
        return leading < 20 ? units[leading] : leading < 100 ? tens[leading / 10] : units[leading / 100]
    }
}
