import Foundation
import Observation

/// A one-word fix the user made to a pasted dictation ("gurujit" → "Gurjeet"), for learning (v2 ticket 15).
public struct WordFix: Codable, Equatable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// The user's custom dictionary: names and terms to spell their way. Kept in local preferences, with what it
/// learns from the user's fixes: the fixes of the last 7 days (word pairs only), words it suggests, and words
/// the user said not to suggest.
@MainActor
@Observable
public final class DictionaryStore {
    static let key = "dictionary"
    static let fixesKey = "dictionaryFixes"
    static let suggestionsKey = "dictionarySuggestions"
    static let dismissedKey = "dictionaryDismissed"
    /// The same fix twice within this long suggests its word (SPEC: 7 days).
    static let learningWindow: TimeInterval = 7 * 24 * 60 * 60

    public private(set) var terms: [String] {
        didSet { defaults.set(terms, forKey: Self.key) }
    }

    /// Words to offer for the dictionary, oldest first: each fixed the same way twice within 7 days.
    public private(set) var suggestions: [String] {
        didSet { defaults.set(suggestions, forKey: Self.suggestionsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    /// A spell check: a fix to ordinary English isn't a word for the dictionary (the user's choice).
    @ObservationIgnored private let isEnglishWord: (String) -> Bool

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
                isEnglishWord: @escaping (String) -> Bool = { _ in false }) {
        self.defaults = defaults
        self.now = now
        self.isEnglishWord = isEnglishWord
        terms = []
        suggestions = defaults.stringArray(forKey: Self.suggestionsKey) ?? []
        for term in defaults.stringArray(forKey: Self.key) ?? [] { add(term) }
        storedFixes = recentFixes  // fixes older than 7 days aren't kept
    }

    /// The one rule for what a term is: trimmed, and with at least one English letter (transcripts are
    /// always in English letters, so anything else could never match). Nil if it can't be a term.
    nonisolated public static func normalized(_ term: String) -> String? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.contains(where: { $0.isASCII && $0.isLetter }) ? term : nil
    }

    /// Adds a term; false if it isn't one (see `normalized`) or is already there (ignoring case).
    @discardableResult
    public func add(_ term: String) -> Bool {
        guard let term = Self.normalized(term), !contains(term) else { return false }
        terms.append(term)
        return true
    }

    /// Changes a term in place; false if the new spelling isn't a term or another term already has it.
    @discardableResult
    public func update(_ term: String, to newTerm: String) -> Bool {
        guard let index = terms.firstIndex(of: term), let newTerm = Self.normalized(newTerm),
              !contains(newTerm, except: term)
        else { return false }
        terms[index] = newTerm
        return true
    }

    public func remove(_ term: String) {
        terms.removeAll { $0 == term }
    }

    private func contains(_ term: String, except: String? = nil) -> Bool {
        terms.contains { $0 != except && $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    // MARK: Learning from fixes

    /// Learns from the user's fixes to a pasted dictation: a fix made the same way within the last 7 days
    /// (whatever the case of the word fixed) suggests its word, unless that word is ordinary English, already in
    /// the dictionary, suggested, or one the user said not to suggest. Returns the new suggestions.
    @discardableResult
    public func learn(_ fixes: [WordFix]) -> [String] {
        let earlier = recentFixes, now = now()
        var suggested: [String] = []
        let learnable = fixes.filter(isLearnable)
        for fix in learnable {
            // Made in an earlier dictation: the same word fixed twice in one isn't twice.
            let again = earlier.contains { $0.to == fix.to && $0.from.caseInsensitiveCompare(fix.from) == .orderedSame }
            if again, !isOffered(fix.to) {
                suggestions.append(fix.to)
                suggested.append(fix.to)
            }
        }
        storedFixes = earlier + learnable.map { StoredFix(from: $0.from, to: $0.to, date: now) }
        return suggested
    }

    /// Forgets every fix kept so far (learning switched off in Settings → Privacy).
    public func forgetFixes() {
        defaults.removeObject(forKey: Self.fixesKey)
    }

    /// Adds a suggested word to the dictionary.
    public func accept(_ word: String) {
        suggestions.removeAll { $0 == word }
        add(word)
    }

    /// Never suggests the word again.
    public func dismiss(_ word: String) {
        suggestions.removeAll { $0 == word }
        defaults.set(dismissed + [word], forKey: Self.dismissedKey)
    }

    /// A fix to a name or term: a new word the dictionary could hold, not ordinary English.
    private func isLearnable(_ fix: WordFix) -> Bool {
        fix.from != fix.to && Self.normalized(fix.to) == fix.to && !isEnglishWord(fix.to.lowercased())
    }

    /// Already a word, a suggestion, or one not to suggest.
    private func isOffered(_ word: String) -> Bool {
        contains(word) || (suggestions + dismissed).contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    private var dismissed: [String] { defaults.stringArray(forKey: Self.dismissedKey) ?? [] }

    /// A fix as kept: its two words and when, nothing else.
    private struct StoredFix: Codable {
        var from: String
        var to: String
        var date: Date
    }

    private var storedFixes: [StoredFix] {
        get { defaults.data(forKey: Self.fixesKey).flatMap { try? JSONDecoder().decode([StoredFix].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.fixesKey) }
    }

    /// The fixes of the last 7 days.
    private var recentFixes: [StoredFix] {
        let now = now()
        return storedFixes.filter { now.timeIntervalSince($0.date) <= Self.learningWindow }
    }
}
