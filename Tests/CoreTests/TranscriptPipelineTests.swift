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
    /// The bundle ID of the app in front, where the text goes.
    var frontmostApp: String?
    /// The title of that app's front window (nil: it can't be read).
    var frontWindowTitle: String?
    /// The address of a browser's front tab (nil: the browser didn't give it).
    var frontTabAddress: String?
    var styles = AppStyles()
    var snippets: [Snippet] = []
    var language = Language.hinglish
    /// Every line the pipeline logged.
    let logged = Lines()
    /// What the pipeline read about a browser's page, in order: "address", "title".
    let pageReads = Lines()

    /// A session built as the app builds it, around the fake model, AI and inserter.
    func makeSession() -> PushToTalkSession {
        let selected: TextCleaner? = aiEnabled ? ai : nil, app = frontmostApp, address = frontTabAddress,
            title = frontWindowTitle, styles = styles, snippets = snippets, language = language
        let pipeline = TranscriptPipeline(speech: model, terms: { ["Gurjeet"] }, isEnglishWord: { _ in false })
        let dictation = pipeline.dictation(selectedAI: { selected }, frontmostApp: { app },
                                           frontTabAddress: { [pageReads] in pageReads.lines.append("address"); return address },
                                           frontWindowTitle: { [pageReads] in pageReads.lines.append("title"); return title },
                                           styles: { styles }, snippets: { snippets },
                                           log: { [logged] in logged.lines.append($0) })
        return PushToTalkSession(
            recorder: recorder,
            speechToText: dictation,
            inserter: inserter, now: clock.now, language: { language },
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
        frontmostApp = "com.microsoft.VSCode"
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

        frontmostApp = "com.apple.Terminal"
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

    // MARK: Styles per app (v2 ticket 13)

    /// The chat apps' bundle IDs: Slack, Teams (new and classic), Messages, WhatsApp, Discord, Telegram (the
    /// App Store app and Telegram Desktop).
    nonisolated static let chatApps = ["com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.microsoft.teams", "com.apple.MobileSMS",
                           "net.whatsapp.WhatsApp", "com.hnc.Discord", "ru.keepcoder.Telegram", "com.tdesktop.Telegram"]

    @Test(arguments: chatApps)
    mutating func chatAppsGetTheCasualStyle(_ app: String) async {
        frontmostApp = app

        #expect(await press(hearing: "See you at five.").pasted == "See you at five")
    }

    @Test(arguments: ["com.apple.TextEdit", nil])
    mutating func otherAppsHaveNoStyle(_ app: String?) async {
        frontmostApp = app

        #expect(await press(hearing: "See you at five.").pasted == "See you at five.")
    }

    @Test mutating func aChatMessageOfOneOrTwoSentencesLosesOnlyItsFinalFullStop() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        #expect(await press(hearing: "Running late. Start without me.").pasted == "Running late. Start without me")
        #expect(await press(hearing: "Hi Rohan comma new line thanks for the update.").pasted
                == "Hi Rohan,\nThanks for the update")
        #expect(await press(hearing: "Are you free at five?").pasted == "Are you free at five?")
        #expect(await press(hearing: "We shipped it. Great work!").pasted == "We shipped it. Great work!")
    }

    @Test mutating func aFullStopSaidOutLoudStaysInAChatMessage() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        #expect(await press(hearing: "see you at five full stop").pasted == "See you at five.")
        #expect(await press(hearing: "See you at five, period.").pasted == "See you at five.")
        #expect(await press(hearing: "Hi Rohan comma new line thanks for the update full stop new line").pasted
                == "Hi Rohan,\nThanks for the update.")
    }

    @Test mutating func aLongerChatMessageKeepsItsFullStops() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        #expect(await press(hearing: "The build is green. QA signed off. Let's ship it.").pasted
                == "The build is green. QA signed off. Let's ship it.")
        // A list's items keep their full stops, like the rest of its items.
        #expect(await press(hearing: "Two updates. One, the login bug is fixed. Two, the notes are ready.").pasted
                == "Two updates:\n1. The login bug is fixed.\n2. The notes are ready.")
    }

    @Test mutating func aChatMessageEndingInAnEllipsisOrAnAbbreviationKeepsIt() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        #expect(await press(hearing: "Let me think...").pasted == "Let me think...")
        #expect(await press(hearing: "See you at 5 p.m.").pasted == "See you at 5 p.m.")
    }

    @Test mutating func aBreakSaidAtTheEndOrStartDoesntHideTheStyle() async {
        frontmostApp = "com.tinyspeck.slackmacgap"
        #expect(await press(hearing: "See you at five. New line").pasted == "See you at five")

        frontmostApp = "com.apple.mail"
        #expect(await press(hearing: "New line hi Mark, thanks for the call.").pasted == "Hi Mark,\n\nThanks for the call.")
    }

    @Test mutating func aChatMessageCountsSentencesNotFullStops() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        #expect(await press(hearing: "Ask Mr. Sharma. He knows.").pasted == "Ask Mr. Sharma. He knows")
        #expect(await press(hearing: "Update to version 2.5.").pasted == "Update to version 2.5")
        #expect(await press(hearing: "It's on example.com.").pasted == "It's on example.com")
    }

    @Test(arguments: ["com.apple.mail", "com.microsoft.Outlook"])
    mutating func emailAppsPutTheGreetingOnALineOfItsOwn(_ app: String) async {
        frontmostApp = app

        // Eval item 36's opening, as both English models wrote it.
        #expect(await press(hearing: "Hi Mark, thanks for your time on the call yesterday. See you on Monday.").pasted
                == "Hi Mark,\n\nThanks for your time on the call yesterday. See you on Monday.")
    }

    @Test mutating func anEmailMayOpenWithAnyUsualGreeting() async {
        frontmostApp = "com.apple.mail"

        #expect(await press(hearing: "Hello everyone, here's a quick summary.").pasted == "Hello everyone,\n\nHere's a quick summary.")
        #expect(await press(hearing: "Good morning team, the build is ready.").pasted == "Good morning team,\n\nThe build is ready.")
        #expect(await press(hearing: "Dear Mr. Sharma, please find the report attached.").pasted
                == "Dear Mr. Sharma,\n\nPlease find the report attached.")
        #expect(await press(hearing: "Hey Mark and Priya, quick question about Friday.").pasted
                == "Hey Mark and Priya,\n\nQuick question about Friday.")
        #expect(await press(hearing: "Hi, are you free tomorrow?").pasted == "Hi,\n\nAre you free tomorrow?")
    }

    /// Mail on the web in each browser (the user's choice, 2026-11-23): Gmail, a work account's Gmail (named after
    /// the company), and Outlook on the web, by the front window's title when the browser doesn't give its tab's
    /// address (not allowed yet).
    nonisolated static let webMail = [
        ("company.thebrowser.dia", "Inbox (3) - kumar@example.com - Gmail"),
        ("com.google.Chrome", "Inbox (1,234) - kumar@example.com - Acme Mail"),
        ("company.thebrowser.Browser", "Re: Pilot - Monday - kumar@example.com - Gmail"),
        ("com.brave.Browser", "Compose Mail - kumar@example.com - Gmail"),
        ("com.apple.Safari", "Mail - Kumar Gaurav - Outlook"),
        ("com.microsoft.edgemac", "Inbox - kumar@example.com - Gmail - Work"),
    ]

    @Test(arguments: webMail)
    mutating func mailInABrowserGetsTheEmailStyle(_ browser: String, _ title: String) async {
        frontmostApp = browser
        frontWindowTitle = title

        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted
                == "Hi Mark,\n\nThanks for the call.\n\nThanks,\nKumar")
        #expect(pageReads.lines == ["address", "title"])
    }

    @Test(arguments: [
        ("company.thebrowser.dia", "Q4 plan - Google Docs"),
        ("com.google.Chrome", "Home - Daily Mail"),  // a site named Mail: no account's address before it
        ("com.brave.Browser", "Calendar - Kumar Gaurav - Outlook"),  // Outlook's calendar, not its mail
        ("com.apple.Safari", nil),  // a title that can't be read
        ("com.apple.TextEdit", "Inbox - kumar@example.com - Gmail"),  // not a browser
    ] as [(String, String?)])
    mutating func otherPagesInABrowserHaveNoStyle(_ app: String, _ title: String?) async {
        frontmostApp = app
        frontWindowTitle = title

        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted
                == "Hi Mark, thanks for the call. Thanks, Kumar")
    }

    /// The tab's address decides when the browser gives it (the user's choice, 2026-11-23): on their Mac, Gmail's
    /// window title with a draft open had five parts and no address.
    @Test(arguments: ["https://mail.google.com/mail/u/0/#inbox?compose=new", "https://mail.google.com/mail/u/1/#inbox",
                      "https://mail.google.com/mail/u/0/?view=cm&fs=1" /* Gmail's own compose window */,
                      "https://mail.google.com/a/example.com/#inbox" /* an old work-account link */,
                      "https://outlook.office.com/mail/inbox", "https://outlook.office365.com/mail/",
                      "https://outlook.live.com/mail/0/", "https://outlook.cloud.microsoft/mail/inbox"])
    mutating func mailInABrowserIsKnownByItsTabsAddress(_ address: String) async {
        frontmostApp = "com.google.Chrome"
        frontTabAddress = address
        frontWindowTitle = "New Message - Google Chrome"

        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted
                == "Hi Mark,\n\nThanks for the call.\n\nThanks,\nKumar")
        #expect(pageReads.lines == ["address"])
    }

    /// Gmail's Chat shares its host, and even its path; Outlook's calendar shares Outlook's host.
    @Test(arguments: ["https://mail.google.com/chat/u/0/#chat/home", "https://mail.google.com/mail/u/0/#chat/dm/x",
                      "https://outlook.office.com/calendar/view/week", "https://docs.google.com/document/d/1/edit"])
    mutating func aBrowserPageWhoseAddressIsntMailHasNoStyleWhateverItsTitle(_ address: String) async {
        frontmostApp = "com.google.Chrome"
        frontTabAddress = address
        frontWindowTitle = "Inbox (3) - kumar@example.com - Gmail - Google Chrome"

        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted
                == "Hi Mark, thanks for the call. Thanks, Kumar")
    }

    @Test mutating func whyABrowserPageIsntMailIsLoggedWithoutItsAddressOrTitle() async {
        frontmostApp = "com.google.Chrome"
        frontTabAddress = "https://docs.google.com/document/d/1/edit"
        _ = await press(hearing: "See you at five.")
        frontTabAddress = nil
        frontWindowTitle = "Q4 plan - kumar@example.com - Google Docs"
        _ = await press(hearing: "See you at five.")
        frontWindowTitle = nil
        _ = await press(hearing: "See you at five.")

        #expect(logged.lines == ["Browser page isn't mail, by its address",
                                 "Browser page isn't mail: no address; title parts of 7, 17, 11 characters; an address is part 2",
                                 "Browser page isn't mail: no address; title unreadable"])
    }

    @Test mutating func anEmailsGreetingMayEndInAFullStop() async {
        frontmostApp = "com.apple.mail"

        // As pasted on the user's Mac after a pause (Parakeet, then Thorough; 2026-11-23).
        #expect(await press(hearing: "Hi Mark. Thanks for the call yesterday. The pilot starts on Monday. Thanks Kumar.").pasted
                == "Hi Mark,\n\nThanks for the call yesterday. The pilot starts on Monday.\n\nThanks,\nKumar")
        #expect(await press(hearing: "Good morning, team. The build is ready.").pasted == "Good morning, team,\n\nThe build is ready.")
        #expect(await press(hearing: "Dear Mr. Sharma. Please find the report attached.").pasted
                == "Dear Mr. Sharma,\n\nPlease find the report attached.")
        #expect(await press(hearing: "Hi. Are you free tomorrow?").pasted == "Hi,\n\nAre you free tomorrow?")
        // A title's full stop doesn't end the greeting.
        #expect(await press(hearing: "Dear Prof. Rao. Thanks for the review.").pasted == "Dear Prof. Rao,\n\nThanks for the review.")
        #expect(await press(hearing: "Dear Prof. Rao, thanks for the review.").pasted == "Dear Prof. Rao,\n\nThanks for the review.")
        #expect(await press(hearing: "Hi J. Smith, thanks for the review.").pasted == "Hi J. Smith,\n\nThanks for the review.")
        #expect(await press(hearing: "Dear Mr. sharma, please call me.").pasted == "Dear Mr. sharma, please call me.")
    }

    @Test mutating func onlyAGreetingOpeningTheEmailGoesOnItsOwnLine() async {
        frontmostApp = "com.apple.mail"

        #expect(await press(hearing: "High time we shipped it, said Mark.").pasted == "High time we shipped it, said Mark.")
        #expect(await press(hearing: "I said hi Mark, then left.").pasted == "I said hi Mark, then left.")
        #expect(await press(hearing: "Hi there is a problem with the build, can you check?").pasted
                == "Hi there is a problem with the build, can you check?")
        // Only the greeting: a capital after its comma starts the text.
        #expect(await press(hearing: "Hi Mark, I, for one, agree.").pasted == "Hi Mark,\n\nI, for one, agree.")
        #expect(await press(hearing: "Hi Mark, Friday, after lunch, works.").pasted == "Hi Mark,\n\nFriday, after lunch, works.")
        // A break the speaker gave it stays as said.
        #expect(await press(hearing: "Hi Rohan comma new line thanks").pasted == "Hi Rohan,\nThanks")
    }

    @Test mutating func anEmailsSignOffGoesOnLinesOfItsOwn() async {
        frontmostApp = "com.apple.mail"

        #expect(await press(hearing: "Hi team, quick update on the launch. The build is ready. Thanks, Kumar").pasted
                == "Hi team,\n\nQuick update on the launch. The build is ready.\n\nThanks,\nKumar")
        #expect(await press(hearing: "The report is attached. Best regards, Kumar Gaurav.").pasted
                == "The report is attached.\n\nBest regards,\nKumar Gaurav")
        #expect(await press(hearing: "See you on Monday. Cheers!").pasted == "See you on Monday.\n\nCheers!")
        #expect(await press(hearing: "See you on Monday. Best Regards").pasted == "See you on Monday.\n\nBest Regards")
    }

    @Test mutating func thankingTheReaderIsNotASignature() async {
        frontmostApp = "com.apple.mail"

        // The name the email greets is the reader's: it stays with the thanks.
        #expect(await press(hearing: "Hi Priya, the deck is ready. Thanks, Priya!").pasted
                == "Hi Priya,\n\nThe deck is ready.\n\nThanks, Priya!")
        #expect(await press(hearing: "The deck is ready. Thank you for your help.").pasted
                == "The deck is ready. Thank you for your help.")
        #expect(await press(hearing: "Thanks, Kumar").pasted == "Thanks, Kumar")  // nothing to sign off
        // Also with the greeting already on a line of its own.
        #expect(await press(hearing: "Hi Priya comma new line the deck is ready. Thanks, Priya!").pasted
                == "Hi Priya,\nThe deck is ready.\n\nThanks, Priya!")
    }

    @Test mutating func theAIsLayoutKeepsThanksToTheReaderTogether() async {
        frontmostApp = "com.apple.mail"
        aiEnabled = true
        ai.reply = { _ in "Hi Priya,\n\nThe deck is ready.\n\nThanks, Priya!" }

        #expect(await press(hearing: "Hi Priya, the deck is ready. Thanks, Priya!").pasted
                == "Hi Priya,\n\nThe deck is ready.\n\nThanks, Priya!")
    }

    @Test mutating func anEmailsAICleanupMayLayItOutInParagraphs() async {
        frontmostApp = "com.apple.mail"
        aiEnabled = true
        // As the 4B model laid out eval item 36's kind of email when asked for paragraphs.
        ai.reply = { _ in "Hi Mark,\n\nThanks for the call. The pilot starts Monday.\n\nCould you send me the names?\n\nThanks,\nKumar" }

        let pasted = await press(hearing: "Hi Mark, thanks for the call. The pilot starts Monday. Could you send me the names? Thanks, Kumar").pasted

        #expect(ai.styles == [.email])
        #expect(pasted == "Hi Mark,\n\nThanks for the call. The pilot starts Monday.\n\nCould you send me the names?\n\nThanks,\nKumar")
    }

    @Test mutating func theLineAfterTheAIsGreetingStartsWithACapital() async {
        frontmostApp = "com.apple.mail"
        aiEnabled = true
        ai.reply = { _ in "Hi Rohan,\n\nkal ki meeting confirm hai.\n\nThanks,\nKumar" }  // as Thorough wrote it

        #expect(await press(hearing: "Hi Rohan, kal ki meeting confirm hai. Thanks, Kumar").pasted
                == "Hi Rohan,\n\nKal ki meeting confirm hai.\n\nThanks,\nKumar")
    }

    @Test mutating func anEmailsAICleanupMustKeepTheBreaksSpoken() async {
        frontmostApp = "com.apple.mail"
        aiEnabled = true
        ai.reply = { _ in "Hi Mark,\n\nThanks for the call. See you Friday." }  // the spoken new paragraph is gone

        let pasted = await press(hearing: "Hi Mark comma new line thanks for the call full stop new paragraph see you Friday").pasted

        #expect(pasted == "Hi Mark,\nThanks for the call.\n\nSee you Friday")
    }

    @Test mutating func elsewhereTheAICleanupStillMayNotAddBreaks() async {
        frontmostApp = "com.tinyspeck.slackmacgap"
        aiEnabled = true
        ai.reply = { _ in "Thanks for the call.\n\nSee you Friday." }

        let pasted = await press(hearing: "Thanks for the call. See you Friday.").pasted

        #expect(ai.styles == [.chat])
        #expect(pasted == "Thanks for the call. See you Friday")
    }

    @Test mutating func aStyleSwitchedOffLeavesItsAppsUnstyled() async {
        styles.chat = false
        frontmostApp = "com.tinyspeck.slackmacgap"
        #expect(await press(hearing: "See you at five.").pasted == "See you at five.")

        styles.email = false
        frontmostApp = "com.apple.mail"
        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted == "Hi Mark, thanks for the call. Thanks, Kumar")
        frontmostApp = "com.google.Chrome"
        frontTabAddress = "https://mail.google.com/mail/u/0/#inbox"
        #expect(await press(hearing: "Hi Mark, thanks for the call. Thanks, Kumar").pasted == "Hi Mark, thanks for the call. Thanks, Kumar")
        #expect(pageReads.lines.isEmpty)  // nor is the browser asked for its tab, so it never asks the user
    }

    @Test mutating func withTheCodeStyleOffCodeEditorsAndTerminalsGetFormattedText() async {
        styles.code = false
        frontmostApp = "com.googlecode.iterm2"

        #expect(await press(hearing: "um fix the login bug comma then run the tests").pasted == "Fix the login bug, then run the tests")
    }

    @Test(arguments: ["com.microsoft.VSCode", "com.apple.Terminal", "com.jetbrains.intellij"])
    mutating func codeEditorsAndTerminalsGetExactlyWhatWasSaid(_ app: String) async {
        frontmostApp = app

        #expect(await press(hearing: "um git commit dash m fix comma typo").pasted == "um git commit dash m fix comma typo")
    }

    @Test mutating func aChatMessagesFullStopComesBackWithUndoFormatting() async {
        frontmostApp = "com.tinyspeck.slackmacgap"
        let session = makeSession()
        _ = await press(hearing: "See you at five.", on: session)

        #expect(session.canUndoFormatting)
        await session.undoFormatting()
        #expect(inserter.replacements == [.init(old: "See you at five", new: "See you at five.")])
    }

    @Test mutating func commandsInAChatAppAreNotStyled() async {
        frontmostApp = "com.tinyspeck.slackmacgap"

        let events = await press(.command, hearing: "message gurujit saying see you at five.").events

        #expect(events.last == .commandParsed(.sendMessage(app: "slack", to: "Gurjeet", text: "See you at five.")))
    }
}

extension TranscriptPipelineTests {
    // MARK: Snippets (v2 ticket 14)

    @Test mutating func sayingACuePastesItsSnippetExactlyAsSaved() async {
        snippets = [Snippet(cue: "my reply", text: "Thanks for reaching out. I'll reply within a day."),
                    Snippet(cue: "my email", text: "kumar@example.com")]
        aiEnabled = true
        frontmostApp = "com.tinyspeck.slackmacgap"  // whose style would drop a short message's full stop

        #expect(await press(hearing: "My reply.").pasted == "Thanks for reaching out. I'll reply within a day.")
        #expect(await press(hearing: "My email.").pasted == "kumar@example.com")  // no capital added
        #expect(ai.styles.isEmpty)  // nor any AI cleanup
    }

    /// The user's choice (2026-11-23): fillers are skipped too, and a cue's digits match the words said.
    @Test mutating func aCueMatchesWhateverTheCasePunctuationAndFillers() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com"),
                    Snippet(cue: "my address", text: "Kumar Gaurav\n42, MG Road\nBengaluru 560001"),
                    Snippet(cue: "zoom link 2", text: "https://zoom.us/j/2"),
                    Snippet(cue: "call 9", text: "Call me at 9."), Snippet(cue: "call 911", text: "Emergency: 911"),
                    Snippet(cue: "room 15", text: "Room 15, 2nd floor"),
                    Snippet(cue: "what's my number", text: "+91 98765 43210")]

        #expect(await press(hearing: "Um, MY EMAIL!").pasted == "kumar@example.com")
        #expect(await press(hearing: "Um, my address.").pasted == "Kumar Gaurav\n42, MG Road\nBengaluru 560001")
        #expect(await press(hearing: "Zoom link two.").pasted == "https://zoom.us/j/2")
        #expect(await press(hearing: "Call nine.").pasted == "Call me at 9.")
        #expect(await press(hearing: "Call nine one one.").pasted == "Emergency: 911")
        #expect(await press(hearing: "Room fifteen.").pasted == "Room 15, 2nd floor")
        #expect(await press(hearing: "Whats my number?").pasted == "+91 98765 43210")
    }

    @Test mutating func aCueInsideALongerDictationIsJustWords() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com"), Snippet(cue: "uh oh", text: "Something broke.")]

        #expect(await press(hearing: "Send them my email.").pasted == "Send them my email.")
        #expect(await press(hearing: "My email is below.").pasted == "My email is below.")
        #expect(await press(hearing: "Oh.").pasted == "Oh.")  // a cue's own words count, fillers and all
        #expect(await press(hearing: "Uh oh.").pasted == "Something broke.")
    }

    @Test mutating func commandsNeverMatchSnippets() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com")]

        let events = await press(.command, hearing: "my email").events

        #expect(events.last == .commandUnknown(transcript: "My email"))
        #expect(inserter.inserted.isEmpty)
    }

    @Test mutating func snippetsWorkInBothLanguages() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com"), Snippet(cue: "mera pata", text: "42, MG Road")]

        language = .english
        #expect(await press(hearing: "My email.").pasted == "kumar@example.com")
        language = .hinglish
        #expect(await press(hearing: "Mera pata.").pasted == "42, MG Road")
        // Devanagari from the Hinglish model reaches the match in English letters.
        #expect(await press(hearing: "मेरा पता").pasted == "42, MG Road")
    }

    /// The user's choice (2026-11-23): code editors and terminals, which otherwise get exactly what was said.
    @Test mutating func aCuePastesItsSnippetInCodeEditorsToo() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com")]
        frontmostApp = "com.apple.Terminal"

        #expect(await press(hearing: "my email").pasted == "kumar@example.com")
    }

    /// The user's choice (2026-11-23): a cue said by accident costs one keystroke.
    @Test mutating func undoFormattingPutsBackTheCueThatWasSaid() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com")]
        let session = makeSession()
        _ = await press(hearing: "my email.", on: session)

        #expect(session.canUndoFormatting)
        await session.undoFormatting()
        #expect(inserter.replacements == [.init(old: "kumar@example.com", new: "My email.")])
    }

    /// A terminal gets the words exactly as said, as for any dictation there.
    @Test mutating func undoFormattingInATerminalPutsBackTheCueExactlyAsSaid() async {
        snippets = [Snippet(cue: "my email", text: "kumar@example.com")]
        frontmostApp = "com.apple.Terminal"
        let session = makeSession()
        _ = await press(hearing: "um my email", on: session)

        await session.undoFormatting()
        #expect(inserter.replacements == [.init(old: "kumar@example.com", new: "um my email")])
    }
}

/// Lines collected by reference, so the pipeline's closures can add to them.
@MainActor
final class Lines {
    var lines: [String] = []
}
