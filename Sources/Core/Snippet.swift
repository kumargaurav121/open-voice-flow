import Foundation

/// A saved snippet: saying its cue as the whole dictation pastes its text exactly as saved (v2 ticket 14).
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// What to say, such as "my address".
    public var cue: String
    /// What's pasted, as saved.
    public var text: String

    public init(id: UUID = UUID(), cue: String, text: String) {
        self.id = id
        self.cue = cue
        self.text = text
    }

    /// The snippet whose cue, as typed, is the whole of `transcript`, whatever its case, punctuation and fillers; a
    /// cue typed with digits matches them said as words (the user's choice, 2026-11-23). What was said is tried as
    /// said first, then without its fillers, so "ER diagram" is that cue's, not "diagram"'s. Nil when none is.
    static func matching(_ transcript: String, in snippets: [Snippet]) -> Snippet? {
        for said in [comparable(transcript), comparable(RulesCleanup.clean(transcript))] where !said.isEmpty {
            if let snippet = snippets.first(where: { comparable($0.cue) == said }) { return snippet }
        }
        return nil
    }

    /// Whether two cues are said the same way, so one dictation would match both.
    static func sameCue(_ cue: String, _ other: String) -> Bool {
        comparable(cue) == comparable(other)
    }

    /// Its words in lowercase letters and digits: an apostrophe joins ("what's" is "whats"), other punctuation
    /// splits ("follow-up" is "follow up"), accents go ("café" is "cafe"), and each digit is its word, so "911", "15"
    /// and "1984" match however they're said ("nine one one", "fifteen", which the rules cleanup writes as 15).
    static func comparable(_ phrase: String) -> String {
        phrase.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: #"['’]"#, with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            .map { word in word.allSatisfy(\.isASCII) && word.allSatisfy(\.isNumber)
                ? word.map { digitWords[$0]! }.joined(separator: " ") : word }
            .joined(separator: " ")
    }

    private static let digitWords: [Character: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six", "7": "seven",
        "8": "eight", "9": "nine",
    ]
}
