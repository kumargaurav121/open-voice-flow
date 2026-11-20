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

    @Test func commandsKeepASpokenListOnOneLine() async {
        let events = await press(.command, hearing: "message gurujit saying first, buy milk, second, call mom").events

        #expect(events.last == .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "First, buy milk, second, call mom")))
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

    // MARK: Lists (v2 ticket 10)

    @Test func spokenListsBecomeNumberedLinesAfterAColon() async {
        // Eval items 38 and 39: the reading script, and the expected output written for it.
        #expect(await press(hearing: "Kal market se yeh cheezein laani hain. First, doodh. Second, bread. Third, anday. And fourth, paneer.").pasted
                == "Kal market se yeh cheezein laani hain:\n1. Doodh\n2. Bread\n3. Anday\n4. Paneer")
        #expect(await press(hearing: "For tomorrow's standup, I have three updates. One, the login bug is fixed. Two, the release notes are ready for review. Three, I'm blocked on the design for the settings page.").pasted
                == "For tomorrow's standup, I have three updates:\n1. The login bug is fixed.\n2. The release notes are ready for review.\n3. I'm blocked on the design for the settings page.")
    }

    @Test func aNumberStartingAClauseIsAnEnumeratorWithoutItsComma() async {
        // Eval item 39 as Parakeet wrote it: "two the release notes", "three I am".
        #expect(await press(hearing: "For tomorrow's stand up I have three updates. One, the login bug is fixed, two the release notes are ready for review, three I am blogged on the design for the setting page.").pasted
                == "For tomorrow's stand up I have three updates:\n1. The login bug is fixed.\n2. The release notes are ready for review.\n3. I am blogged on the design for the setting page.")
        // A number before a noun is a quantity.
        #expect(await press(hearing: "One, we ordered pizza, two pastas and three cokes.").pasted
                == "One, we ordered pizza, two pastas and three cokes.")
    }

    @Test func ordinalsNeedNoComma() async {
        // Eval item 38 as the Hinglish model wrote it.
        #expect(await press(hearing: "Kal market se yah chizen laani hai, first doodh, second bread, third ande and fourth panir.").pasted
                == "Kal market se yah chizen laani hai:\n1. Doodh\n2. Bread\n3. Ande\n4. Panir")
    }

    @Test func aListTheModelNumberedInlineGetsALineEach() async {
        // Eval item 39 as the Hinglish model wrote it.
        #expect(await press(hearing: "For tomorrow's stand up, I have three updates: 1. The login bug is fixed, 2. The release notes are ready for review, 3. I am blogged on the design for the setting page.").pasted
                == "For tomorrow's stand up, I have three updates:\n1. The login bug is fixed.\n2. The release notes are ready for review.\n3. I am blogged on the design for the setting page.")
    }

    @Test func numberOneAndHindiOrdinalsEnumerateToo() async {
        #expect(await press(hearing: "Two things. Number one, book the meeting room. Number two, send the invite to everyone.").pasted
                == "Two things:\n1. Book the meeting room.\n2. Send the invite to everyone.")
        // Not heard in the eval yet: spellings as the Hinglish model writes "pahla" elsewhere.
        #expect(await press(hearing: "Aaj do kaam hain. Pahla, doodh laana. Doosra, bill bharna.").pasted
                == "Aaj do kaam hain:\n1. Doodh laana\n2. Bill bharna")
    }

    @Test func quantitiesAndLoneEnumeratorsAreNotLists() async {
        for sentence in [
            "Ek, do, teen, chalo shuru karte hain.",
            "Do bread aur teen log aayenge.",
            "One coffee and two teas, please.",
            "I have one, two or three options.",
            "One, two, three, go!",
            "First, the plan is ready.",
            // Found in review: ordinals and numbers inside ordinary sentences.
            "First time I tried it failed, second time it worked.",
            "Pehli baar main Delhi gaya, doosri baar Mumbai.",
            "First and foremost, we ship. Second, we test.",
            "First of all, thanks. Second, the plan.",
            "I have two cats. One I adopted, two I bought.",
            "One, or at most, two, people will come.",
            "Number one priority is safety, number two is cost.",
            "Congrats, first and second place winners!",
            "Ram, first. Shyam, second.",
            "First, thanks for coming. I know it's late, second only to last week's meeting.",
        ] {
            #expect(await press(hearing: sentence).pasted == sentence)
        }
    }

    @Test func itemsOfUpToThreeWordsHaveNoFullStopsElseAllDo() async {
        #expect(await press(hearing: "First, buy milk. Second, call the plumber.").pasted == "1. Buy milk\n2. Call the plumber")
        #expect(await press(hearing: "First, buy fresh milk. Second, call the plumber today.").pasted
                == "1. Buy fresh milk.\n2. Call the plumber today.")
    }

    @Test func listItemsKeepTheirWords() async {
        // Found in review.
        #expect(await press(hearing: "First, is the plan ready? Second, who is paying?").pasted
                == "1. Is the plan ready?\n2. Who is paying?")
        #expect(await press(hearing: "First, open the app and then second, log in.").pasted == "1. Open the app\n2. Log in")
        #expect(await press(hearing: "First, 12 eggs. Second, call the plumber.").pasted == "1. 12 eggs\n2. Call the plumber")
        // What follows the last item's sentence goes below the list.
        #expect(await press(hearing: "First, milk. Second, tea. That's all I need, thanks.").pasted
                == "1. Milk\n2. Tea\n\nThat's all I need, thanks.")
        // "Tenth" reaches the list as "10th" (spoken numbers run first).
        #expect(await press(hearing: "First, a. Second, b. Third, c. Fourth, d. Fifth, e. Sixth, f. Seventh, g. Eighth, h. Ninth, i. Tenth, j.").pasted
                == "1. A\n2. B\n3. C\n4. D\n5. E\n6. F\n7. G\n8. H\n9. I\n10. J")
    }

    @Test mutating func listsSurviveTheAICleanup() async {
        // The app log's AI cleanup rejected this list on 2026-10-08. Lists are laid out after the AI pass now, on
        // whichever text it used.
        aiEnabled = true
        let heard = "okay I want three items, first is milk, second is tea, third is coffee"
        let list = "Okay I want three items:\n1. Milk\n2. Tea\n3. Coffee"

        ai.reply = { $0 + "." }                                           // accepted
        #expect(await press(hearing: heard).pasted == list)
        ai.reply = { _ in "First is milk, second is tea, third is coffee." }  // Fast's rewrite: rejected
        #expect(await press(hearing: heard).pasted == list)
        ai.reply = { _ in "Okay I want three items:\n1. Milk\n2. Tea\n3. Coffee" }  // its own list: rejected
        #expect(await press(hearing: heard).pasted == list)
    }
}
