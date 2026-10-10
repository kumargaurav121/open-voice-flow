import Testing
@testable import Core

@MainActor
struct CommandSessionTests {
    let recorder = FakeRecorder()
    let stt = FakeSpeechToText()
    let inserter = FakeInserter()
    let clock = FakeClock()
    let model = FakeCommandModel(reply: #"{"action":"unknown"}"#)

    func run(_ spoken: String, kind: SessionKind = .command) async -> (events: [SessionEvent], transcripts: [SessionTranscript]) {
        stt.transcript = spoken
        let session = PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                                       language: { .hinglish }, frontmostApp: { "Slack" },
                                       commands: CommandParser(model: { [model] in model }))
        var events: [SessionEvent] = []
        var transcripts: [SessionTranscript] = []
        session.onEvent = { events.append($0) }
        session.onTranscript = { transcripts.append($0) }
        session.keyDown(kind)
        clock.advance(by: 1.0)
        await session.keyUp()
        return (events, transcripts)
    }

    @Test func aCommandIsTranscribedAndParsedButNeverTyped() async {
        let (events, _) = await run("Message Gurjeet saying I'll be late by 15 minutes.")

        #expect(events == [.listening(.command), .transcribing,
                           .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "I'll be late by 15 minutes."))])
        #expect(inserter.inserted.isEmpty)
    }

    @Test func anUnknownCommandSaysSoAndKeepsTheTranscript() async {
        let (events, _) = await run("Book a flight to Delhi tomorrow.")

        #expect(events.last == .commandUnknown(transcript: "Book a flight to Delhi tomorrow."))
        #expect(model.inputs == ["Book a flight to Delhi tomorrow."])
        #expect(inserter.inserted.isEmpty)
    }

    @Test func eachCommandIsReportedForHistoryWithWhatItDid() async {
        let (_, parsed) = await run("Message Gurjeet saying hi")
        let (_, unknown) = await run("Book a flight")

        #expect(parsed.map(\.kind) == [.command])
        #expect(parsed.first?.outcome == "→ Slack · Gurjeet · \"Hi\"")
        #expect(parsed.first?.inserted == false)
        #expect(unknown.first?.outcome == "Can't do that yet")
    }

    @Test func commandsUseTheirOwnSpeechToText() async {
        // The app gives commands a pipeline without AI cleanup: faster, and nothing rewrites the phrasing.
        let commandSTT = FakeSpeechToText()
        commandSTT.transcript = "Message Gurjeet saying hi"
        stt.transcript = "something else entirely"
        let session = PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                                       language: { .hinglish }, commands: CommandParser(model: { nil }),
                                       commandSpeechToText: commandSTT)
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown(.command)
        clock.advance(by: 1)
        await session.keyUp()

        #expect(events.last == .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "Hi")))
        #expect(stt.requests.isEmpty)
    }

    @Test func escWhileACommandIsBeingUnderstoodCancelsIt() async {
        stt.transcript = "Tell Rohan he can merge"
        let slow = SlowCommandModel()
        let session = PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                                       language: { .english }, commands: CommandParser(model: { slow }))
        var events: [SessionEvent] = []
        var transcripts: [SessionTranscript] = []
        session.onEvent = { events.append($0) }
        session.onTranscript = { transcripts.append($0) }
        slow.onReply = { Task { await session.cancel() } }

        session.keyDown(.command)
        clock.advance(by: 1)
        await session.keyUp()

        #expect(events.last == .ignored(.cancelled))
        #expect(!events.contains { if case .commandParsed = $0 { true } else { false } })
        #expect(transcripts.isEmpty)
    }

    @Test func dictationIsUnchanged() async {
        let (events, transcripts) = await run("Message Gurjeet saying hi", kind: .dictation)

        #expect(events.first == .listening(.dictation))
        #expect(inserter.inserted == ["Message Gurjeet saying hi"])
        #expect(transcripts.first?.kind == .dictation && transcripts.first?.outcome == nil)
        #expect(model.inputs.isEmpty)
    }
}

@MainActor
final class SlowCommandModel: CommandModel {
    var onReply: () -> Void = {}
    func reply(to command: String, instructions: String) async throws -> String {
        onReply()
        try await Task.sleep(for: .milliseconds(100))
        return #"{"action":"send_message","app":"slack","to":"Rohan","text":"You can merge"}"#
    }
}
