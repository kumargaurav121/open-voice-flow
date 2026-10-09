import Foundation
import Observation

/// The user's custom dictionary: names and terms to spell their way. Kept in local preferences.
@MainActor
@Observable
public final class DictionaryStore {
    static let key = "dictionary"

    public private(set) var terms: [String] {
        didSet { defaults.set(terms, forKey: Self.key) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terms = []
        for term in defaults.stringArray(forKey: Self.key) ?? [] { add(term) }
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
}
