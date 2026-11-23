import Foundation

/// The kind of app a dictation goes into, which picks its style (v2 ticket 13).
public enum AppCategory: String, CaseIterable, Sendable {
    /// Casual: no full stop at the end of a short message.
    case chat
    /// Laid out: the greeting and sign-off on lines of their own, and paragraphs from the AI.
    case email
    /// Exactly as spoken: no cleanup at all (a "cleaned" shell command is a broken one).
    case code
    /// Everything else: formatted, with no style of its own.
    case other

    /// Bundle IDs from the apps on the user's Mac and Homebrew's cask definitions.
    static let chatApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.microsoft.teams2" /* Teams */, "com.microsoft.teams" /* classic Teams */,
        "com.apple.MobileSMS" /* Messages */, "net.whatsapp.WhatsApp", "com.hnc.Discord",
        "ru.keepcoder.Telegram", "com.tdesktop.Telegram" /* Telegram Desktop */,
    ]

    static let emailApps: Set<String> = ["com.apple.mail", "com.microsoft.Outlook"]

    /// Browsers, whose front window's title names the page in them: Dia, Chrome, Arc, Brave, Safari, Edge.
    static let browsers: Set<String> = [
        "company.thebrowser.dia", "com.google.Chrome", "company.thebrowser.Browser" /* Arc */, "com.brave.Browser",
        "com.apple.Safari", "com.microsoft.edgemac",
    ]

    /// The category of the app with this bundle ID (nil: no app in front). In a browser, mail on the web is email,
    /// by the front window's title (`windowTitle`, read only for a browser).
    public init(bundleID: String?, windowTitle: () -> String?) {
        guard let bundleID else { self = .other; return }
        if Self.chatApps.contains(bundleID) {
            self = .chat
        } else if Self.emailApps.contains(bundleID) {
            self = .email
        } else if CodeContext.isCodeEditor(bundleID: bundleID) {
            self = .code
        } else if Self.browsers.contains(bundleID), windowTitle().map(Self.isWebMail) == true {
            self = .email
        } else {
            self = .other
        }
    }

    /// A page of Gmail ("Inbox (3) - kumar@example.com - Gmail"; a work account's ends in its company's name,
    /// "… - Acme Mail") or Outlook on the web's mail ("Mail - Kumar Gaurav - Outlook"; its calendar's starts
    /// "Calendar"). A browser may add its profile.
    static func isWebMail(_ title: String) -> Bool {
        let parts = title.components(separatedBy: " - ")
        return parts.first == "Mail" && parts.contains("Outlook") || zip(parts, parts.dropFirst()).contains { account, site in
            isAddress(account) && (site == "Gmail" || site.hasSuffix(" Mail"))
        }
    }

    /// A window title's shape for the log, never its text: its parts' lengths and which one is an address.
    static func shape(ofTitle title: String?) -> String {
        guard let title else { return "title unreadable" }
        let parts = title.components(separatedBy: " - ")
        let address = parts.firstIndex(where: isAddress).map { "an address is part \($0 + 1)" } ?? "no address"
        return "title parts of \(parts.map { String($0.count) }.joined(separator: ", ")) characters; \(address)"
    }

    private static func isAddress(_ part: String) -> Bool {
        part.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}

/// Each category's style, the last formatting step, after lists.
enum AppStyle {
    /// - Parameter saidFullStop: the text ends with a full stop the speaker said, which a chat message keeps.
    static func apply(_ text: String, for category: AppCategory, saidFullStop: Bool) -> String {
        // A break said at the very start or end isn't pasted (every transcript is trimmed), so it can't hide the end
        // or the greeting.
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch category {
        case .chat: saidFullStop ? text : casual(text)
        case .email: email(text)
        case .code, .other: text
        }
    }

    // MARK: Chat

    /// A chat message of up to this many sentences loses its final full stop.
    static let shortMessage = 2

    /// A short chat message without the final full stop the speech model gave it; question and exclamation marks
    /// stay, and so does a full stop said out loud (`apply`). Longer messages
    /// and lists keep theirs (a list's items all have one or none), and so does an ellipsis or an abbreviation
    /// ("p.m.").
    static func casual(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).map(Word.init)
        guard let last = words.last, last.trail == ".", !isAbbreviation(last),
              text.range(of: listLine, options: .regularExpression) == nil,
              words.filter({ $0.trail.contains { ".?!".contains($0) } && !isAbbreviation($0) }).count <= shortMessage
        else { return text }
        return String(text.dropLast())
    }

    /// A numbered list's line ("1. Milk").
    private static let listLine = #"(?m)^\d+[.)] "#
    /// Titles and other one-part abbreviations, whose full stop doesn't end a sentence.
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "jr", "sr", "vs", "etc"]

    /// "p.m.", "e.g.", "U.S.", "Mr.": not a sentence's end ("2.5." and "example.com." are).
    private static func isAbbreviation(_ word: Word) -> Bool {
        abbreviations.contains(word.name) || word.core.range(of: #"^(\p{L}\.)+\p{L}$"#, options: .regularExpression) != nil
    }

    // MARK: Email

    /// A greeting opening an email ("Hi Mark,", "Good morning, team,", "Dear Mr. Sharma,"), up to its comma or the
    /// full stop a speech model may give it after a pause ("Hi Mark."; a title's doesn't count), then either the
    /// text after it or a line break.
    private static let greeting = #"^(?i:hi|hello|hey|dear|good morning|good afternoon|good evening|namaste)"#
        + #"(?:,? +\#(greeted)(?: +\#(greeted)){0,3})?(?:,|(?<!\#(abbreviated))\.)(?=[ \t]+\S|[ \t]*\n)"#
    /// Who a greeting greets: a name, a title, or a group ("team"), and "and" or "&" between them.
    private static let greeted = #"(?:\#(abbreviated)\.|\p{Lu}[\p{L}'-]*|&|(?i:and|team|all|everyone|everybody|there|guys|folks|both))"#
    /// A title or an initial before a name, whose full stop is part of the greeting ("Dear Prof. Rao,", "Hi J.
    /// Smith,").
    private static let abbreviated = #"\b(?:Mr|Mrs|Ms|Dr|Prof|St|\p{Lu})"#

    /// A sign-off ending an email, after a sentence ("… Friday. Thanks, Kumar", "Best regards, Kumar Gaurav."),
    /// and the name that may follow it. Longer phrases first: "Best Regards" isn't "Best" signed "Regards".
    private static let signOff = try! NSRegularExpression(pattern:
        #"(?<=[.!?\n])[ \t]*(?<phrase>(?i:thanks again|many thanks|thank you|thanks|best regards|kind regards|"#
        + #"warm regards|regards|best|yours sincerely|sincerely|cheers|take care))"#
        + #"(?:[,.!]?[ \t]+(?<name>\p{Lu}[\p{L}'-]*(?: \p{Lu}[\p{L}'-]*){0,2}))?[,.!]?$"#)

    /// An email with its greeting on a line of its own, then a blank line, and its sign-off after a blank line,
    /// the sender's name on the line below it. Breaks the speaker or the AI already put there stay.
    static func email(_ text: String) -> String {
        var text = text
        var greetedNames: Set<Substring> = []
        if let opening = text.range(of: greeting, options: .regularExpression) {
            greetedNames = Set(text[opening].split { !$0.isLetter })
            let rest = text[opening.upperBound...].drop { $0 == " " || $0 == "\t" }
            // Already on a line of its own (said, or the AI's): its breaks stay, and the text after it starts with a
            // capital, which the AI may leave out.
            let breaks = rest.first == "\n" ? rest.prefix(while: \.isWhitespace) : "\n\n"
            // It ends in a comma, as a greeting does, whatever the speech model gave it.
            text = text[opening].dropLast() + "," + breaks + String(rest.drop(while: \.isWhitespace)).capitalizedFirst
        }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = signOff.firstMatch(in: text, range: whole), let found = Range(match.range, in: text),
              let phrase = Range(match.range(withName: "phrase"), in: text)
        else { return text }
        let before = text[..<found.lowerBound]
        guard !before.allSatisfy(\.isWhitespace) else { return text }  // nothing to sign off
        var closing = text[found].trimmingCharacters(in: .whitespaces)
        // A name the email greets is its reader's ("Thanks, Priya!"): it stays with the thanks.
        if let name = Range(match.range(withName: "name"), in: text),
           !greetedNames.contains(text[name].split(separator: " ")[0]) {
            closing = text[phrase] + ",\n" + text[name]
        }
        // A sign-off already on a line of its own (said, or the AI's) keeps the break before it.
        return (before.last == "\n" ? String(before) : before.trimmingCharacters(in: .whitespaces) + "\n\n") + closing
    }
}
