import Testing
@testable import Core

/// The text pipeline the app, the eval runner and these tests all build, exercised through a session:
/// what the speech model heard and what lands in the focused app (or reaches the command parser).
@MainActor
struct TranscriptPipelineTests {
    let recorder = FakeRecorder()
    let model = FakeSpeechToText()
    let ai = FakeCleaner()
    let inserter = FakeInserter()
    let clock = FakeClock()
    let commandModel = FakeCommandModel(reply: #"{"action":"unknown"}"#)
    var aiEnabled = false
    var codeContext = false

    /// Holds the key for a second while the speech model "hears" `heard`; returns what was pasted.
    func press(_ kind: SessionKind = .dictation, hearing heard: String, audio: [Float] = [])
        async -> (pasted: String?, events: [SessionEvent]) {
        model.transcript = heard
        let selected: TextCleaner? = aiEnabled ? ai : nil, codeContext = codeContext
        let pipeline = TranscriptPipeline(speech: model, terms: { ["Gurjeet"] }, isEnglishWord: { _ in false })
        let session = PushToTalkSession(
            recorder: recorder,
            speechToText: pipeline.dictation(selectedAI: { selected }, isCodeContext: { codeContext }, log: { _ in }),
            inserter: inserter, now: clock.now, language: { .hinglish },
            commands: CommandParser(model: { [commandModel] in commandModel }),
            commandSpeechToText: pipeline.commands(),
            live: pipeline.live
        )
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }
        session.keyDown(kind)
        recorder.deliver(audio)
        clock.advance(by: 1)
        await session.keyUp()
        return (inserter.inserted.last, events)
    }

    @Test func pastesTheDictionarysSpellingsWithFillersRemoved() async {
        #expect(await press(hearing: "um, gurujit ko message karo").pasted == "Gurjeet ko message karo")
    }

    @Test func pastesEnglishLettersWhateverScriptTheModelWrote() async {
        let pasted = await press(hearing: "मैं आज थोड़ा देर से आऊंगा, traffic बहुत है").pasted

        #expect(pasted?.unicodeScalars.allSatisfy(\.isASCII) == true)
        #expect(pasted?.contains("traffic") == true)
    }

    @Test mutating func theAICleanupSeesTheDictionarysSpellings() async {
        aiEnabled = true
        ai.reply = { $0 + "." }

        let pasted = await press(hearing: "um, gurujit ko message karo").pasted

        #expect(ai.inputs == ["Gurjeet ko message karo"])
        #expect(pasted == "Gurjeet ko message karo.")
    }

    @Test mutating func codeEditorsGetTheRawTranscriptWithoutCleanup() async {
        codeContext = true
        aiEnabled = true

        #expect(await press(hearing: "um git commit dash m fix").pasted == "um git commit dash m fix")
        #expect(ai.inputs.isEmpty)
    }

    @Test mutating func commandsGetTheDictionaryAndRulesButNeverTheAICleanup() async {
        aiEnabled = true

        let events = await press(.command, hearing: "um, message gurujit saying I'll be late").events

        #expect(events.last == .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "I'll be late")))
        #expect(ai.inputs.isEmpty)
    }

    @Test func cleanupRunsOnceOnTheWholeDictationNotOnEachPart() async {
        model.replies = ["um, so the plan", "is ready"]

        let pasted = await press(hearing: "", audio: PauseCutterTests.audio([.speech(3), .pause(0.6), .speech(2)])).pasted

        #expect(model.requests.count == 2)
        #expect(pasted == "So the plan is ready")
    }
}
