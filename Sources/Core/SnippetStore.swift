import Foundation
import Observation

/// The user's snippets (Settings → Snippets). Kept in local preferences.
@MainActor
@Observable
public final class SnippetStore {
    static let key = "snippets"

    public private(set) var snippets: [Snippet] {
        didSet {
            if let data = try? JSONEncoder().encode(snippets) { defaults.set(data, forKey: Self.key) }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snippets = []
        // Each one on its own, so one unreadable snippet doesn't lose the rest.
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Lenient].self, from: $0) }
        for snippet in saved ?? [] { snippet.value.map { insert($0) } }
    }

    /// A cue as saved: trimmed, with an English letter or a digit to say, fillers aside (transcripts are always in
    /// English letters, and fillers never decide a match). Nil if it can't be one.
    nonisolated public static func normalizedCue(_ cue: String) -> String? {
        let cue = cue.trimmingCharacters(in: .whitespacesAndNewlines)
        return RulesCleanup.clean(cue).contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) ? cue : nil
    }

    /// A text as saved, and so as pasted: trimmed, like every dictation. Nil if blank.
    nonisolated public static func normalizedText(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Adds a snippet; false if the cue or text is blank (see `normalizedCue`) or another cue is said the same way.
    @discardableResult
    public func add(cue: String, text: String) -> Bool {
        insert(Snippet(cue: cue, text: text))
    }

    /// Changes a snippet in place; false as for `add`.
    @discardableResult
    public func update(_ id: Snippet.ID, cue: String, text: String) -> Bool {
        guard let index = snippets.firstIndex(where: { $0.id == id }),
              let snippet = valid(Snippet(id: id, cue: cue, text: text))
        else { return false }
        snippets[index] = snippet
        return true
    }

    public func remove(_ id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    @discardableResult
    private func insert(_ snippet: Snippet) -> Bool {
        guard let snippet = valid(snippet) else { return false }
        snippets.append(snippet)
        return true
    }

    /// The snippet as saved (`normalizedCue`, `normalizedText`), or nil if either is blank or another snippet's
    /// cue is said the same way.
    private func valid(_ snippet: Snippet) -> Snippet? {
        guard let cue = Self.normalizedCue(snippet.cue), let text = Self.normalizedText(snippet.text),
              !snippets.contains(where: { $0.id != snippet.id && Snippet.sameCue($0.cue, cue) })
        else { return nil }
        return Snippet(id: snippet.id, cue: cue, text: text)
    }

    /// A saved snippet, or nil if it can't be read.
    private struct Lenient: Decodable {
        let value: Snippet?
        init(from decoder: Decoder) throws { value = try? Snippet(from: decoder) }
    }
}
