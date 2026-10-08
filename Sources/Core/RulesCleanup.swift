import Foundation

/// The always-on cleanup pass: fast (no model), conservative, and safe for Hinglish.
/// Only removes what never carries meaning — hesitation sounds and stuttered English function words —
/// and tidies spacing and capitalisation. Words that are *sometimes* fillers ("like", "so", "matlab",
/// "basically") are left for the optional AI pass, and Hindi reduplication ("jaldi jaldi") is kept.
public enum RulesCleanup {
    static let hesitations: Set<String> = ["um", "umm", "ummm", "uh", "uhh", "uhm", "er", "erm", "hmm", "hmmm", "ah"]
    /// Stutters on these are never intentional; on content words they can be (Hindi reduplication).
    static let stutterable: Set<String> = [
        "the", "a", "an", "i", "to", "and", "of", "in", "on", "is", "it", "that", "we", "you", "for", "with", "this",
    ]

    public static func clean(_ text: String) -> String {
        var words: [String] = []
        for raw in text.split(whereSeparator: \.isWhitespace).map(String.init) {
            let bare = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if hesitations.contains(bare) {
                // Keep sentence-ending punctuation the filler carried ("...ship it, uh." → "...ship it.").
                if let end = raw.last, ".?!".contains(end), let previous = words.popLast() {
                    let trimmed = previous.trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
                    // "really? um." keeps its question mark rather than becoming "really?."
                    words.append(trimmed.last.map { ".?!".contains($0) } == true ? trimmed : trimmed + String(end))
                } else if raw.hasSuffix(","), let previous = words.last, previous.hasSuffix(",") {
                    // A parenthetical filler (", uh,") takes its leading comma with it.
                    words[words.count - 1] = String(previous.dropLast())
                }
                continue
            }
            if let previous = words.last,
               stutterable.contains(bare),
               previous.lowercased().trimmingCharacters(in: .punctuationCharacters) == bare,
               previous.last.map({ !$0.isPunctuation }) ?? true {
                continue
            }
            words.append(raw)
        }
        var result = words.joined(separator: " ")
        result = result.replacingOccurrences(of: #"\s+([,.;:?!])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^[,;:]\s*"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #",(\s*[,.;:?!])"#, with: "$1", options: .regularExpression)
        // The pronoun "i", not the "i" in "i.e." or "i.e".
        result = result.replacingOccurrences(of: #"(?<![\w.])i(?![\w.])"#, with: "I", options: .regularExpression)
        return capitaliseSentences(result)
    }

    /// Capitalises the first letter of the text and of each sentence, where a sentence ends with . ? or !
    /// followed by a space — but not after a short abbreviation ("e.g. this") or inside a number ("3.5").
    private static func capitaliseSentences(_ text: String) -> String {
        let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "dr.", "approx."]
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var capitaliseNext = true
        for index in words.indices {
            if capitaliseNext, let first = words[index].firstIndex(where: \.isLetter) {
                words[index].replaceSubrange(first...first, with: words[index][first].uppercased())
                capitaliseNext = false
            }
            let word = words[index]
            if let last = word.last, ".?!".contains(last), !abbreviations.contains(word.lowercased()) {
                capitaliseNext = true
            }
        }
        return words.joined(separator: " ")
    }
}
