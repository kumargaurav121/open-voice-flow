import Foundation

/// Decides whether an AI cleanup can replace the transcript. A cleanup may only delete fillers and
/// repeated words and fix punctuation and casing, so:
/// - every dropped word must be a filler where it was dropped, or a nearby repeat of a word it kept;
/// - it may not add words or shrink the text below half;
/// - it must stay in English letters.
/// A self-correction may go too (v2 ticket 11): a dropped run of up to 12 words, a mistake and a correction marker
/// ("four, actually no, let's make it"), when the kept fix after it replaces the mistake word for word and the
/// rewrite adds no word at all (ADR 0015).
/// Line breaks are the speaker's ("new line", "new paragraph"): the rewrite keeps exactly the same ones. Colons and
/// list numbers opening a line ("1.", "2)") are layout, not words. An email's rewrite may add breaks (its greeting,
/// paragraphs and sign-off, v2 ticket 13) but keeps every spoken one between the same words.
/// Anything else (an answer, a translation, a dropped "mujhe lagta hai ki", "I like it" → "I it") is
/// rejected and the rules-cleaned text is used instead.
public enum AICleanupGuard {
    /// At most this share of the rewrite's words may be new (not spoken).
    static let maxNewWordShare = 0.2
    /// The rewrite must keep at least this share of the spoken word count.
    static let minLengthRatio = 0.5
    /// A dropped copy counts as a stutter only if the same word was said this many words earlier or fewer
    /// ("the the", "can you can you"); further apart, the repetition is probably meant.
    static let repeatWindow = 2

    /// Never meaningful: always deletable.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "hmm", "ah", "basically", "literally"]
    /// Fillers only at a sentence or comma boundary ("So, …", "…, like, …"); elsewhere they carry meaning
    /// ("I like it", "so much", Hindi "na" as a negation).
    static let boundaryFillers: Set<String> = ["so", "like", "actually", "well", "na", "toh", "matlab", "yaani"]
    /// Said between a mistake and its fix ("four, actually no, five"); "nahin nahin" as the Hinglish model writes it.
    static let correctionMarkers: [[String]] = [
        ["actually", "no"], ["no", "wait"], ["scratch", "that"], ["i", "mean"], ["sorry"], ["nahi", "nahi"],
        ["nahin", "nahin"],
    ]
    /// The longest dropped run a correction can explain, its marker included.
    static let maxCorrectionLength = 12
    /// Spoken words × rewritten words the correction check aligns at most (about 500 words each, a few
    /// milliseconds); longer dictations get no corrections.
    static let maxAlignment = 250_000

    /// - Parameter mayAddBreaks: the rewrite may add line breaks and blank lines (an email's layout).
    public static func accepts(original: String, rewritten: String, mayAddBreaks: Bool = false) -> Bool {
        // List numbers are layout on both sides: never a word, nor standing in for a spoken one.
        let spoken = tokens(original).filter { !$0.isListNumber }
        let rewrittenTokens = tokens(rewritten).filter { !$0.isListNumber }
        let cleaned = rewrittenTokens.map(\.word)
        let sameBreaks = breaks(original) == breaks(rewritten)
        guard !cleaned.isEmpty, !spoken.isEmpty,
              mayAddBreaks ? keepsSpokenBreaks(spoken: spoken, rewritten: rewrittenTokens) ?? sameBreaks : sameBreaks,
              !rewritten.unicodeScalars.contains(where: isIndicOrArabic)
        else { return false }
        if onlyTidied(spoken: spoken, cleaned: cleaned, maxNewWordShare: maxNewWordShare) { return true }
        // Only what today's rules reject is checked for self-corrections, so nothing accepted before changes.
        guard let corrected = withoutCorrections(spoken: spoken, cleaned: cleaned) else { return false }
        return onlyTidied(spoken: corrected, cleaned: cleaned, maxNewWordShare: 0)
    }

    /// The rewrite only deleted fillers and repeats, added at most `maxNewWordShare` new words, and kept half.
    private static func onlyTidied(spoken: [Token], cleaned: [String], maxNewWordShare: Double) -> Bool {
        let vocabulary = Set(spoken.map(\.word))
        let newWords = cleaned.filter { !vocabulary.contains($0) }.count
        return Double(newWords) / Double(cleaned.count) <= maxNewWordShare
            && Double(cleaned.count) / Double(spoken.count) >= minLengthRatio
            && onlyFillersAndRepeatsDeleted(spoken: spoken, cleaned: cleaned)
    }

    // MARK: Self-corrections

    /// The spoken words without the self-corrections the rewrite dropped, or nil when a dropped run isn't one
    /// (or the text is too long to align). Both ways of aligning repeated words must agree it is a correction:
    /// matched to their latest spoken copies, and to their earliest.
    private static func withoutCorrections(spoken: [Token], cleaned: [String]) -> [Token]? {
        var corrected: [Token]?
        for latest in [true, false] {
            guard let kept = keptIndices(spoken: spoken.map(\.word), cleaned: cleaned, latestCopies: latest),
                  let result = withoutCorrections(spoken: spoken, kept: kept)
            else { return nil }
            corrected = result
        }
        return corrected
    }

    private static func withoutCorrections(spoken: [Token], kept: Set<Int>) -> [Token]? {
        let keptTokens = spoken.indices.filter(kept.contains).map { spoken[$0] }
        var result: [Token] = []
        var dropped: [Token] = []
        var keptSoFar = 0
        var corrected = false
        func endDroppedRun() {
            if isCorrection(dropped, fix: keptTokens[keptSoFar...]) {
                corrected = true
            } else {
                result += dropped
            }
            dropped = []
        }
        for (index, token) in spoken.enumerated() {
            if kept.contains(index) {
                endDroppedRun()
                result.append(token)
                keptSoFar += 1
            } else {
                dropped.append(token)
            }
        }
        endDroppedRun()
        return corrected ? result : nil
    }

    /// A dropped run of a mistake and a marker ("four, actually no"), with a kept fix right after it that
    /// replaces the mistake word for word: "two tickets" → "three tickets",
    /// "teen baje hai" → "chaar baje hai". Anything else may be meaning ("We can't do Friday, sorry, I'll call
    /// you tomorrow" → "I'll call you tomorrow") or the fix dropped instead ("Book two tickets, no wait, three
    /// tickets" → "Book two tickets").
    private static func isCorrection(_ run: [Token], fix: ArraySlice<Token>) -> Bool {
        guard run.count <= maxCorrectionLength else { return false }
        let words = run.map(\.word)
        return correctionMarkers.contains { marker in
            occurrences(of: marker, in: words).contains { start in
                start > 0 && replaces(Array(run[..<start]), with: Array(fix.prefix(start)))
            }
        }
    }

    /// The fix lines up with the mistake word for word and changes at most half of it, at least one word. A one-word
    /// mistake must be swapped for its own kind: a number for a number ("four" → "five"), a name for a name.
    private static func replaces(_ mistake: [Token], with fix: [Token]) -> Bool {
        guard fix.count == mistake.count else { return false }
        let changed = zip(mistake, fix).filter { $0.word != $1.word }.count
        guard changed >= 1, changed <= max(1, mistake.count / 2) else { return false }
        guard mistake.count == 1 else { return true }
        let (was, now) = (mistake[0], fix[0])
        let isNumber = { (token: Token) in token.word.allSatisfy(\.isNumber) }
        return isNumber(was) && isNumber(now) || was.capitalized && now.capitalized
    }

    /// Which spoken words the rewrite kept: each kept word matched to its latest spoken copy, or its earliest.
    /// Nil for texts too long to align.
    private static func keptIndices(spoken: [String], cleaned: [String], latestCopies: Bool) -> Set<Int>? {
        guard latestCopies else {
            // The earliest copies are the latest of the texts reversed.
            let reversed = keptIndices(spoken: spoken.reversed(), cleaned: cleaned.reversed(), latestCopies: true)
            return reversed.map { Set($0.map { spoken.count - 1 - $0 }) }
        }
        return matches(spoken: spoken, cleaned: cleaned).map { Set($0.map(\.spoken)) }
    }

    /// Each kept spoken word and the rewritten word it is, in order, matched to its latest spoken copy. Nil for texts
    /// too long to align.
    private static func matches(spoken: [String], cleaned: [String]) -> [(spoken: Int, cleaned: Int)]? {
        let (n, m) = (spoken.count, cleaned.count)
        guard n * m <= maxAlignment else { return nil }
        // Longest common subsequence of the prefixes.
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                table[i][j] = spoken[i - 1] == cleaned[j - 1] ? table[i - 1][j - 1] + 1 : max(table[i - 1][j], table[i][j - 1])
            }
        }
        // Walking back from the ends matches each word to its latest copy.
        var matched: [(spoken: Int, cleaned: Int)] = []
        var (i, j) = (n, m)
        while i > 0, j > 0 {
            if spoken[i - 1] == cleaned[j - 1] {
                matched.append((i - 1, j - 1))
                (i, j) = (i - 1, j - 1)
            } else if table[i - 1][j] >= table[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return matched.reversed()
    }

    // MARK: Layout

    /// Every spoken break is still between the same kept words: a new line as a new line or a paragraph, a
    /// paragraph as a paragraph. Breaks the rewrite adds don't matter. Nil for texts too long to align.
    private static func keepsSpokenBreaks(spoken: [Token], rewritten: [Token]) -> Bool? {
        guard let pairs = matches(spoken: spoken.map(\.word), cleaned: rewritten.map(\.word)) else { return nil }
        return zip(pairs, pairs.dropFirst()).allSatisfy { previous, next in
            let (said, saidNext) = (spoken[previous.spoken], spoken[next.spoken])
            let (written, writtenNext) = (rewritten[previous.cleaned], rewritten[next.cleaned])
            return (saidNext.line == said.line || writtenNext.line > written.line)
                && (saidNext.paragraph == said.paragraph || writtenNext.paragraph > written.paragraph)
        }
    }

    /// The text's line breaks in order: 1 for a new line, 2 for a new paragraph (any blank lines).
    private static func breaks(_ text: String) -> [Int] {
        var result: [Int] = []
        var blankLine = false
        for line in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blankLine = true
            } else {
                result.append(blankLine ? 2 : 1)
                blankLine = false
            }
        }
        return result
    }

    // MARK: Deletions

    private static func onlyFillersAndRepeatsDeleted(spoken: [Token], cleaned: [String]) -> Bool {
        let words = spoken.map(\.word)
        let kept = counts(cleaned)
        var deleted: [String: Int] = [:]
        for (word, count) in counts(words) where count > kept[word, default: 0] {
            deleted[word] = count - kept[word, default: 0]
        }
        // Filler phrases removed where they are fillers account for their words.
        for (phrase, isFillerAt) in phrases {
            let removed = occurrences(of: phrase, in: words).count - occurrences(of: phrase, in: cleaned).count
            let credit = min(max(removed, 0), occurrences(of: phrase, in: words).filter { isFillerAt(spoken, $0) }.count)
            for word in phrase { deleted[word, default: 0] -= credit }
        }
        var allowance: [String: Int] = [:]
        for (index, token) in spoken.enumerated() {
            if boundaryFillers.contains(token.word), token.boundaryBefore || token.boundaryAfter {
                allowance[token.word, default: 0] += 1
            }
            let recent = words[max(0, index - repeatWindow)..<index]
            if recent.contains(token.word) { allowance[token.word, default: 0] += 1 }
        }
        return deleted.allSatisfy { word, count in
            count <= 0 || fillers.contains(word) || count <= allowance[word, default: 0]
        }
    }

    /// Multi-word fillers and where they count as fillers, given the phrase's start index.
    private static let phrases: [([String], @Sendable ([Token], Int) -> Bool)] = [
        // "…, you know" / "you know, …" — not "do you know him".
        (["you", "know"], { tokens, start in tokens[start + 1].boundaryAfter }),
        // "I mean, …" / "and I mean we can't" — not "I mean it / that / what / this".
        (["i", "mean"], { tokens, start in
            tokens[start + 1].boundaryAfter || !["it", "that", "what", "this"].contains(tokens[safe: start + 2]?.word ?? "")
        }),
        // Only set off by punctuation: "it's, kind of, done" — not "what kind of car".
        (["kind", "of"], { tokens, start in tokens[start].boundaryBefore && tokens[start + 1].boundaryAfter }),
        (["sort", "of"], { tokens, start in tokens[start].boundaryBefore && tokens[start + 1].boundaryAfter }),
    ]

    // MARK: Tokens

    struct Token: Sendable {
        var word: String
        /// Starts the text or follows a , . ; : ? !
        var boundaryBefore: Bool
        /// Ends the text or is followed by a , . ; : ? !
        var boundaryAfter: Bool
        /// "1." or "2)" opening a line: layout, not a word said.
        var isListNumber = false
        /// Written with a capital: a name, or a sentence's first word.
        var capitalized = false
        /// Which line and paragraph of the text it's on, counting from 0.
        var line = 0
        var paragraph = 0
    }

    private static func tokens(_ text: String) -> [Token] {
        let lines = text.replacingOccurrences(of: "\u{2019}", with: "'").components(separatedBy: "\n")
        var result: [Token] = []
        var afterBoundary = true
        var (lineNumber, paragraph, blankLine) = (-1, 0, false)
        for line in lines {
            let pieces = line.split(whereSeparator: \.isWhitespace)
            guard !pieces.isEmpty else {
                blankLine = true
                continue
            }
            lineNumber += 1
            if blankLine, lineNumber > 0 { paragraph += 1 }
            blankLine = false
            for (position, piece) in pieces.enumerated() {
                let written = piece.split { !$0.isLetter && !$0.isNumber && $0 != "'" }
                let words = written.map { canonical($0.lowercased()) }
                let endsWithBoundary = piece.last.map { ",.;:?!".contains($0) } ?? false
                let isListNumber = position == 0 && piece.range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil
                for (index, word) in words.enumerated() {
                    result.append(Token(word: word,
                                        boundaryBefore: index == 0 && afterBoundary,
                                        boundaryAfter: index == words.count - 1 && endsWithBoundary,
                                        isListNumber: isListNumber,
                                        capitalized: written[index].first?.isUppercase ?? false,
                                        line: lineNumber, paragraph: paragraph))
                }
                if !words.isEmpty { afterBoundary = endsWithBoundary }
            }
        }
        if !result.isEmpty { result[result.count - 1].boundaryAfter = true }
        return result
    }

    /// The same word written another way isn't a change: "three" = "3", "okay" = "ok".
    static let equivalents: [String: String] = {
        let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                       "nineteen", "twenty"]
        var map = Dictionary(uniqueKeysWithValues: numbers.enumerated().map { ($1, String($0)) })
        for (word, value) in [("thirty", 30), ("forty", 40), ("fifty", 50), ("sixty", 60), ("seventy", 70),
                              ("eighty", 80), ("ninety", 90), ("hundred", 100)] {
            map[word] = String(value)
        }
        map["okay"] = "ok"
        return map
    }()

    private static func canonical(_ word: String) -> String {
        equivalents[word] ?? word
    }

    private static func counts(_ words: [String]) -> [String: Int] {
        words.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// Start indices of each occurrence of `phrase` in `words`.
    private static func occurrences(of phrase: [String], in words: [String]) -> [Int] {
        guard words.count >= phrase.count else { return [] }
        return (0...(words.count - phrase.count)).filter { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }

    private static func isIndicOrArabic(_ scalar: Unicode.Scalar) -> Bool {
        (0x0900...0x097F).contains(scalar.value) || (0x0600...0x06FF).contains(scalar.value)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
