import Foundation

/// Picks who a spoken name means among an app's search results (Slack's ⌘K rows), by sound, so the name
/// as heard ("Gurjit") still finds the person ("Gurjeet Singh"). Strict by design: if more than one
/// person matches, it's ambiguous and nothing is sent.
public enum RecipientMatch {
    public enum Result: Equatable, Sendable {
        case found(String)
        case notFound
        case ambiguous([String])
    }

    /// One vowel's difference between first names (Gurjit/Gurjeet sound identical after normalising).
    static let tolerance = 0.5

    public static func resolve(_ spoken: String, among candidates: [String]) -> Result {
        let spokenWords = words(spoken)
        guard !spokenWords.isEmpty else { return .notFound }
        let matches = candidates.filter { candidate in
            // Channels and group conversations ("A, B") aren't one person.
            guard !candidate.hasPrefix("#"), !candidate.contains(",") else { return false }
            let name = words(candidate)
            guard name.count >= spokenWords.count else { return false }
            return zip(spokenWords, name).allSatisfy(sameName)
        }
        switch matches.count {
        case 0: return .notFound
        case 1: return .found(matches[0])
        default: return .ambiguous(matches)
        }
    }

    private static func sameName(_ spoken: String, _ name: String) -> Bool {
        let (a, b) = (DictionaryCorrection.soundKey(spoken), DictionaryCorrection.soundKey(name))
        // An empty key (no English letters) says nothing about the sound, so it can't match.
        return !a.isEmpty && !b.isEmpty && DictionaryCorrection.soundDistance(a, b) <= tolerance
    }

    /// The name's words, without Slack's extras: "(he/him)", "(you)", status text after a separator.
    private static func words(_ text: String) -> [String] {
        let name = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "·|•–—")).first ?? ""
        return name.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }).map(String.init)
    }
}
