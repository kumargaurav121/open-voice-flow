import Testing
@testable import Core

/// What the session reports for history: each final transcript, whether it reached the app.
@MainActor
struct SessionTranscriptTests {
    let recorder = FakeRecorder()
    let stt = FakeSpeechToText()
    let inserter = FakeInserter()
    let clock = FakeClock()

    func dictate(_ spoken: String, holding seconds: Double = 1.0, language: Language = .english) async -> [SessionTranscript] {
        stt.transcript = spoken
        let session = PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                                       language: { language }, frontmostApp: { "Slack" })
        var transcripts: [SessionTranscript] = []
        session.onTranscript = { transcripts.append($0) }
        session.keyDown()
        clock.advance(by: seconds)
        await session.keyUp()
        return transcripts
    }

    @Test func anInsertedDictationIsReportedWithItsTextModeAndAudio() async {
        let transcripts = await dictate("  Message Gurjeet saying I'm late. ", language: .hinglish)

        #expect(transcripts == [SessionTranscript(text: "Message Gurjeet saying I'm late.", language: .hinglish,
                                                  app: "Slack", inserted: true, clip: recorder.clip)])
    }

    @Test func textThatCouldNotBeInsertedIsStillReported() async {
        inserter.error = InsertFailure()

        let transcripts = await dictate("Save this somewhere")

        #expect(transcripts.map(\.text) == ["Save this somewhere"])
        #expect(transcripts.map(\.inserted) == [false])
    }

    @Test func theAppIsTheOneInFrontWhenRecordingStarted() async {
        stt.transcript = "First"
        var front = "Slack"
        let session = PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                                       language: { .english }, frontmostApp: { front })
        var transcripts: [SessionTranscript] = []
        session.onTranscript = { transcripts.append($0) }
        stt.onTranscribe = {
            // While this dictation is transcribing, the user switches app and presses again (ignored).
            front = "Mail"
            session.keyDown()
        }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(transcripts.map(\.app) == ["Slack"])
    }

    @Test func nothingIsReportedWhenThereIsNoText() async {
        #expect(await dictate("Hello", holding: 0.1).isEmpty)  // too short
        #expect(await dictate("   ").isEmpty)                    // blank transcript
        stt.error = InsertFailure()
        #expect(await dictate("Hello").isEmpty)                  // transcription failed
    }
}

private struct InsertFailure: Error {}
