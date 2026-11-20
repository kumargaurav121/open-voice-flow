import Foundation

/// Spoken lists as numbered lines (v2 ticket 10): enumerators counting up from 1, each starting a phrase, become
/// "1. Item" lines after a lead-in ending in a colon. Dictation only, after the AI pass, line by line.
/// - Enumerators: "first, second…", "number one…", Hindi "pahla, doosra…", a model's own "1. … 2. …", and
///   "one, … two, …" when the number has its punctuation or starts a clause ("two the release notes", as
///   Parakeet writes it); before a noun a number is a quantity ("two pastas"). "First time" and "pehli baar" are
///   never enumerators.
/// - Clear lists only: every enumerator has its own punctuation or comes before an article ("One, …", "two the
///   …"), or there are three or more of them ("first doodh, second bread, third ande"). No item may be empty or
///   start with a joining word ("first and foremost", "first of all").
/// - A list of three or more may start with an ordinal mid-phrase ("I need to buy first milk, second bread, third
///   eggs"; the user's choice, 2026-11-20), unless they are ranks: "first prize, second prize", "first in maths".
/// - "And" before an enumerator is dropped, and so is "is" after a bare ordinal ("first is milk" → "1. Milk").
/// - Items start with a capital. If every item is up to three words they are fragments with no full stop
///   ("Doodh"); otherwise all are sentences and end with one.
/// - The last item ends at its first sentence end; what follows goes below the list.
enum SpokenLists {
    static func apply(_ text: String) -> String {
        text.components(separatedBy: "\n").map(layOut).joined(separator: "\n")
    }

    private static func layOut(_ line: String) -> String {
        let words = line.split(separator: " ").map(Word.init)
        guard let list = list(in: words) else { return line }
        var lines: [String] = []
        if !list.leadIn.isEmpty { lines.append(introducing(list.leadIn.map(\.raw).joined(separator: " "))) }
        let sentences = list.items.contains { $0.count > 3 }
        for (position, item) in list.items.enumerated() {
            lines.append("\(position + 1). " + written(item, asSentence: sentences))
        }
        let after = list.after.map(\.raw).joined(separator: " ")
        return lines.joined(separator: "\n") + (after.isEmpty ? "" : "\n\n" + after)
    }

    // MARK: Finding a list

    private struct List {
        let leadIn: [Word]
        let items: [[Word]]
        let after: [Word]
    }

    private enum Kind { case ordinal, hindiOrdinal, numbered, cardinal, digits }

    private struct Enumerator {
        let kind: Kind
        let value: Int
        let start: Int
        /// The index after it.
        let end: Int
        /// Followed by its own punctuation or an article: clearly an enumerator even in a list of two.
        let marked: Bool
        /// Not at a phrase start ("buy first milk"): only a first ordinal, in a list of three or more.
        var midPhrase = false
    }

    private static let ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
    private static let cardinals = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    /// "Pahla, doosra…" in the Hinglish model's spellings, and others; "ek, do, teen" are quantities, never these.
    private static let hindiOrdinals: [String: Int] = [
        "pahla": 1, "pehla": 1, "pahli": 1, "pehli": 1, "doosra": 2, "dusra": 2, "doosri": 2, "dusri": 2,
        "teesra": 3, "tisra": 3, "teesri": 3, "tisri": 3, "chautha": 4, "chauthi": 4,
        "paanchva": 5, "panchva": 5, "paanchvi": 5, "panchvi": 5,
    ]
    /// After an ordinal, these make it part of a noun ("first time", "pehli baar", "doosra wala").
    private static let ordinalNouns: Set<String> = ["time", "times", "baar", "one", "ones", "wala", "wali", "waala", "waali"]
    /// Words that can come between an item and the next enumerator.
    private static let connectors: Set<String> = ["and", "aur", "then"]
    /// An item can't start with one: the ordinal was part of a phrase ("first and foremost", "first of all").
    private static let joiningWords: Set<String> = ["and", "or", "of", "but", "aur", "ya"]
    /// An item starting with one makes mid-phrase ordinals ranks ("first in maths, second in science").
    private static let prepositions: Set<String> = ["in", "at", "on", "for", "to", "by", "with", "from", "among"]
    /// After an enumerator, these start its item clearly.
    private static let articles: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "our", "your", "his", "her", "their", "its",
    ]
    /// After a number, these also start a clause ("three I am blogged"), where a noun would make it a quantity.
    private static let pronouns: Set<String> = [
        "i", "we", "you", "he", "she", "it", "they", "there", "i'm", "i've", "i'll", "we're", "we've", "we'll",
        "you're", "it's", "he's", "she's", "they're", "there's",
    ]

    /// The first clear list in the line.
    private static func list(in words: [Word]) -> List? {
        let candidates = words.indices.compactMap { enumerator(at: $0, in: words) }
        for first in candidates where first.value == 1 {
            var run = [first], end = first.end
            for next in candidates where next.kind == first.kind && next.value == run.count + 1 && next.start > end {
                run.append(next)
                end = next.end
            }
            if let list = list(of: run, in: words) { return list }
        }
        return nil
    }

    private static func list(of run: [Enumerator], in words: [Word]) -> List? {
        let startsMidPhrase = run[0].midPhrase
        guard run.count >= (startsMidPhrase ? 3 : 2), run.allSatisfy(\.marked) || run.count >= 3 else { return nil }
        var items: [[Word]] = []
        var after: [Word] = []
        for (position, enumerator) in run.enumerated() {
            let isLast = position == run.count - 1
            var item = Array(words[enumerator.end..<(isLast ? words.count : run[position + 1].start)])
            // "…anday. And fourth", "…the app and then second": these join the next item.
            while !isLast, let last = item.last, last.isBare, connectors.contains(last.name) { item.removeLast() }
            if enumerator.kind == .ordinal, !enumerator.marked, let first = item.first, first.isBare, first.name == "is" {
                item.removeFirst()
            }
            if isLast, let end = item.dropLast().firstIndex(where: { $0.trail.contains(where: { ".?!".contains($0) }) }) {
                after = Array(item[(end + 1)...])
                item = Array(item[...end])
            }
            guard let first = item.first, !joiningWords.contains(first.name) else { return nil }
            items.append(item)
        }
        if startsMidPhrase {
            // Ranks, not a list: "first prize, second prize…", "first in maths, second in science…".
            guard Set(items.map { $0.map(\.name).joined(separator: " ") }).count > 1,
                  !items.contains(where: { prepositions.contains($0[0].name) })
            else { return nil }
        }
        return List(leadIn: Array(words[..<run[0].start]), items: items, after: after)
    }

    private static func enumerator(at index: Int, in words: [Word]) -> Enumerator? {
        guard startsAPhrase(index, in: words) else {
            // "Buy first milk, …": only a first ordinal, and the list must then be three or more.
            guard ["first", "pahla", "pehla", "pahli", "pehli"].contains(words[index].name),
                  var first = reading(at: index, in: words)
            else { return nil }
            first.midPhrase = true
            return first
        }
        return reading(at: index, in: words)
    }

    /// The enumerator the words at `index` are, if they start a phrase.
    private static func reading(at index: Int, in words: [Word]) -> Enumerator? {
        let word = words[index]
        let next = index + 1 < words.count ? words[index + 1] : nil
        func found(_ kind: Kind, _ value: Int, length: Int = 1, marked: Bool? = nil) -> Enumerator {
            let last = words[index + length - 1]
            let followedByArticle = index + length < words.count && articles.contains(words[index + length].name)
            return Enumerator(kind: kind, value: value, start: index, end: index + length,
                              marked: marked ?? (!last.trail.isEmpty || followedByArticle))
        }
        if let value = ordinals.firstIndex(of: word.name).map({ $0 + 1 }) ?? ordinalDigits(word) {
            return ordinalNouns.contains(next?.name ?? "") ? nil : found(.ordinal, value)
        }
        if let value = hindiOrdinals[word.name] {
            return ordinalNouns.contains(next?.name ?? "") ? nil : found(.hindiOrdinal, value)
        }
        if word.name == "number", word.isBare, let next,
           let value = cardinals.firstIndex(of: next.name).map({ $0 + 1 }) ?? Int(next.core) {
            return found(.numbered, value, length: 2)
        }
        if word.lead.isEmpty, [".", ")"].contains(word.trail), let value = Int(word.core) {
            return found(.digits, value, marked: true)
        }
        // "One, the login bug" and "three I am" enumerate; "one coffee" is a quantity.
        if let value = cardinals.firstIndex(of: word.name).map({ $0 + 1 }),
           !word.trail.isEmpty || articles.contains(next?.name ?? "") || pronouns.contains(next?.name ?? "") {
            return found(.cardinal, value)
        }
        return nil
    }

    /// "10th": spoken ordinals from tenth reach this step as digits.
    private static func ordinalDigits(_ word: Word) -> Int? {
        guard let suffix = ["st", "nd", "rd", "th"].first(where: { word.name.hasSuffix($0) }) else { return nil }
        return Int(word.name.dropLast(suffix.count))
    }

    private static func startsAPhrase(_ index: Int, in words: [Word]) -> Bool {
        guard index > 0 else { return true }
        let previous = words[index - 1]
        return previous.trail.contains(where: { ",.;:?!".contains($0) }) || previous.isBare && connectors.contains(previous.name)
    }

    // MARK: Writing

    /// The lead-in ends with a colon, unless it asks or exclaims.
    private static func introducing(_ leadIn: String) -> String {
        if let last = leadIn.last, "?!".contains(last) { return leadIn }
        return leadIn.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")) + ":"
    }

    private static func written(_ item: [Word], asSentence: Bool) -> String {
        var text = item.map(\.raw).joined(separator: " ")
        // The first word's capital: "12 eggs" stays as it is.
        if let first = text.firstIndex(where: { $0.isLetter || $0.isNumber }), text[first].isLetter {
            text.replaceSubrange(first...first, with: text[first].uppercased())
        }
        if let last = text.last, "?!".contains(last) { return text }
        let bare = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return asSentence ? bare + "." : bare
    }
}
