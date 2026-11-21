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

    /// A session built as the app builds it, around the fake model, AI and inserter.
    func makeSession() -> PushToTalkSession {
        let selected: TextCleaner? = aiEnabled ? ai : nil, codeContext = codeContext
        let pipeline = TranscriptPipeline(speech: model, terms: { ["Gurjeet"] }, isEnglishWord: { _ in false })
        let dictation = pipeline.dictation(selectedAI: { selected }, isCodeContext: { codeContext }, log: { _ in })
        return PushToTalkSession(
            recorder: recorder,
            speechToText: dictation,
            inserter: inserter, now: clock.now, language: { .hinglish },
            commands: CommandParser(model: { [commandModel] in commandModel }),
            commandSpeechToText: pipeline.commands(),
            live: pipeline.live,
            unformatted: { dictation.unformatted }
        )
    }

    /// Holds the key for a second while the speech model "hears" `heard`; returns what was pasted.
    func press(_ kind: SessionKind = .dictation, hearing heard: String, audio: [Float] = [],
               on session: PushToTalkSession? = nil) async -> (pasted: String?, events: [SessionEvent]) {
        model.transcript = heard
        let session = session ?? makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }
        session.keyDown(kind)
        recorder.deliver(audio)
        clock.advance(by: 1)
        await session.keyUp()
        return (inserter.inserted.last, events)
    }

    /// Undo Formatting on `session`; returns what it reported.
    func undo(on session: PushToTalkSession) async -> [SessionEvent] {
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }
        await session.undoFormatting()
        return events
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

    @Test func aListOfThreeMayStartMidPhrase() async {
        // As dictated on the Mac (2026-11-20); the user asked for lists of three or more to count.
        #expect(await press(hearing: "I need to buy first milk, second bread, third eggs.").pasted
                == "I need to buy:\n1. Milk\n2. Bread\n3. Eggs")
        for sentence in [
            "I need to buy first milk, second bread.",                    // two: the start must be clear
            "She won first prize, second prize and third prize.",           // ranks of one thing
            "She came first in maths, second in science and third in art.",  // ranks in places
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

    // MARK: Self-corrections (v2 ticket 11)

    @Test mutating func theAICleanupMayKeepOnlyWhatWasMeant() async {
        aiEnabled = true
        // Eval items 40 and 41: the reading script, and the expected output written for it.
        ai.reply = { _ in "Let's meet at five, at the usual coffee place." }
        #expect(await press(hearing: "Let's meet at four, actually no, let's make it five, at the usual coffee place.").pasted
                == "Let's meet at five, at the usual coffee place.")
        ai.reply = { _ in "Meeting chaar baje hai. Main kal Pune ja raha hoon." }
        #expect(await press(hearing: "Meeting teen baje hai, nahi nahi, chaar baje hai. Main kal Mumbai ja raha hoon, sorry, Pune ja raha hoon.").pasted
                == "Meeting chaar baje hai. Main kal Pune ja raha hoon.")
    }

    @Test mutating func selfCorrectionsAsTheModelsWroteThem() async {
        aiEnabled = true
        // Eval item 40 as Parakeet and Whisper turbo wrote it, 41 as the Hinglish model did ("nahin nahin").
        ai.reply = { _ in "Let's meet at five at the usual coffee place." }
        #expect(await press(hearing: "Let's meet at four actually, no, let's make it five at the usual coffee place").pasted
                == "Let's meet at five at the usual coffee place.")
        ai.reply = { _ in "Let's meet at 5 at the usual coffee place." }
        #expect(await press(hearing: "Let's meet at 4. Actually no, let's make it 5 at the usual coffee place.").pasted
                == "Let's meet at 5 at the usual coffee place.")
        ai.reply = { _ in "Meeting chaar baje hai, main kal pune ja raha hoon." }
        #expect(await press(hearing: "Meeting tin baje hai, nahin nahin chaar baje hai, main kal Mumbai ja raha hoon, sorry, pune ja raha hoon.").pasted
                == "Meeting chaar baje hai, main kal pune ja raha hoon.")
        // One word for another of its kind: a name for a name.
        ai.reply = { _ in "Send it to Rahul." }
        #expect(await press(hearing: "Send it to Priya, sorry, Rahul").pasted == "Send it to Rahul.")
    }

    @Test mutating func onlyACorrectionMayBeDropped() async {
        aiEnabled = true
        let heard = "Let's meet at four, actually no, let's make it five, at the usual coffee place."
        for rewrite in [
            "Let's meet at four, at the usual coffee place.",   // the old version kept, the fix dropped
            "Let's meet at six, at the usual coffee place.",    // a value the speaker didn't say
            "Let's meet at five, at the usual place.",          // another word dropped, with no marker of its own
        ] {
            ai.reply = { _ in rewrite }
            #expect(await press(hearing: heard).pasted == heard)
        }
        // Found in review: the mistake kept and the fix dropped, words lost that no fix replaces, and markers
        // that aren't corrections.
        for (heard, rewrite) in [
            ("Book two tickets, no wait, three tickets", "Book two tickets."),
            ("Kal do kilo lana, nahi nahi, teen kilo lana", "Kal do kilo lana."),
            ("Meeting teen baje hai, nahi nahi, chaar baje hai.", "Meeting teen baje hai."),
            ("I'll come, no wait, I won't come", "I'll come."),
            ("Let's meet at four, actually no", "Let's meet."),
            ("Let's meet at four today, actually no, five, at the cafe.", "Let's meet at four, at the cafe."),
            ("Meeting teen baje hai aaj, nahi nahi, chaar baje hai, office mein.", "Meeting teen baje hai, office mein."),
            ("Send it to Priya today, sorry, to Rahul, before lunch.", "Send it to Priya, before lunch."),
            ("Send Priya the deck, no wait, the report", "Send the report."),
            // Real corrections the guard can't verify, rejected, which is safe: the two alignments of "the"
            // disagree on what was dropped; the fix is a word longer than the mistake.
            ("Send Priya the deck, no wait, the report", "Send Priya the report."),
            ("I'll come, no wait, I won't come", "I won't come."),
            ("We can't do Friday, sorry, I'll call you tomorrow.", "I'll call you tomorrow."),
            ("Ship it on Friday, I mean if QA passes.", "If QA passes."),
            ("We actually no longer support Windows.", "Support Windows."),
        ] {
            ai.reply = { _ in rewrite }
            #expect(await press(hearing: heard).pasted == heard, "\(heard) → \(rewrite)")
        }
        // The fixes themselves are accepted.
        for (heard, fixed) in [
            ("Book two tickets, no wait, three tickets", "Book three tickets."),
        ] {
            ai.reply = { _ in fixed }
            #expect(await press(hearing: heard).pasted == fixed)
        }
        // The marker alone, with nothing it corrects: an apology, not a correction.
        ai.reply = { _ in "I'm late." }
        #expect(await press(hearing: "Sorry, I'm late.").pasted == "Sorry, I'm late.")
        // "Actually" on its own is a real word (eval item 44).
        ai.reply = { _ in "I enjoyed the demo, the new notch animation looks really smooth." }
        #expect(await press(hearing: "I actually enjoyed the demo, the new notch animation looks really smooth.").pasted
                == "I actually enjoyed the demo, the new notch animation looks really smooth.")
    }

    @Test mutating func aCorrectionDropsAtMostTwelveWords() async {
        aiEnabled = true
        // Twelve dropped, the marker included.
        ai.reply = { _ in "Ask Ravi to bring the big red file from the shelf." }
        #expect(await press(hearing: "Ask Ram to bring the big red file from the shelf, sorry, ask Ravi to bring the big red file from the shelf.").pasted
                == "Ask Ravi to bring the big red file from the shelf.")
        // Thirteen.
        ai.reply = { _ in "Ask Ravi to bring the big red file from the top shelf." }
        #expect(await press(hearing: "Ask Ram to bring the big red file from the top shelf, sorry, ask Ravi to bring the big red file from the top shelf.").pasted
                == "Ask Ram to bring the big red file from the top shelf, sorry, ask Ravi to bring the big red file from the top shelf.")
    }

    @Test func withoutAICleanupACorrectionStaysAsSpoken() async {
        #expect(await press(hearing: "Let's meet at four, actually no, let's make it five.").pasted
                == "Let's meet at four, actually no, let's make it five.")
    }

    // MARK: Undo formatting (v2 ticket 12)

    @Test func undoFormattingPutsBackTheTextBeforeFormatting() async {
        let session = makeSession()
        #expect(await press(hearing: "um first milk, second bread, third eggs", on: session).pasted
                == "1. Milk\n2. Bread\n3. Eggs")

        let events = await undo(on: session)

        // Fillers stay removed; the list is undone.
        #expect(inserter.replacements == [.init(old: "1. Milk\n2. Bread\n3. Eggs", new: "First milk, second bread, third eggs")])
        #expect(events == [.formattingUndone])
    }

    @Test func undoFormattingLeavesEditedTextAloneAndSaysSo() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        inserter.fieldUnchanged = false  // the user typed after it

        #expect(await undo(on: session) == [.cantUndoFormatting])
        #expect(inserter.replacements.isEmpty)
    }

    @Test func aRefusedUndoCanBeTriedAgain() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        inserter.fieldUnchanged = false
        _ = await undo(on: session)
        inserter.fieldUnchanged = true  // the user deleted what they typed after it

        #expect(await undo(on: session) == [.formattingUndone])
        #expect(inserter.replacements == [.init(old: "Hi Rohan,\nThanks", new: "Hi Rohan comma new line thanks")])
    }

    @Test func undoFormattingWithoutAccessibilitySaysItCouldntPaste() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        inserter.error = FakeError()  // Accessibility was switched off

        #expect(await undo(on: session) == [.failed(.insertion)])
    }

    @Test func onlyTheLastDictationCanBeUndoneAndOnlyOnce() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        await session.undoFormatting()
        await session.undoFormatting()
        #expect(inserter.replacements == [.init(old: "Hi Rohan,\nThanks", new: "Hi Rohan comma new line thanks")])

        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        session.keyDown()  // the next dictation starts
        await session.cancel()
        await session.undoFormatting()

        #expect(inserter.replacements.count == 1)
    }

    @Test mutating func withNothingToUndoUndoFormattingDoesNothing() async {
        var session = makeSession()
        #expect(!session.canUndoFormatting)  // nothing dictated yet
        #expect(await undo(on: session).isEmpty)

        _ = await press(hearing: "I'll be there at 5.", on: session)  // nothing was formatted
        #expect(!session.canUndoFormatting)
        #expect(await undo(on: session).isEmpty)

        inserter.error = FakeError()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)  // not pasted
        inserter.error = nil
        #expect(!session.canUndoFormatting)
        #expect(await undo(on: session).isEmpty)

        codeContext = true
        session = makeSession()
        _ = await press(hearing: "git commit dash m fix comma typo", on: session)  // code editors get it raw
        #expect(!session.canUndoFormatting)
        #expect(await undo(on: session).isEmpty)

        #expect(inserter.replacements.isEmpty)
    }

    @Test func undoFormattingCanBeOfferedAfterAFormattedDictation() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)

        #expect(session.canUndoFormatting)
    }

    @Test func aPressWhileUndoingDoesNotStartADictation() async {
        let session = makeSession()
        _ = await press(hearing: "Hi Rohan comma new line thanks", on: session)
        let starts = recorder.startCount
        inserter.onReplace = { session.keyDown() }  // its text would land in the middle of the undo

        _ = await undo(on: session)

        #expect(recorder.startCount == starts)
    }

    @Test mutating func undoFormattingAlsoUndoesTheAICleanup() async {
        aiEnabled = true
        ai.reply = { _ in "Let's meet at five." }
        let session = makeSession()
        _ = await press(hearing: "Let's meet at four, actually no, let's make it five.", on: session)

        await session.undoFormatting()

        #expect(inserter.replacements == [.init(old: "Let's meet at five.", new: "Let's meet at four, actually no, let's make it five.")])
    }
}
