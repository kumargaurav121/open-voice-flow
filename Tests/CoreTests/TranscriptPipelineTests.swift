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

    @Test func commandsKeepSpokenPunctuationAsWords() async {
        // A line break would cut the message off: the command parser reads one line.
        let events = await press(.command, hearing: "message gurujit saying running late comma new line sorry").events

        #expect(events.last == .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "Running late comma new line sorry")))
    }

    @Test func cleanupRunsOnceOnTheWholeDictationNotOnEachPart() async {
        model.replies = ["um, so the plan", "is ready"]

        let pasted = await press(hearing: "", audio: PauseCutterTests.audio([.speech(3), .pause(0.6), .speech(2)])).pasted

        #expect(model.requests.count == 2)
        #expect(pasted == "So the plan is ready")
    }

    // MARK: Spoken punctuation and line breaks (v2 ticket 09)

    @Test func spokenPunctuationAndBreaksBecomeMarksAndLines() async {
        // Eval item 42, as Parakeet wrote it: its own commas set off each spoken command.
        let heard = "Hi Rohan, comma, new line, thanks for the update, full stop, new paragraph, let's ship it on Friday. Exclamation mark."

        #expect(await press(hearing: heard).pasted == "Hi Rohan,\nThanks for the update.\n\nLet's ship it on Friday!")
    }

    @Test func everySpokenMarkHasItsSign() async {
        #expect(await press(hearing: "is it ready question mark next line yes exclamation point").pasted
                == "Is it ready?\nYes!")
        #expect(await press(hearing: "The plan, colon, ship it Friday, dash, latest semicolon then rest, period.").pasted
                == "The plan: ship it Friday - latest; then rest.")
    }

    @Test func talkingAboutPunctuationStaysWords() async {
        #expect(await press(hearing: "Remove the comma and add a question mark, then start this new paragraph").pasted
                == "Remove the comma and add a question mark, then start this new paragraph")
        #expect(await press(hearing: "We're launching a new line of laptops").pasted == "We're launching a new line of laptops")
        // Hindi's "this" and "one", as the Hinglish model writes them.
        #expect(await press(hearing: "Yah comma hata do, ek new line daalo").pasted == "Yah comma hata do, ek new line daalo")
    }

    @Test func periodDashAndColonAreMarksOnlyWhenSetOff() async {
        // Everyday words too; the speech model sets the commands off with its own punctuation.
        #expect(await press(hearing: "We closed the reporting period. I'll dash home before colon screening").pasted
                == "We closed the reporting period. I'll dash home before colon screening")
        #expect(await press(hearing: "Ship it Friday, period. Then rest").pasted == "Ship it Friday. Then rest")
        // Set off on one side only, they are still words (found in review).
        #expect(await press(hearing: "In that period, colon cancer rates rose. When you're done, dash off a reply.").pasted
                == "In that period, colon cancer rates rose. When you're done, dash off a reply.")
    }

    @Test func aCommandBesideAPauseCutStillApplies() async {
        // The speaker paused after "comma": each part was transcribed alone and ended as a sentence.
        model.replies = ["Hi Rohan, comma.", "New line, thanks for the update."]

        let pasted = await press(hearing: "", audio: PauseCutterTests.audio([.speech(3), .pause(0.6), .speech(2)])).pasted

        #expect(model.requests.count == 2)
        #expect(pasted == "Hi Rohan,\nThanks for the update.")
    }

    @Test mutating func theAICleanupKeepsTheSpokenBreaksOrIsNotUsed() async {
        aiEnabled = true
        let heard = "Hi Rohan comma new line thanks for the update full stop new paragraph let's ship it"
        let rules = "Hi Rohan,\nThanks for the update.\n\nLet's ship it"

        // As Fast and Thorough rewrote eval item 42: on one line, or with the paragraph break merged.
        ai.reply = { _ in "Hi Rohan, thanks for the update. Let's ship it." }
        #expect(await press(hearing: heard).pasted == rules)
        ai.reply = { _ in "Hi Rohan,  \nThanks for the update.  \nLet's ship it." }
        #expect(await press(hearing: heard).pasted == rules)

        // The same breaks: used, without the spaces some models put before a break.
        ai.reply = { _ in "Hi Rohan,  \nThanks for the update.\n\nLet's ship it." }
        #expect(await press(hearing: heard).pasted == "Hi Rohan,\nThanks for the update.\n\nLet's ship it.")
    }

    @Test mutating func theAICleanupMayNumberTheSpokenLines() async {
        aiEnabled = true
        ai.reply = { _ in "Buy:\n1. Milk\n2. Bread\n3. Eggs" }

        #expect(await press(hearing: "Buy: new line milk new line bread new line eggs").pasted == "Buy:\n1. Milk\n2. Bread\n3. Eggs")
    }

    @Test mutating func aNumberTheAIAddsInsideASentenceIsStillAnAddedWord() async {
        aiEnabled = true
        ai.reply = { _ in "Buy 1. milk 2. bread" }

        #expect(await press(hearing: "buy milk bread").pasted == "Buy milk bread")
    }

    @Test mutating func aListNumberNeverStandsForASpokenWord() async {
        aiEnabled = true
        // "Two" was dropped, and the AI's "2." doesn't make up for it (found in review).
        ai.reply = { _ in "Buy:\n1. Eggs\n2. Milk" }
        #expect(await press(hearing: "Buy: new line two eggs new line milk").pasted == "Buy:\nTwo eggs\nMilk")

        // Numbers already opening the spoken lines are kept as they were.
        ai.reply = { $0 + "." }
        #expect(await press(hearing: "Updates: new line 1. login fixed new line 2. notes ready").pasted
                == "Updates:\n1. Login fixed\n2. Notes ready.")
    }
}
