import Foundation

/// What a spoken command asks for. v1 knows one action (SPEC §4.3).
public enum CommandIntent: Equatable, Sendable {
    /// `to` is the name as spoken; resolving it to a person is the adapter's job.
    case sendMessage(app: String, to: String, text: String)

    /// How the notch and history show it: `→ Slack · Gurjeet · "I'll be late"`.
    public var summary: String {
        switch self {
        case .sendMessage(let app, let to, let text): "→ \(app.capitalizedFirst) · \(to) · \"\(text)\""
        }
    }

    /// The message to send (what goes on the clipboard until the adapter sends it).
    public var messageText: String {
        switch self {
        case .sendMessage(_, _, let text): text
        }
    }

    public static let unknownSummary = "Can't do that yet"
}

/// Asks a language model to turn a command into the JSON in `CommandPrompt`; provided by the LLM package.
@MainActor
public protocol CommandModel: AnyObject {
    func reply(to command: String, instructions: String) async throws -> String
}

/// Understands a command: the direct phrasings by rule (instant and exact), anything else by the local
/// model, whose reply must pass `CommandSchema`. No model, a failure or an invalid reply means unknown.
@MainActor
public final class CommandParser {
    private let model: () -> CommandModel?

    private let log: (String) -> Void

    public init(model: @escaping () -> CommandModel?, log: @escaping (String) -> Void = { _ in }) {
        self.model = model
        self.log = log
    }

    public func parse(_ command: String) async -> CommandIntent? {
        if let intent = CommandRules.parse(command) { return intent }
        guard let model = model() else {
            log("No local model for commands; not understood")
            return nil
        }
        let reply: String
        do {
            reply = try await model.reply(to: command, instructions: CommandPrompt.instructions)
        } catch {
            log("Command model failed (\(logSafe(error)))")
            return nil
        }
        guard case .sendMessage(let app, let spokenTo, let text)? = CommandSchema.intent(from: reply) else { return nil }
        let to = CommandRules.withoutInstructionWords(spokenTo)
        // The model may only name someone the speaker named (no invented or injected recipients), and its
        // message gets the same text rules as dictation: English letters, tidy spacing and capitals.
        guard CommandRules.mentions(to, in: command) else {
            log("Command model named someone who wasn't mentioned; not understood")
            return nil
        }
        return .sendMessage(app: app, to: to, text: RulesCleanup.clean(LatinScriptSpeechToText.latin(text)))
    }
}

/// Direct messages, where the text is exactly what was said after the keyword:
/// "Message Gurjeet saying …", "Send a message to Priya on Slack: …", "Gurjeet ko message karo ki …".
/// Reported speech ("Tell Rohan he can merge", "Priya ko bolo ki … jaaye") isn't matched: turning it
/// into direct speech ("you can merge", "… jao") is the model's job.
public enum CommandRules {
    private static let name = #"(?<to>[\p{L}][\p{L}'’.-]*(?:\s+[\p{L}][\p{L}'’.-]*){0,2}?)"#
    private static let patterns: [NSRegularExpression] = [
        // "… saying/that …", "…: …", or "… on Slack, …" (a bare comma is ambiguous: "Message Priya, John saying hi").
        #"^(?:send\s+)?(?:a\s+)?message\s+(?:to\s+)?\#(name)(?:(?:\s+on\s+slack)?(?:\s+(?:saying|that)\b|\s*:)|\s+on\s+slack\s*,)\s*(?<text>.+)$"#,
        #"^(?:slack\s+(?:pe|par)\s+)?\#(name)\s+ko\s+(?:slack\s+(?:pe|par)\s+)?message\s+(?:karo|kar\s+do|bhejo|bhej\s+do)(?:\s+(?:ki|ke)\b|\s*,)?\s*(?<text>.+)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// Apps the user might name that v1 can't message through.
    private static let otherApps = ["whatsapp", "telegram", "teams", "imessage", "messages", "sms", "email", "mail", "discord", "signal"]
    private static let keywords: Set<String> = ["saying", "that", "to", "ki", "ke", "slack"]
    /// Words that make a "name" a group: v1 messages one person.
    private static let groupWords: Set<String> = ["and", "team", "everyone", "all", "group", "channel", "guys", "folks", "on"]
    private static let leadingSlack = try! NSRegularExpression(pattern: #"^on\s+slack\s*,?\s*"#, options: .caseInsensitive)
    private static let trailingSlack = try! NSRegularExpression(pattern: #"\s+on\s+slack\s*([.!?]?)$"#, options: .caseInsensitive)

    public static func parse(_ command: String) -> CommandIntent? {
        var command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        command = leadingSlack.stringByReplacingMatches(in: command, range: NSRange(command.startIndex..., in: command), withTemplate: "")
        let range = NSRange(command.startIndex..., in: command)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: command, range: range),
                  let toRange = Range(match.range(withName: "to"), in: command),
                  let textRange = Range(match.range(withName: "text"), in: command)
            else { continue }
            let to = String(command[toRange])
            // Only the part before the message decides the app: "saying check the email" is still Slack.
            let addressing = Set(words(in: String(command[..<textRange.lowerBound])))
            guard CommandSchema.isPlausibleName(to), !keywords.contains(to.lowercased()),
                  addressing.isDisjoint(with: otherApps), Set(words(in: to)).isDisjoint(with: groupWords)
            else { return nil }
            var text = String(command[textRange])
            text = trailingSlack.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " :,").union(.whitespaces))
            guard !text.isEmpty else { continue }
            return .sendMessage(app: "slack", to: to, text: text.capitalizedFirst)
        }
        return nil
    }

    /// Words of the instruction, not the name, that a model (or a misheard "Tell") can leave in front of it.
    private static let instructionWords: Set<String> = ["tell", "till", "ask", "message", "bolo", "to", "please"]

    /// "Till Rohan" → "Rohan"; a name that's nothing but such words is left alone (and fails the checks).
    static func withoutInstructionWords(_ name: String) -> String {
        let words = name.split(separator: " ")
        let kept = words.drop { instructionWords.contains($0.lowercased()) }
        return kept.isEmpty ? name : kept.joined(separator: " ")
    }

    /// Whether `name` was said in the command, as whole words.
    static func mentions(_ name: String, in command: String) -> Bool {
        let said = words(in: command)
        let wanted = words(in: name)
        guard !wanted.isEmpty, said.count >= wanted.count else { return false }
        return (0...(said.count - wanted.count)).contains { Array(said[$0..<$0 + wanted.count]) == wanted }
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }
}

/// Checks the model's reply: valid JSON of the one known shape, else unknown. Never trusts free text.
public enum CommandSchema {
    public static func intent(from reply: String) -> CommandIntent? {
        let text = ModelReply.strippingThinking(reply)
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close,
              let object = try? JSONSerialization.jsonObject(with: Data(text[open...close].utf8)) as? [String: Any],
              object["action"] as? String == "send_message",
              (object["app"] as? String)?.lowercased() == "slack",
              let to = (object["to"] as? String)?.trimmingCharacters(in: .whitespaces), isPlausibleName(to),
              let message = (object["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty
        else { return nil }
        return .sendMessage(app: "slack", to: to, text: message)
    }

    /// A name as spoken: one to three words, letters only, short.
    static func isPlausibleName(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        return (1...3).contains(words.count) && name.count <= 40
            && name.allSatisfy { $0.isLetter || " '’.-".contains($0) }
    }
}

/// What the local model is told when the rules don't recognise a command.
public enum CommandPrompt {
    public static let instructions = """
        You turn a spoken command into JSON. The only action is sending a Slack message. Reply with only \
        one JSON object, no other text:
        {"action": "send_message", "app": "slack", "to": "<the name exactly as spoken>", "text": "<the message>"}
        Rules for "text", the message the recipient will read:
        - Keep the speaker's language and words. Hinglish stays Hinglish in English letters; never translate.
        - Turn reported speech into direct speech addressed to the recipient: he/she/him/her meaning the \
        recipient become you/your; in Hindi, a request like "ko bolo ki … jaaye / kare / de" becomes "… jao / \
        karo / do".
        - Leave out the instruction itself ("tell", "ask", "bolo ki", "on Slack").
        "to" is only the person's name, as spoken, without words like tell or ask. If the command asks for \
        anything else, or names another app, reply {"action": "unknown"}.

        Examples (none of these people are real):
        Command: Tell Arjun the client call moved to four and he should join.
        {"action": "send_message", "app": "slack", "to": "Arjun", "text": "The client call moved to four, you should join."}
        Command: Neha ko bolo ki kal office jaldi aa jaaye.
        {"action": "send_message", "app": "slack", "to": "Neha", "text": "Kal office jaldi aa jao."}
        Command: Ask Kabir if he finished the report
        {"action": "send_message", "app": "slack", "to": "Kabir", "text": "Did you finish the report?"}
        Command: Kabir ko bolo ki report aaj shaam tak bhej de.
        {"action": "send_message", "app": "slack", "to": "Kabir", "text": "Report aaj shaam tak bhej do."}
        Command: Order a pizza for tonight.
        {"action": "unknown"}
        """
}

extension String {
    /// The first letter upper-cased, the rest untouched ("iPhone" stays, "hi there" → "Hi there").
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Model replies: Qwen3 may lead with a thinking block even when asked not to.
public enum ModelReply {
    public static func strippingThinking(_ reply: String) -> String {
        var text = reply.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }  // opening tag cut off
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
