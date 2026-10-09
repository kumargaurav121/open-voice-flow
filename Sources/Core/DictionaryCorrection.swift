import Foundation

/// Respells the user's dictionary terms in a transcript. Speech models write names the way they heard them
/// ("gurujit", "Gurjit" for Gurjeet; "super base" for Supabase), and the Hinglish model ignores Whisper's
/// prompt, so terms are matched by sound instead: a word, or a few adjacent words, that sounds like a
/// term is replaced by the term's own spelling.
///
/// Built to leave ordinary words alone (a wrongly changed word is worse than a missed name):
/// - short terms (under five sounds) must sound identical, and match a single word only;
/// - longer terms may differ a little (vowels count half), with the same first sound and last consonant
///   ("version" never becomes "Vercel");
/// - a real English word on its own is never respelled ("vessel" stays, even with Vercel in the list).
public enum DictionaryCorrection {
    /// Allowed difference per sound in a term's key, exclusive (under 1.2 for a 6-sound name).
    static let tolerancePerSound = 0.2
    /// Keys shorter than this must match exactly.
    static let minFuzzyLength = 5

    /// - Parameter isEnglishWord: whether a single word is correctly spelled English (the app asks macOS's
    ///   spell checker); such words are left as they are.
    public static func correct(_ text: String, terms: [String], isEnglishWord: (String) -> Bool = { _ in false }) -> String {
        let terms = terms.compactMap(DictionaryStore.normalized)
            .map { Term(spelling: $0, key: soundKey($0)) }
            .filter { !$0.key.isEmpty }
        guard !terms.isEmpty else { return text }
        let maxSpan = (terms.map { $0.spelling.split(separator: " ").count }.max() ?? 1) + 1
        // Every match shares the term's first sound, so each word is only compared with those terms.
        let termsByFirstSound = Dictionary(grouping: terms) { $0.key[0] }

        let words = words(in: text)
        var replacements: [(range: Range<String.Index>, spelling: String)] = []
        var index = 0
        while index < words.count {
            if let match = bestMatch(startingAt: index, in: words, text: text, terms: termsByFirstSound[words[index].key.first ?? " "] ?? [],
                                     maxSpan: maxSpan, isEnglishWord: isEnglishWord) {
                let range = words[index].range.lowerBound..<words[index + match.length - 1].range.upperBound
                if text[range] != match.spelling { replacements.append((range, match.spelling)) }
                index += match.length
            } else {
                index += 1
            }
        }
        var corrected = text
        for replacement in replacements.reversed() {
            corrected.replaceSubrange(replacement.range, with: replacement.spelling)
        }
        return corrected
    }

    // MARK: Matching

    private struct Term {
        let spelling: String
        let key: [Character]
    }

    private struct Word {
        let range: Range<String.Index>
        let key: [Character]
    }

    private static func bestMatch(startingAt start: Int, in words: [Word], text: String, terms: [Term],
                                  maxSpan: Int, isEnglishWord: (String) -> Bool) -> (spelling: String, length: Int)? {
        var best: (spelling: String, length: Int, distance: Double)?
        for length in 1...maxSpan where start + length <= words.count {
            let span = words[start..<start + length]
            // Only words separated by spaces join up ("super base", not "super, base").
            if length > 1, zip(span, span.dropFirst()).contains(where: { !text[$0.range.upperBound..<$1.range.lowerBound].allSatisfy(\.isWhitespace) }) {
                break
            }
            let key = span.flatMap(\.key)
            var spanBest: (spelling: String, distance: Double)?
            for term in terms {
                let short = term.key.count < minFuzzyLength
                if short {
                    guard length == 1, key == term.key else { continue }
                } else {
                    // Cheap checks before the edit distance: most words can't be close.
                    guard Double(abs(key.count - term.key.count)) * 0.5 < tolerance(for: term.key),
                          sameEdges(key, term.key)
                    else { continue }
                }
                let distance = short ? 0 : soundDistance(key, term.key)
                guard distance == 0 || distance < tolerance(for: term.key) else { continue }
                if spanBest == nil || distance < spanBest!.distance { spanBest = (term.spelling, distance) }
            }
            // Asked only for candidates: the spell checker is the slow part.
            guard let spanBest, length > 1 || !isEnglishWord(String(text[span.first!.range])) else { continue }
            if best == nil || spanBest.distance < best!.distance {
                best = (spanBest.spelling, length, spanBest.distance)
            }
        }
        return best.map { ($0.spelling, $0.length) }
    }

    private static func tolerance(for key: [Character]) -> Double {
        Double(key.count) * tolerancePerSound
    }

    /// Same first sound and same last consonant: mishearings keep a word's outline.
    private static func sameEdges(_ a: [Character], _ b: [Character]) -> Bool {
        a.first == b.first && a.last(where: { !isVowel($0) }) == b.last(where: { !isVowel($0) })
    }

    /// Edit distance where vowel edits cost half: vowels are what speech models (and romanised Hindi)
    /// vary most.
    static func soundDistance(_ a: [Character], _ b: [Character]) -> Double {
        func cost(_ c: Character) -> Double { isVowel(c) ? 0.5 : 1 }
        var previous = [0.0] + b.indices.map { _ in 0.0 }
        for j in b.indices { previous[j + 1] = previous[j] + cost(b[j]) }
        for i in a.indices {
            var current = [previous[0] + cost(a[i])]
            for j in b.indices {
                let substitution: Double = a[i] == b[j] ? 0 : (isVowel(a[i]) && isVowel(b[j]) ? 0.5 : 1)
                current.append(min(previous[j] + substitution, previous[j + 1] + cost(a[i]), current[j] + cost(b[j])))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Sound keys

    /// A spelling reduced to how it sounds: one letter per sound, spelling variants merged (ph/f, c/k/s,
    /// q/k, w/v, z/j, d/t, ee/i, oo/u, y/i), h after a consonant dropped (kh, gh, sh, th), doubles collapsed.
    static func soundKey(_ spelling: String) -> [Character] {
        let letters = Array(spelling.lowercased().filter { $0.isASCII && $0.isLetter })
        var sounds: [Character] = []
        var i = 0
        while i < letters.count {
            let c = letters[i]
            let next = i + 1 < letters.count ? letters[i + 1] : nil
            switch (c, next) {
            case ("p", "h"): sounds.append("f"); i += 1
            case ("c", "k"): sounds.append("k"); i += 1
            case ("e", "e"): sounds.append("i"); i += 1
            case ("o", "o"): sounds.append("u"); i += 1
            case ("c", let n?) where "eiy".contains(n): sounds.append("s")
            case ("c", _), ("q", _): sounds.append("k")
            case ("x", _): sounds.append(contentsOf: ["k", "s"])
            case ("w", _): sounds.append("v")
            case ("z", _): sounds.append("j")
            case ("d", _): sounds.append("t")
            case ("y", _): sounds.append("i")
            case ("h", _) where sounds.last.map { !isVowel($0) } ?? false: break
            default: sounds.append(c)
            }
            i += 1
        }
        return sounds.reduce(into: []) { key, sound in
            if key.last != sound { key.append(sound) }
        }
    }

    private static func isVowel(_ c: Character) -> Bool { "aeiou".contains(c) }

    /// Words with their positions: letters and digits, plus inner dots, apostrophes and hyphens ("Next.js").
    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            let next = text.index(after: index)
            // Dots, apostrophes and hyphens inside a word belong to it ("Next.js", "Gurjeet's").
            let joinsWord = ".'’-".contains(c) && start != nil && next < text.endIndex && (text[next].isLetter || text[next].isNumber)
            if c.isLetter || c.isNumber || joinsWord {
                if start == nil { start = index }
            } else if let wordStart = start {
                words.append(word(text, wordStart..<index))
                start = nil
            }
            index = next
        }
        if let wordStart = start { words.append(word(text, wordStart..<text.endIndex)) }
        return words
    }

    /// A possessive is matched without its 's ("Gurjit's" → "Gurjeet's").
    private static func word(_ text: String, _ range: Range<String.Index>) -> Word {
        var range = range
        let lower = text[range].lowercased()
        if text[range].count > 2, lower.hasSuffix("'s") || lower.hasSuffix("’s") {
            range = range.lowerBound..<text.index(range.upperBound, offsetBy: -2)
        }
        return Word(range: range, key: soundKey(String(text[range])))
    }
}
