import Testing
@testable import Core

struct CommandRulesTests {
    @Test(arguments: [
        ("Message Gurjeet saying I'll be late by 15 minutes.", "Gurjeet", "I'll be late by 15 minutes."),
        ("Send a message to Priya on Slack: can you share the deck?", "Priya", "Can you share the deck?"),
        ("Send a message to Priya on slack, can you share the deck?", "Priya", "Can you share the deck?"),
        ("Message Gurjeet Singh that the deploy is done", "Gurjeet Singh", "The deploy is done"),
        ("Gurjeet ko message karo ki main meeting mein hoon, baad mein call karta hoon.", "Gurjeet", "Main meeting mein hoon, baad mein call karta hoon."),
        ("Slack pe Rohan ko message bhejo ki build green hai", "Rohan", "Build green hai"),
        // Other apps or "Slack" inside the message are just words.
        ("Message Priya saying check the email thread", "Priya", "Check the email thread"),
        ("Message Priya saying hello on Slack", "Priya", "Hello"),
        ("On Slack, message Priya saying the deck is ready", "Priya", "The deck is ready"),
        ("Message R. K. Sharma saying hi", "R. K. Sharma", "Hi"),
    ])
    func directMessagesAreParsedWithoutTheModel(spoken: String, to: String, text: String) {
        #expect(CommandRules.parse(spoken) == .sendMessage(app: "slack", to: to, text: text))
    }

    @Test(arguments: [
        "Tell Rohan the build is green and he can merge now.",   // reported speech: the model rewrites it
        "Slack pe Priya ko bolo ki lunch ke liye ready ho jaaye.",
        "Book a flight to Delhi tomorrow.",
        "Send a message to Priya on WhatsApp saying hi",         // only Slack is supported
        "Message saying hello",                                   // nobody to send it to
        "Message the team saying standup is moved",                // a group, not a person
        "Message Rohan and Priya saying hi",
        "Message Priya, John saying hi",
    ])
    func everythingElseIsLeftToTheModel(spoken: String) {
        #expect(CommandRules.parse(spoken) == nil)
    }
}

struct CommandSchemaTests {
    @Test func aValidReplyBecomesTheIntent() {
        let reply = #"{"action": "send_message", "app": "Slack", "to": "Rohan", "text": "The build is green and you can merge now."}"#
        #expect(CommandSchema.intent(from: reply) == .sendMessage(app: "slack", to: "Rohan", text: "The build is green and you can merge now."))
    }

    @Test func toleratesCodeFencesAndThinking() {
        let reply = "<think>ok</think>\n```json\n{\"action\":\"send_message\",\"app\":\"slack\",\"to\":\"Priya\",\"text\":\"Lunch ke liye ready ho jao.\"}\n```"
        #expect(CommandSchema.intent(from: reply) == .sendMessage(app: "slack", to: "Priya", text: "Lunch ke liye ready ho jao."))
    }

    @Test(arguments: [
        #"{"action": "unknown"}"#,
        #"{"action": "send_message", "app": "whatsapp", "to": "Priya", "text": "hi"}"#,
        #"{"action": "send_message", "app": "slack", "to": "", "text": "hi"}"#,
        #"{"action": "send_message", "app": "slack", "to": "Priya"}"#,
        #"{"action": "send_message", "app": "slack", "to": "the person I met at the conference last week", "text": "hi"}"#,
        #"{"action": "book_flight", "to": "Delhi"}"#,
        "Sure! I'll send that message for you.",
        "",
    ])
    func anythingElseIsUnknown(reply: String) {
        #expect(CommandSchema.intent(from: reply) == nil)
    }
}

@MainActor
struct CommandParserTests {
    @Test func aRuleMatchNeverWakesTheModel() async {
        let model = FakeCommandModel(reply: "{}")
        let parser = CommandParser(model: { model })

        #expect(await parser.parse("Message Gurjeet saying hi") == .sendMessage(app: "slack", to: "Gurjeet", text: "Hi"))
        #expect(model.inputs.isEmpty)
    }

    @Test func otherCommandsGoToTheModelAndItsReplyIsChecked() async {
        let model = FakeCommandModel(reply: #"{"action":"send_message","app":"slack","to":"Rohan","text":"You can merge now."}"#)
        let parser = CommandParser(model: { model })

        #expect(await parser.parse("Tell Rohan he can merge now") == .sendMessage(app: "slack", to: "Rohan", text: "You can merge now."))
        #expect(model.inputs == ["Tell Rohan he can merge now"])
    }

    @Test func theModelCanOnlyNameSomeoneTheSpeakerNamed() async {
        // A hallucinated (or injected) recipient never reaches the adapter.
        let model = FakeCommandModel(reply: #"{"action":"send_message","app":"slack","to":"Mallory","text":"hi"}"#)

        #expect(await CommandParser(model: { model }).parse("Tell Rohan hi") == nil)
    }

    @Test func instructionWordsAreTrimmedFromTheModelsRecipient() async {
        // Speech-to-text heard "Tell" as "Till"; the model copied it into the name.
        let model = FakeCommandModel(reply: #"{"action":"send_message","app":"slack","to":"Till Rohan","text":"You can merge now."}"#)

        #expect(await CommandParser(model: { model }).parse("Till Rohan he can merge now")
                == .sendMessage(app: "slack", to: "Rohan", text: "You can merge now."))
    }

    @Test func theModelsMessageGetsTheDictationTextRules() async {
        // English letters, tidy spacing and capitals, like dictation.
        let model = FakeCommandModel(reply: #"{"action":"send_message","app":"slack","to":"Priya","text":"lunch  ke liye ready हो jao"}"#)

        #expect(await CommandParser(model: { model }).parse("Priya ko bolo ki lunch ke liye ready ho jaaye")
                == .sendMessage(app: "slack", to: "Priya", text: "Lunch ke liye ready ho jao"))
    }

    @Test func theModelsExamplesAreNotTheEvalCommands() {
        // Eval clips 24-28 must stay unseen, or the eval measures memory.
        for spoken in ["Tell Rohan the build is green", "Priya ko bolo ki lunch ke liye ready", "Message Gurjeet saying I'll be late",
                       "Send a message to Priya on Slack", "Gurjeet ko message karo ki main meeting mein hoon"] {
            #expect(!CommandPrompt.instructions.contains(spoken))
        }
    }

    @Test func aFailingOrMissingModelMeansUnknown() async {
        let failing = FakeCommandModel(reply: "", error: true)
        #expect(await CommandParser(model: { failing }).parse("Tell Rohan hi") == nil)
        #expect(await CommandParser(model: { nil }).parse("Tell Rohan hi") == nil)
    }
}

@MainActor
final class FakeCommandModel: CommandModel {
    let reply: String
    let error: Bool
    private(set) var inputs: [String] = []

    init(reply: String, error: Bool = false) {
        self.reply = reply
        self.error = error
    }

    func reply(to command: String, instructions: String) async throws -> String {
        inputs.append(command)
        if error { throw FakeModelError() }
        return reply
    }
}

private struct FakeModelError: Error {}
