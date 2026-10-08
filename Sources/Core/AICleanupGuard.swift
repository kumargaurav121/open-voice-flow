import Foundation

/// Decides whether an AI cleanup can replace the transcript. A cleanup may only delete fillers and
/// repeated words and fix punctuation and casing, so:
/// - every dropped word must be a filler where it was dropped, or a nearby repeat of a word it kept;
/// - it may not add words or shrink the text below half;
/// - it must stay in English letters.
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

    public static func accepts(original: String, rewritten: String) -> Bool {
        let spoken = tokens(original)
        let cleaned = tokens(rewritten).map(\.word)
        guard !cleaned.isEmpty, !spoken.isEmpty,
              !rewritten.unicodeScalars.contains(where: isIndicOrArabic)
        else { return false }
        let vocabulary = Set(spoken.map(\.word))
        let newWords = cleaned.filter { !vocabulary.contains($0) }.count
        return Double(newWords) / Double(cleaned.count) <= maxNewWordShare
            && Double(cleaned.count) / Double(spoken.count) >= minLengthRatio
            && onlyFillersAndRepeatsDeleted(spoken: spoken, cleaned: cleaned)
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
    }

    private static func tokens(_ text: String) -> [Token] {
        let pieces = text.replacingOccurrences(of: "\u{2019}", with: "'").lowercased().split(whereSeparator: \.isWhitespace)
        var result: [Token] = []
        var afterBoundary = true
        for piece in pieces {
            let words = piece.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map { canonical(String($0)) }
            let endsWithBoundary = piece.last.map { ",.;:?!".contains($0) } ?? false
            for (index, word) in words.enumerated() {
                result.append(Token(word: word,
                                    boundaryBefore: index == 0 && afterBoundary,
                                    boundaryAfter: index == words.count - 1 && endsWithBoundary))
            }
            if !words.isEmpty { afterBoundary = endsWithBoundary }
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
