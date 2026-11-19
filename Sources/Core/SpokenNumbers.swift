import Foundation

/// Spoken numbers, written the usual way (v2 ticket 07): 10 and up as digits ("15 minutes", "400 milliseconds"),
/// one to nine as words ("three updates", "meet at five") except in times, decimals, percentages and dates
/// ("11:30", "3 PM", "1.5 seconds", "5%", "1st of December"). Parakeet writes most numbers as words (v2 ticket 06);
/// digits a model already wrote are left alone. Number words in a row that make no single number ("one two
/// three") stay words, and so do ordinals under 10 away from a month ("First, ...", "wait a second").
enum SpokenNumbers {
    static func digits(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(Word.init)
        var output: [String] = []
        var index = 0
        // The number just before was left as words, and nothing came between: so is this one ("one two").
        var afterNumber = false
        while index < words.count {
            guard let number = Number(reading: words, at: index) else {
                output.append(clockTime(words[index]) ?? words[index].raw)
                index += 1
                afterNumber = false
                continue
            }
            if !afterNumber, let (written, end) = write(number, in: words) {
                output.append(written)
                index = end
                afterNumber = false
            } else {
                output += words[number.start..<number.end].map(\.raw)
                index = number.end
                afterNumber = !number.isOrdinal && number.runsOn(in: words)
            }
        }
        return output.joined(separator: " ")
    }

    /// The number as digits, and where the words it used end; nil to leave it as words.
    private static func write(_ number: Number, in words: [Word]) -> (String, end: Int)? {
        let lead = words[number.start].lead
        /// The digits in place of the words up to `end`, with the punctuation around them.
        func written(_ digits: String, end: Int, percent: Bool = true) -> (String, end: Int) {
            var digits = digits, end = end
            if percent, words[end - 1].trail.isEmpty, end < words.count, words[end].lead.isEmpty {
                if words[end].name == "percent" {
                    digits += "%"
                    end += 1
                } else if words[end].name == "per", words[end].trail.isEmpty, end + 1 < words.count,
                          words[end + 1].name == "cent", words[end + 1].lead.isEmpty {
                    digits += "%"
                    end += 2
                }
            }
            return (lead + digits + words[end - 1].trail, end)
        }
        let value = number.value, after = number.end
        if number.isOrdinal {
            // "a thirty-second ad" is a length of time; "the twenty-second of December" is a date.
            guard value >= 10 && !number.endsInSecond || isNextToMonth(number, in: words) else { return nil }
            return written("\(value)\(ordinalSuffix(value))" + (number.remainder.map { "-" + $0 } ?? ""), end: after,
                           percent: false)
        }
        if number.runsOn(in: words) {
            // "At one point, ..." is a moment, not a decimal.
            let atOnePoint = value == 1 && number.isOneWord && number.start > 0 && words[number.start - 1].name == "at"
            if !atOnePoint, let (fraction, end) = fraction(after: after, in: words) {
                return written("\(value).\(fraction)", end: end)
            }
            if number.isOneWord, (1...12).contains(value) {
                if let (minutes, end) = twoDigits(after: after, in: words, within: 10...59),
                   isTime(from: number.start, to: end, in: words), !isCounting(at: end, in: words) {
                    return written("\(value):\(minutes)", end: end, percent: false)
                }
                // "3 PM", "5 o'clock": the word after stays as it is.
                let next = words[after]
                if next.lead.isEmpty, ["am", "pm", "o'clock", "o’clock"].contains(next.name.replacingOccurrences(of: ".", with: "")) {
                    return written("\(value)", end: after, percent: false)
                }
            }
            if number.isOneWord, value == 19 || value == 20,
               let (rest, end) = twoDigits(after: after, in: words, within: 10...99), !isCounting(at: end, in: words) {
                return written("\(value)\(rest)", end: end, percent: false)
            }
            let percent = written("\(value)", end: after)
            if percent.end > after { return percent }
            // Two numbers in a row ("one two"): there's no telling where one ends, so both stay words.
            if Number(reading: words, at: after) != nil { return nil }
        }
        guard value >= 10 else { return nil }
        return written(plain(value) + (number.remainder.map { "-" + $0 } ?? ""), end: after, percent: number.remainder == nil)
    }

    /// The digits after the decimal point: "point five" or "and a half".
    private static func fraction(after index: Int, in words: [Word]) -> (String, end: Int)? {
        let names = words[index...].prefix(3).map(\.name)
        if names == ["and", "a", "half"], words[index].isBare, words[index + 1].isBare, words[index + 2].lead.isEmpty {
            return ("5", index + 3)
        }
        guard names.first == "point", words[index].isBare else { return nil }
        var digits = "", end = index + 1
        while end < words.count, words[end].lead.isEmpty, let digit = Self.digit(words[end].name) {
            digits += "\(digit)"
            end += 1
            if !words[end - 1].trail.isEmpty { break }
        }
        return digits.isEmpty ? nil : (digits, end)
    }

    /// Minutes after an hour or the end of a year: a number from `range` ("thirty", "twenty-six"), or "oh" and a
    /// digit ("oh five").
    private static func twoDigits(after index: Int, in words: [Word], within range: ClosedRange<Int>) -> (String, end: Int)? {
        if words[index].name == "oh", words[index].isBare, index + 1 < words.count, words[index + 1].lead.isEmpty,
           let digit = digit(words[index + 1].name), digit > 0 {
            return ("0\(digit)", index + 2)
        }
        guard let number = Number(reading: words, at: index), number.start == index, !number.isOrdinal,
              !number.hasScale, number.remainder == nil, range.contains(number.value)
        else { return nil }
        return ("\(number.value)", number.end)
    }

    /// An hour and minutes are a time only with a word that says so: "at eleven thirty", "eleven thirty tomorrow";
    /// not "room two twelve" or "it costs one fifty". "Ten oh five" says so itself.
    private static func isTime(from start: Int, to end: Int, in words: [Word]) -> Bool {
        if words[start + 1].name == "oh" { return true }
        let before = start > 0 && words[start - 1].trail.isEmpty && words[start].lead.isEmpty
            && timeWordsBefore.contains(words[start - 1].name)
        let after = end < words.count && words[end - 1].trail.isEmpty && words[end].lead.isEmpty
            && timeWordsAfter.contains(words[end].name.replacingOccurrences(of: ".", with: ""))
        return before || after
    }

    private static let timeWordsBefore: Set<String> = ["at", "by", "until", "till", "from", "to", "around", "before",
                                                       "after", "between", "since"]
    private static let timeWordsAfter: Set<String> = ["am", "pm", "tomorrow", "today", "tonight"]

    /// Two numbers followed by what they count are a rough count, not a time or a year: "five ten minutes", "twenty
    /// thirty people".
    private static func isCounting(at index: Int, in words: [Word]) -> Bool {
        index < words.count && words[index - 1].trail.isEmpty && words[index].lead.isEmpty
            && countedThings.contains(words[index].name)
    }

    private static let countedThings: Set<String> = ["seconds", "minutes", "hours", "days", "weeks", "months", "years",
                                                     "times", "people", "rupees", "dollars"]

    /// "six.15" as "6:15": Parakeet sometimes writes the hour as a word and the minutes as digits (eval clip 57).
    private static func clockTime(_ word: Word) -> String? {
        let parts = word.name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Number.vocabulary[String(parts[0])], !hour.isOrdinal,
              (1...12).contains(hour.value), parts[1].count == 2, parts[1].allSatisfy(\.isASCII),
              let minutes = Int(parts[1]), (0...59).contains(minutes)
        else { return nil }
        return "\(word.lead)\(hour.value):\(parts[1])\(word.trail)"
    }

    private static func digit(_ name: String) -> Int? {
        name == "oh" ? 0 : Number.vocabulary[name].flatMap { $0.kind == .unit && !$0.isOrdinal ? $0.value : nil }
    }

    private static let months: Set<Substring> = ["January", "February", "March", "April", "May", "June", "July",
                                                 "August", "September", "October", "November", "December"]

    /// "December first", "the first of December".
    private static func isNextToMonth(_ number: Number, in words: [Word]) -> Bool {
        if number.start > 0, words[number.start - 1].trail.isEmpty, months.contains(words[number.start - 1].core) {
            return true
        }
        let after = number.end
        return number.runsOn(in: words) && after + 1 < words.count && words[after].name == "of" && words[after].isBare
            && words[after + 1].lead.isEmpty && months.contains(words[after + 1].core)
    }

    private static func ordinalSuffix(_ value: Int) -> String {
        if (11...13).contains(value % 100) { return "th" }
        return switch value % 10 {
        case 1: "st"
        case 2: "nd"
        case 3: "rd"
        default: "th"
        }
    }

    /// "2 million"; commas from 10,000 ("25,000"), so years and four-digit amounts read as "2026" and "1500".
    private static func plain(_ value: Int) -> String {
        for (scale, name) in [(1_000_000_000, "billion"), (1_000_000, "million")] where value >= scale && value % scale == 0 {
            return "\(value / scale) \(name)"
        }
        let digits = String(value)
        guard value >= 10_000 else { return digits }
        var grouped = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped += "," }
            grouped.append(character)
        }
        return grouped
    }
}

/// One space-separated word of the text, and the punctuation around it.
private struct Word {
    let raw: String
    let lead: Substring
    let core: Substring
    let trail: Substring
    /// The word in lower case.
    let name: String
    /// Its parts between hyphens, in lower case ("twenty-five").
    let pieces: [String]

    init(_ raw: Substring) {
        self.raw = String(raw)
        let start = raw.firstIndex { $0.isLetter || $0.isNumber } ?? raw.endIndex
        let end = raw[start...].lastIndex { $0.isLetter || $0.isNumber }.map { raw.index(after: $0) } ?? start
        lead = raw[..<start]
        core = raw[start..<end]
        trail = raw[end...]
        name = core.lowercased()
        pieces = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    }

    var isBare: Bool { lead.isEmpty && trail.isEmpty }
}

/// Number words in a row that make one number ("four hundred", "twenty-five", "a hundred and twenty").
private struct Number {
    enum Kind { case unit, teen, tens, hundred, scale, and }

    static let vocabulary: [String: (kind: Kind, value: Int, isOrdinal: Bool)] = {
        var words: [String: (kind: Kind, value: Int, isOrdinal: Bool)] = ["and": (.and, 0, false)]
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let unitOrdinals = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
        let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                     "nineteen"]
        let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        for (value, word) in units.enumerated() { words[word] = (.unit, value, false) }
        for (value, word) in unitOrdinals.enumerated() where !word.isEmpty { words[word] = (.unit, value, true) }
        for (offset, word) in teens.enumerated() {
            words[word] = (.teen, 10 + offset, false)
            words[offset == 2 ? "twelfth" : word + "th"] = (.teen, 10 + offset, true)
        }
        for (offset, word) in tens.enumerated() {
            words[word] = (.tens, 20 + 10 * offset, false)
            words[String(word.dropLast()) + "ieth"] = (.tens, 20 + 10 * offset, true)
        }
        words["hundred"] = (.hundred, 100, false)
        words["hundredth"] = (.hundred, 100, true)
        for (word, value) in [("thousand", 1_000), ("million", 1_000_000), ("billion", 1_000_000_000)] {
            words[word] = (.scale, value, false)
            words[word + "th"] = (.scale, value, true)
        }
        return words
    }()

    private(set) var value = 0
    let start: Int
    private(set) var end: Int
    private(set) var isOrdinal = false
    /// It has a hundred, thousand...: never minutes or the end of a year.
    private(set) var hasScale = false
    /// What follows it inside a hyphenated word ("year-old" in "twenty-five-year-old").
    private(set) var remainder: String?
    /// It ends in "second", which is also a length of time ("a thirty-second ad").
    private(set) var endsInSecond = false
    /// A single word ("eleven"), as an hour or the start of a year.
    var isOneWord: Bool { end - start == 1 && remainder == nil && pieceCount == 1 }
    private var pieceCount = 0

    /// The number starting at `index`, if a number starts there.
    init?(reading words: [Word], at index: Int) {
        start = index
        end = index
        var grammar = Grammar()
        var position = index
        // "a hundred", "a thousand": the "a" is the one.
        if words[index].name == "a", words[index].trail.isEmpty, index + 1 < words.count, words[index + 1].lead.isEmpty,
           ["hundred", "thousand"].contains(words[index + 1].pieces[0]) {
            grammar.startWithOne()
            position += 1
        }
        let firstWord = position
        while position < words.count {
            let word = words[position]
            if position > firstWord, !word.lead.isEmpty { break }
            var trial = grammar
            var taken = 0
            for (offset, piece) in word.pieces.enumerated() {
                let next: String? = offset + 1 < word.pieces.count ? word.pieces[offset + 1]
                    : word.trail.isEmpty && position + 1 < words.count && words[position + 1].lead.isEmpty
                    ? words[position + 1].pieces[0] : nil
                guard trial.take(piece, before: next) else { break }
                taken += 1
            }
            guard taken > 0, trial.words > 0 else { break }
            if taken < word.pieces.count {
                // A number starting a hyphenated word ("twenty-five-year-old"), unless it goes on with another
                // number ("twenty-twenty").
                guard position == firstWord, Self.vocabulary[word.pieces[taken]] == nil else { break }
                remainder = word.core.split(separator: "-", omittingEmptySubsequences: false)[taken...].joined(separator: "-")
            }
            grammar = trial
            end = position + 1
            pieceCount += taken
            endsInSecond = word.pieces[taken - 1] == "second"
            if remainder != nil || !word.trail.isEmpty || grammar.isClosed { break }
            position += 1
        }
        // "a hundred and" with nothing after it: the "and" isn't part of the number.
        if grammar.endsWithAnd { end -= 1 }
        guard end > firstWord else { return nil }
        value = grammar.value
        isOrdinal = grammar.isOrdinal
        hasScale = grammar.hasScale
    }

    /// Nothing comes between it and the next word: no punctuation, no hyphenated rest.
    func runsOn(in words: [Word]) -> Bool {
        remainder == nil && words[end - 1].trail.isEmpty && end < words.count
    }

    /// Which word may follow which: "twenty six" is one number, "twenty twenty" and "one two" aren't.
    private struct Grammar {
        private var total = 0
        private var current = 0
        private var last: Kind?
        private var smallestScale = Int.max
        private(set) var words = 0
        private(set) var isOrdinal = false
        private(set) var hasScale = false
        /// "zero" and ordinals end a number.
        private(set) var isClosed = false

        var value: Int { total + current }
        var endsWithAnd: Bool { last == .and }

        mutating func startWithOne() {
            current = 1
            last = .unit
            words = 1
        }

        /// Takes the word if the number goes on with it.
        mutating func take(_ word: String, before next: String?) -> Bool {
            guard !isClosed, let (kind, value, ordinal) = Number.vocabulary[word] else { return false }
            switch kind {
            case .unit:
                guard [nil, .tens, .hundred, .scale, .and].contains(last), value > 0 || last == nil else { return false }
                if value == 0 { isClosed = true }
                current += value
            case .teen, .tens:
                guard [nil, .hundred, .scale, .and].contains(last) else { return false }
                current += value
            case .hundred:
                // Not on its own ("hundred percent" stays as said).
                guard [.unit, .teen].contains(last), current < 100 else { return false }
                current *= 100
                hasScale = true
            case .scale:
                guard [.unit, .teen, .tens, .hundred].contains(last), value < smallestScale else { return false }
                total += current * value
                current = 0
                smallestScale = value
                hasScale = true
            case .and:
                // "a hundred and twenty"; not "one and a half" (a fraction) or "ten and two".
                guard [.hundred, .scale].contains(last), let next,
                      let following = Number.vocabulary[next], [.unit, .teen, .tens].contains(following.kind)
                else { return false }
                last = .and
                return true
            }
            last = kind
            words += 1
            if ordinal {
                isOrdinal = true
                isClosed = true
            }
            return true
        }
    }
}
