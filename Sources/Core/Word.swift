import Foundation

/// One space-separated word of a text, and the punctuation around it (`SpokenNumbers`, `SpokenPunctuation`).
struct Word {
    let raw: String
    let lead: Substring
    let core: Substring
    let trail: Substring
    /// The word in lower case.
    let name: String
    /// Its parts between hyphens, in lower case ("twenty-five").
    let pieces: [String]

    init(_ raw: Substring) {
        self.raw = String(raw)
        let start = raw.firstIndex { $0.isLetter || $0.isNumber } ?? raw.endIndex
        let end = raw[start...].lastIndex { $0.isLetter || $0.isNumber }.map { raw.index(after: $0) } ?? start
        lead = raw[..<start]
        core = raw[start..<end]
        trail = raw[end...]
        name = core.lowercased()
        pieces = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    }

    var isBare: Bool { lead.isEmpty && trail.isEmpty }
}
