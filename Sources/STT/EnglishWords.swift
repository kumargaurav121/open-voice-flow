import AppKit

/// Ordinary English words, per macOS's spell checker; the dictionary step never respells them.
@MainActor
public enum EnglishWords {
    /// Checked lowercased against plain English: the system's default (en_IN here) and capitalised
    /// forms accept names like "Gurjit" and "Rohan", which are exactly what the dictionary should fix.
    public static func contains(_ word: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word.lowercased(), startingAt: 0, language: "en", wrap: false,
                                            inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
}
