import Foundation
import Testing
@testable import Core

/// Double-tap the dictation key to record without holding it; tap again to stop and paste.
@MainActor
struct HandsFreeTests {
    let recorder = FakeRecorder()
    let stt = FakeSpeechToText()
    let inserter = FakeInserter()
    let clock = FakeClock()

    func makeSession(limit: TimeInterval = PushToTalkSession.handsFreeLimit,
                     commands: CommandParser? = nil) -> PushToTalkSession {
        PushToTalkSession(recorder: recorder, speechToText: stt, inserter: inserter, now: clock.now,
                          language: { .english }, commands: commands, handsFreeLimit: limit)
    }

    /// A quick tap, then a second press soon after: hands-free from the second press.
    func doubleTap(_ session: PushToTalkSession, _ kind: SessionKind = .dictation) async {
        session.keyDown(kind)
        clock.advance(by: 0.1)
        await session.keyUp()
        clock.advance(by: 0.2)
        session.keyDown(kind)
        clock.advance(by: 0.1)
        await session.keyUp()
    }

    @Test func aDoubleTapKeepsRecordingAfterTheKeyIsLetGo() async {
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        await doubleTap(session)

        #expect(events.suffix(2) == [.listening(.dictation), .handsFree])
        #expect(recorder.isRecording)
        #expect(stt.requests.isEmpty)
    }

    @Test func theNextTapStopsAndPastes() async {
        stt.transcript = "A long thought, dictated hands-free."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        await doubleTap(session)
        clock.advance(by: 30)
        session.keyDown()  // the stop tap
        clock.advance(by: 0.1)
        await session.keyUp()

        #expect(inserter.inserted == ["A long thought, dictated hands-free."])
        #expect(events.contains(.released(.dictation)))
        #expect(!recorder.isRecording)
        #expect(recorder.startCount == 2)  // the stop tap didn't start another recording
    }

    @Test func escapeThrowsAHandsFreeRecordingAway() async {
        stt.transcript = "Never pasted."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        await doubleTap(session)
        clock.advance(by: 5)
        await session.cancel()

        #expect(events.last == .ignored(.cancelled))
        #expect(stt.requests.isEmpty)
        #expect(!recorder.isRecording)
    }

    @Test func itStopsByItselfAtTheLimitAndPastes() async {
        stt.transcript = "Forgot the mic was on."
        let session = makeSession(limit: 0.05)

        await doubleTap(session)
        clock.advance(by: 600)
        for _ in 0..<200 where inserter.inserted.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(inserter.inserted == ["Forgot the mic was on."])
        #expect(!recorder.isRecording)
    }

    @Test func aTapLongBeforeAPressIsNotADoubleTap() async {
        stt.transcript = "Held as usual."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 0.1)
        await session.keyUp()  // an accidental tap
        clock.advance(by: 1)
        session.keyDown()
        clock.advance(by: 2)
        await session.keyUp()

        #expect(!events.contains(.handsFree))
        #expect(inserter.inserted == ["Held as usual."])
    }

    @Test func theCommandKeyNeverGoesHandsFree() async {
        stt.transcript = "Message Gurjeet saying hi"
        let session = makeSession(commands: CommandParser(model: { FakeCommandModel(reply: #"{"action":"unknown"}"#) }))
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        await doubleTap(session, .command)

        #expect(!events.contains(.handsFree))
        #expect(!recorder.isRecording)
    }

    @Test func aSecondPressThatIsHeldIsAnOrdinaryDictation() async {
        stt.transcript = "Fumbled, then held."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        clock.advance(by: 0.1)
        await session.keyUp()  // a fumbled tap
        clock.advance(by: 0.2)
        session.keyDown()
        clock.advance(by: 2)
        await session.keyUp()

        #expect(!events.contains(.handsFree))
        #expect(inserter.inserted == ["Fumbled, then held."])
        #expect(!recorder.isRecording)
    }

    @Test func keyCombinationsDuringHandsFreeAreIgnored() async {
        stt.transcript = "Still listening."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        await doubleTap(session)
        session.keyDown()  // fn goes down...
        await session.chord()  // ...with another key (fn+Delete): no stop, and no release follows
        clock.advance(by: 10)
        #expect(recorder.isRecording)
        session.keyDown()  // a clean tap stops it
        clock.advance(by: 0.1)
        await session.keyUp()

        #expect(!events.contains(.ignored(.cancelled)))
        #expect(inserter.inserted == ["Still listening."])
    }

    @Test func theCommandKeyDuringHandsFreeIsIgnored() async {
        stt.transcript = "Uninterrupted."
        let session = makeSession(commands: CommandParser(model: { FakeCommandModel(reply: #"{"action":"unknown"}"#) }))

        await doubleTap(session)
        session.keyDown(.command)
        clock.advance(by: 1)
        await session.keyUp()  // the command key's release
        #expect(recorder.isRecording)
        #expect(stt.requests.isEmpty)
        session.keyDown()
        clock.advance(by: 0.1)
        await session.keyUp()

        #expect(inserter.inserted == ["Uninterrupted."])
    }

    @Test func theTimeLimitStopRunsLikeAnyOther() async {
        let model = CancellationSpyingSpeechToText()
        let session = PushToTalkSession(recorder: recorder, speechToText: model, inserter: inserter, now: clock.now,
                                        language: { .english }, handsFreeLimit: 0.05)

        await doubleTap(session)
        clock.advance(by: 600)  // the session's clock: the recording's length when the limit stops it
        for _ in 0..<200 where inserter.inserted.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(inserter.inserted == ["words"])
        #expect(model.sawCancellation == false)  // cleanup and pasting don't run in a cancelled task
    }
}

/// Notes whether it was asked to transcribe from inside a cancelled task.
@MainActor
final class CancellationSpyingSpeechToText: SpeechToText {
    private(set) var sawCancellation: Bool?

    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        sawCancellation = Task.isCancelled
        return "words"
    }
}
