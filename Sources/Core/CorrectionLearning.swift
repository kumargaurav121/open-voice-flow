import Foundation

/// A field's text and where its cursor is (UTF-16), as Accessibility reports it.
public struct FieldText: Equatable, Sendable {
    public var text: String
    public var cursor: Int

    public init(text: String, cursor: Int) {
        self.text = text
        self.cursor = cursor
    }
}

/// The field a dictation was just pasted into, read again to learn from the user's fixes (v2 ticket 15).
/// Provided by the Insertion package (Accessibility).
@MainActor
public protocol PastedField: AnyObject {
    /// Starts following the focused field: its text now, or nil when it can't be read (none, or a password field).
    func follow() async -> FieldText?
    /// The followed field's text now; nil once focus has left it, or it can't be read.
    func read() async -> FieldText?
}

/// Learning from the user's fixes to a pasted dictation: the field to watch, whether learning is on, and where the
/// fixes go (the dictionary, which returns any words it now suggests).
public struct CorrectionLearning {
    public var field: PastedField
    public var isOn: () -> Bool
    public var learn: ([WordFix]) -> [String]
    /// How long the field is watched after a paste (SPEC: 30 s), and how often it's read.
    public var window: TimeInterval
    public var interval: TimeInterval

    public init(field: PastedField, isOn: @escaping () -> Bool, learn: @escaping ([WordFix]) -> [String],
                window: TimeInterval = 30, interval: TimeInterval = 0.5) {
        self.field = field
        self.isOn = isOn
        self.learn = learn
        self.window = window
        self.interval = interval
    }
}

/// Watches a pasted dictation for the user's one-word fixes.
enum CorrectionWatch {
    /// How long a paste may take to show in its field: a ⌘V is applied by the app a moment after it's sent.
    static let pasteLanding: TimeInterval = 1

    /// The fixes the field showed for `pasted`, read until `window` ends, focus leaves the field, or the task is
    /// cancelled (a new dictation). A fix counts only once two reads in a row show it, so a word half typed doesn't.
    @MainActor
    static func watch(_ pasted: String, in field: PastedField, window: TimeInterval,
                      interval: TimeInterval) async -> [WordFix] {
        guard let paste = await landed(pasted, in: field, interval: interval) else { return [] }
        let deadline = ContinuousClock.now + .seconds(window)
        var last: [WordFix]?
        var settled: [WordFix] = []
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let now = await field.read() else { break }
            let fixes = paste.fixes(in: now.text)
            if let fixes, fixes == last { settled = fixes }
            last = fixes
        }
        return settled
    }

    /// Where the paste landed in the field, read until it shows (`pasteLanding`); nil if it never does there.
    @MainActor
    private static func landed(_ pasted: String, in field: PastedField, interval: TimeInterval) async -> Paste? {
        var text = await field.follow()
        let deadline = ContinuousClock.now + .seconds(pasteLanding)
        while let current = text {
            if let paste = Paste(pasted, in: current) { return paste }
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return nil }
            try? await Task.sleep(for: .seconds(min(interval, 0.1)))
            text = await field.read()
        }
        return nil
    }

    /// A dictation where it landed: the text before and after it in the field, and its words.
    struct Paste {
        let before: String
        let after: String
        let words: [String]

        /// Nil unless the pasted text ends at the field's cursor, as a paste leaves it.
        init?(_ pasted: String, in field: FieldText) {
            let utf16 = field.text.utf16
            let length = pasted.utf16.count
            guard field.cursor >= length, field.cursor <= utf16.count,
                  let start = utf16.index(utf16.startIndex, offsetBy: field.cursor - length, limitedBy: utf16.endIndex),
                  let end = utf16.index(utf16.startIndex, offsetBy: field.cursor, limitedBy: utf16.endIndex),
                  String(field.text[start..<end]) == pasted
            else { return nil }
            before = String(field.text[..<start])
            after = String(field.text[end...])
            words = Self.words(pasted)
        }

        /// The fixes in the field's text now, or nil when the text around the paste changed or the paste changed in
        /// other ways (words added or removed inside it, two for one).
        func fixes(in text: String) -> [WordFix]? {
            guard text.count >= before.count + after.count, text.hasPrefix(before), text.hasSuffix(after) else {
                return nil
            }
            return oneWordFixes(from: words, to: Self.words(String(text.dropFirst(before.count).dropLast(after.count))))
        }

        static func words(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map(String.init)
        }
    }

    /// One-word replacements between the pasted words and the same stretch now, compared without the punctuation
    /// around them ("supabass," is "supabass"). Nil when anything else changed, except words typed after its last
    /// word, kept: a last word followed by others could as well have been split in two ("Supa base").
    static func oneWordFixes(from pasted: [String], to now: [String]) -> [WordFix]? {
        let old = pasted.map(core), new = now.map(core)
        var fixes: [WordFix] = []
        // Word pairs kept, in order (a longest common subsequence), then what lies between them.
        let kept = keptPairs(old, new)
        var (i, j) = (0, 0)
        for (keptOld, keptNew) in kept + [(old.count, new.count)] {
            let removed = keptOld - i, added = keptNew - j
            let atEnd = keptOld == old.count
            switch (removed, added) {
            case (0, 0): break
            case (0, _) where atEnd: break  // typed after the paste
            case (1, 1) where !old[i].isEmpty && !new[j].isEmpty: fixes.append(WordFix(from: old[i], to: new[j]))
            case (1, 1): break  // a dash or other mark on its own: not a word
            default: return nil
            }
            (i, j) = (keptOld + 1, keptNew + 1)
        }
        return fixes
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// The index pairs of a longest common subsequence of two word lists.
    private static func keptPairs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var (i, j) = (0, 0)
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                (i, j) = (i + 1, j + 1)
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
