import Foundation

/// Spoken punctuation and line breaks (v2 ticket 09): "comma", "full stop", "question mark", "new line",
/// "new paragraph" and the like become the mark or the break. Dictation only, after the rules cleanup.
/// - After an article or determiner they stay words: "remove the comma", "a new line of laptops", "yah comma".
/// - "Period", "colon" and "dash" are everyday words too ("the reporting period", "colon cancer"), so they count
///   only when the speech model set them off with its own punctuation on both sides, or before them at the
///   end ("ship it Friday, period.").
/// - Models set the commands off with their own punctuation ("Rohan, comma, new line, thanks"): a spoken mark
///   takes the place of the model's mark before it, a break keeps it, and the command's own is dropped.
/// - The word after a spoken full stop, question or exclamation mark, or a break, starts with a capital.
enum SpokenPunctuation {
    /// What a spoken "dash" writes: a hyphen with spaces, as typed on a keyboard.
    static let dash = " - "

    static func apply(_ text: String) -> String {
        render(pieces(text))
    }

    /// Whether the text ends with a full stop the speaker said ("see you at five full stop", breaks after it
    /// aside), not one the speech model wrote.
    static func endsWithSpokenFullStop(_ text: String) -> Bool {
        let last = pieces(text).last { if case .word = $0 { true } else { false } }
        guard case .word(let word)? = last else { return false }
        return word.spoken.hasSuffix(".")
    }

    private static func pieces(_ text: String) -> [Piece] {
        let words = split(text)
        var output: [Piece] = []
        var capitaliseNext = false
        var index = 0
        while index < words.count {
            guard let (command, end) = spokenCommand(at: index, in: words), write(command, into: &output) else {
                output.append(.word(written(words[index], capitalised: capitaliseNext)))
                capitaliseNext = false
                index += 1
                continue
            }
            switch command {
            case .mark(let mark): capitaliseNext = ".?!".contains(mark)
            case .lineBreak: capitaliseNext = true
            case .dash: capitaliseNext = false
            }
            index = end
        }
        return output
    }

    // MARK: Commands

    enum Command: Equatable {
        case mark(String), lineBreak(String), dash
    }

    /// Each command's words, longest first; `everyday` words need the model's punctuation around them.
    private static let vocabulary: [(words: [String], command: Command, everyday: Bool)] = [
        (["full", "stop"], .mark("."), false),
        (["question", "mark"], .mark("?"), false),
        (["exclamation", "mark"], .mark("!"), false),
        (["exclamation", "point"], .mark("!"), false),
        (["semi", "colon"], .mark(";"), false),
        (["new", "line"], .lineBreak("\n"), false),
        (["next", "line"], .lineBreak("\n"), false),
        (["new", "paragraph"], .lineBreak("\n\n"), false),
        (["comma"], .mark(","), false),
        (["full-stop"], .mark("."), false),
        (["semicolon"], .mark(";"), false),
        (["semi-colon"], .mark(";"), false),
        (["newline"], .lineBreak("\n"), false),
        (["period"], .mark("."), true),
        (["colon"], .mark(":"), true),
        (["dash"], .dash, true),
    ]

    /// Before one of these, a command word is the thing itself: "the comma", "a new line", "this period", and
    /// Hindi's "yah comma", "ek new line" (as the Hinglish model writes them).
    private static let determiners: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their",
        "each", "every", "any", "some", "no", "another", "which", "what", "whose",
        "yah", "yeh", "ye", "vah", "woh", "wo", "ek",
    ]

    /// The command spoken at `index`, and the index after it.
    private static func spokenCommand(at index: Int, in words: [Word]) -> (Command, Int)? {
        let previous = index > 0 ? words[index - 1] : nil
        if let previous, previous.trail.isEmpty, determiners.contains(previous.name) { return nil }
        for entry in vocabulary {
            let end = index + entry.words.count
            guard end <= words.count else { continue }
            let spoken = words[index..<end]
            // Only the last word may carry punctuation (the model's, dropped); none may open with any.
            guard spoken.map(\.name) == entry.words, spoken.allSatisfy(\.lead.isEmpty),
                  spoken.dropLast().allSatisfy(\.trail.isEmpty)
            else { continue }
            if entry.everyday, previous?.trail.isEmpty ?? true || end < words.count && words[end - 1].trail.isEmpty {
                return nil
            }
            return (entry.command, end)
        }
        return nil
    }

    // MARK: Writing

    private enum Piece {
        case word(Written), lineBreak(String), dash
    }

    private struct Written {
        var body: String
        /// The model's punctuation after the word.
        var trail: String
        /// Marks the speaker said after it.
        var spoken = ""
    }

    /// Adds a command to the output; false when it can't apply (a mark with no word before it).
    private static func write(_ command: Command, into output: inout [Piece]) -> Bool {
        if case .lineBreak(let lineBreak) = command {
            output.append(.lineBreak(lineBreak))
            return true
        }
        guard case .word(var last)? = output.last else { return false }
        // The spoken mark replaces the model's ("Friday. Exclamation mark" → "Friday!").
        if last.spoken.isEmpty, last.trail.allSatisfy({ ",.;:?!".contains($0) }) { last.trail = "" }
        if case .mark(let mark) = command { last.spoken += mark }
        output[output.count - 1] = .word(last)
        if command == .dash { output.append(.dash) }
        return true
    }

    private static func written(_ word: Word, capitalised: Bool) -> Written {
        var body = String(word.lead + word.core)
        if capitalised, let first = body.firstIndex(where: \.isLetter) {
            body.replaceSubrange(first...first, with: body[first].uppercased())
        }
        return Written(body: body, trail: String(word.trail))
    }

    private static func render(_ output: [Piece]) -> String {
        var text = ""
        var lineStart = true
        for piece in output {
            switch piece {
            case .word(let word):
                text += (lineStart ? "" : " ") + word.body + word.trail + word.spoken
                lineStart = false
            case .lineBreak(let lineBreak):
                text += lineBreak
                lineStart = true
            case .dash:
                text += dash.dropLast()  // the next word adds the space
                lineStart = false
            }
        }
        return text
    }

    /// The text's words. A comma glued to a command ("Rohan,comma", as the Hinglish model wrote eval item 42)
    /// is split off.
    private static func split(_ text: String) -> [Word] {
        text.split(separator: " ").flatMap { piece -> [Word] in
            if let comma = piece.firstIndex(of: ","), piece.index(after: comma) < piece.endIndex {
                let rest = piece[piece.index(after: comma)...]
                if vocabulary.contains(where: { $0.words.first == Word(rest).name }) {
                    return [Word(piece[...comma]), Word(rest)]
                }
            }
            return [Word(piece)]
        }
    }
}
