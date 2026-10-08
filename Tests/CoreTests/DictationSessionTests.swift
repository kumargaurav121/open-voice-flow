import Testing
@testable import Core

@MainActor
struct DictationSessionTests {
    let recorder = FakeRecorder()
    let stt = FakeSpeechToText()
    let inserter = FakeInserter()
    let clock = FakeClock()

    func makeSession(language: Language = .auto) -> DictationSession {
        DictationSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now, language: { language })
    }

    @Test func releasingAfterHoldingInsertsTheTranscript() async {
        stt.transcript = "Hello world"
        let session = makeSession()

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(inserter.inserted == ["Hello world"])
    }

    @Test func pressShorterThanAQuarterSecondIsIgnored() async {
        stt.transcript = "Hello world"
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 0.2)
        await session.keyUp()

        #expect(stt.requests.isEmpty)
        #expect(inserter.inserted.isEmpty)
        #expect(events.last == .ignored(.tooShort))
        #expect(!recorder.isRecording)
    }

    @Test func clipWithNoSpeechIsNotTranscribed() async {
        recorder.clip = AudioClip(samples: [], sampleRate: 16_000)
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(stt.requests.isEmpty)
        #expect(events.last == .ignored(.noSpeech))
    }

    @Test func blankTranscriptInsertsNothing() async {
        stt.transcript = "   \n"
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(inserter.inserted.isEmpty)
        #expect(events.last == .ignored(.emptyTranscript))
    }

    @Test func transcriptionFailureReportsAnErrorAndInsertsNothing() async {
        stt.error = FakeError()
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(inserter.inserted.isEmpty)
        #expect(events.last == .failed(.transcription))
    }

    @Test func successfulSessionReportsEachStageWithTimings() async {
        stt.transcript = "Hello"
        stt.onTranscribe = { clock.advance(by: 0.5) }
        inserter.onInsert = { clock.advance(by: 0.25) }
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 2.0)
        await session.keyUp()

        let timings = SessionTimings(capture: 2.0, transcribe: 0.5, insert: 0.25)
        #expect(events == [.listening, .transcribing, .inserted(timings)])
    }

    @Test func insertionFailureIsReported() async {
        stt.transcript = "Hello"
        inserter.error = FakeError()
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(events.last == .failed(.insertion))
    }

    @Test func microphoneThatWontStartIsReportedAndReleaseDoesNothing() async {
        recorder.startError = FakeError()
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(events == [.failed(.microphone)])
        #expect(stt.requests.isEmpty)
    }

    @Test func pressWhileStillTranscribingDoesNotStartAnotherRecording() async {
        stt.transcript = "Hello"
        let session = makeSession()
        stt.onTranscribe = { session.keyDown() }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(recorder.startCount == 1)
        #expect(inserter.inserted == ["Hello"])
    }

    @Test func cancelledRecordingIsDiscarded() async {
        stt.transcript = "Hello"
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 1.0)
        await session.cancel()
        await session.keyUp()

        #expect(!recorder.isRecording)
        #expect(stt.requests.isEmpty)
        #expect(events == [.listening, .ignored(.cancelled)])
    }

    @Test func transcribesInTheSelectedLanguage() async {
        stt.transcript = "नमस्ते"
        let session = makeSession(language: .hindi)

        session.keyDown()
        clock.advance(by: 1.0)
        await session.keyUp()

        #expect(stt.requests.map(\.language) == [.hindi])
    }

    @Test func pressWhileACancelIsStillStoppingTheMicDoesNotStartRecording() async {
        let session = makeSession()
        session.keyDown()
        recorder.onStop = { session.keyDown() }

        await session.cancel()

        #expect(recorder.startCount == 1)
    }
}
