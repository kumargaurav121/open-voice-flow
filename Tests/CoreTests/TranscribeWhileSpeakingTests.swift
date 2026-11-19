import Foundation
import Testing
@testable import Core

/// Holding the dictation key while audio arrives: finished parts are transcribed in the background, and
/// only the tail is left at release.
@MainActor
struct TranscribeWhileSpeakingTests {
    let recorder = FakeRecorder()
    let model = FakeSpeechToText()
    let inserter = FakeInserter()
    let clock = FakeClock()
    let live: LiveTranscriber

    init() {
        live = LiveTranscriber(wrapping: model)
    }

    func makeSession(language: @escaping () -> Language = { .hinglish }) -> PushToTalkSession {
        PushToTalkSession(recorder: recorder, speechToText: live, inserter: inserter, now: clock.now,
                          language: language, live: live)
    }

    static func audio(_ sounds: [PauseCutterTests.Sound]) -> [Float] { PauseCutterTests.audio(sounds) }

    /// Lets background transcription run until the model has had `count` requests.
    func waitForRequests(_ count: Int) async {
        for _ in 0..<1_000 where model.requests.count < count { await Task.yield() }
    }

    @Test func finishedPartsAreTranscribedWhileTheKeyIsStillHeld() async {
        model.replies = ["Hello there.", "How are you?"]
        let session = makeSession()

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(1.2)]))
        await waitForRequests(1)

        #expect(model.requests.count == 1)  // before release
        recorder.deliver(Self.audio([.speech(2)]))
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(inserter.inserted == ["Hello there. How are you?"])
    }

    @Test func onlyTheTailIsTranscribedAfterRelease() async {
        model.replies = ["one", "two", "three"]
        let session = makeSession()

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(4), .pause(0.6), .speech(2)]))
        await waitForRequests(2)
        let beforeRelease = model.requests.count
        clock.advance(by: 10)
        await session.keyUp()

        #expect(beforeRelease == 2)
        #expect(model.requests.count == 3)
        #expect(model.requests.last.map { $0.clip.duration > 1.9 && $0.clip.duration < 2.4 } == true)
        #expect(inserter.inserted == ["one two three"])
    }

    @Test func audioStillWaitingAtReleaseIsTranscribedToo() async {
        model.replies = ["Hello there.", "How are you?"]
        let session = makeSession()

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(1.2)]))
        recorder.record(Self.audio([.speech(2)]))  // recorded, not yet announced when the key goes up
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(inserter.inserted == ["Hello there. How are you?"])
    }

    @Test func escapeWhileSpeakingDiscardsWhatWasTranscribed() async {
        model.replies = ["Thrown away.", "Kept."]
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6)]))
        await waitForRequests(1)
        await session.cancel()
        session.keyDown()
        recorder.deliver(Self.audio([.speech(2)]))
        clock.advance(by: 2)
        await session.keyUp()

        #expect(events.contains(.ignored(.cancelled)))
        #expect(inserter.inserted == ["Kept."])
    }

    @Test func escapeAfterReleaseStillDiscardsTheDictation() async {
        model.transcript = "Never pasted."
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }
        model.onTranscribe = { Task { await session.cancel() } }

        session.keyDown()
        recorder.deliver(Self.audio([.speech(2)]))
        clock.advance(by: 2)
        await session.keyUp()

        #expect(inserter.inserted.isEmpty)
        #expect(events.last == .ignored(.cancelled))
    }

    @Test func theLanguageIsTheOneSelectedWhenTheKeyWentDown() async {
        var selected = Language.english
        let session = makeSession(language: { selected })

        session.keyDown()
        selected = .hinglish
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(2)]))
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(model.requests.count == 2)
        #expect(model.requests.allSatisfy { $0.language == .english })
    }

    // MARK: Long parts (a model that reads a long stretch in one pass: Parakeet in English mode)

    /// English in long parts, Hinglish as before.
    func makeLongPartsSession(language: Language) -> PushToTalkSession {
        let live = LiveTranscriber(wrapping: model, partLengths: { $0 == .english ? .long : .short })
        return PushToTalkSession(recorder: recorder, speechToText: live, inserter: inserter, now: clock.now,
                                 language: { language }, live: live)
    }

    @Test func inLongPartsADictationUnder40SecondsIsTranscribedWholeAtRelease() async {
        model.transcript = "All of it."
        let session = makeLongPartsSession(language: .english)

        session.keyDown()
        recorder.deliver(Self.audio([.speech(10), .pause(1.2), .speech(12), .pause(0.8), .speech(10), .pause(1)]))
        await waitForRequests(1)
        #expect(model.requests.isEmpty)  // nothing cut while speaking
        recorder.deliver(Self.audio([.speech(3)]))
        clock.advance(by: 38)
        await session.keyUp()

        #expect(model.requests.count == 1)
        #expect(inserter.inserted == ["All of it."])
    }

    @Test func inLongPartsTheFirstPauseAfter40SecondsOfSpeechCuts() async {
        model.replies = ["The long part.", "The tail."]
        let session = makeLongPartsSession(language: .english)

        session.keyDown()
        recorder.deliver(Self.audio([.speech(20), .pause(0.6), .speech(21), .pause(1.2), .speech(3)]))
        await waitForRequests(1)
        let beforeRelease = model.requests.count
        clock.advance(by: 46)
        await session.keyUp()

        #expect(beforeRelease == 1)
        #expect(model.requests.first.map { $0.clip.duration > 41 && $0.clip.duration < 42.5 } == true)
        #expect(model.requests.last.map { $0.clip.duration > 2.9 && $0.clip.duration < 3.4 } == true)
        #expect(inserter.inserted == ["The long part. The tail."])
    }

    @Test func inLongPartsSpeechWithoutAPauseIsCutBefore60Seconds() async {
        model.replies = ["Without a breath", "the rest."]
        let session = makeLongPartsSession(language: .english)

        session.keyDown()
        // The room before the first word: the cutter needs to have heard it to tell speech from silence.
        recorder.deliver(Self.audio([.pause(1), .speech(55), .quietSpeech(0.3), .speech(10)]))
        await waitForRequests(1)
        let beforeRelease = model.requests.count
        clock.advance(by: 67)
        await session.keyUp()

        #expect(beforeRelease == 1)
        // Cut inside the quieter words, 55 s in; the room before the speech is trimmed.
        #expect(model.requests.first.map { $0.clip.duration > 54.9 && $0.clip.duration < 56.3 } == true)
        #expect(inserter.inserted == ["Without a breath the rest."])
    }

    @Test func theOtherLanguageStillCutsAtEveryPause() async {
        model.replies = ["Pehla.", "Doosra."]
        let session = makeLongPartsSession(language: .hinglish)

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(1.2), .speech(2)]))
        await waitForRequests(1)
        let beforeRelease = model.requests.count
        clock.advance(by: 6.2)
        await session.keyUp()

        #expect(beforeRelease == 1)
        #expect(inserter.inserted == ["Pehla. Doosra."])
    }

    @Test func commandsAreTranscribedWholeAfterRelease() async {
        model.transcript = "Message Gurjeet saying hi"
        let session = PushToTalkSession(recorder: recorder, speechToText: live, inserter: inserter, now: clock.now,
                                        language: { .hinglish },
                                        commands: CommandParser(model: { FakeCommandModel(reply: #"{"action":"unknown"}"#) }),
                                        live: live)

        session.keyDown(.command)
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(2)]))
        await waitForRequests(1)
        #expect(model.requests.isEmpty)
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(model.requests.map(\.clip) == [recorder.clip])
    }

    @Test func theLogTimingsCountThePartsAndTheTail() async {
        model.replies = ["Hello there.", "How are you?"]
        let session = makeSession()
        var timings: SessionTimings?
        session.onEvent = { if case .inserted(let t) = $0 { timings = t } }

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(2)]))
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(timings?.parts == 1)
        #expect(timings.map { $0.tail > 1.9 && $0.tail < 2.4 } == true)
    }

    @Test func aPauseBeforeReleaseLeavesNothingToTranscribeAfterIt() async {
        model.replies = ["All done."]
        let session = makeSession()

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(1.5)]))
        clock.advance(by: 4.5)
        await session.keyUp()

        #expect(model.requests.count == 1)
        #expect(inserter.inserted == ["All done."])
    }

    @Test func withoutACutTheWholeRecordingIsTranscribedAsBefore() async {
        model.transcript = "Short one."
        let session = makeSession()

        session.keyDown()
        recorder.deliver(Self.audio([.speech(1.5), .pause(0.3)]))
        clock.advance(by: 1.8)
        await session.keyUp()

        #expect(model.requests.map(\.clip) == [recorder.clip])
        #expect(inserter.inserted == ["Short one."])
    }

    /// Dictates `audio` (released straight after) while the model replies with `replies`; returns what was pasted.
    func dictate(_ audio: [PauseCutterTests.Sound], replies: [String]) async -> String? {
        model.replies = replies
        let session = makeSession()
        session.keyDown()
        recorder.deliver(Self.audio(audio))
        clock.advance(by: 10)
        await session.keyUp()
        return inserter.inserted.last
    }

    @Test func aCutMidSentenceDoesNotEndTheSentence() async {
        let pasted = await dictate([.speech(3), .pause(0.6), .speech(2)],
                                   replies: ["The next step is the notch.", "Animation and then the Slack command."])

        #expect(pasted == "The next step is the notch animation and then the Slack command.")
    }

    @Test func aLongPauseKeepsTheSentenceBreak() async {
        let pasted = await dictate([.speech(3), .pause(1.5), .speech(2)],
                                   replies: ["We shipped the fix.", "Then we tested it."])

        #expect(pasted == "We shipped the fix. Then we tested it.")
    }

    @Test func namesAndIKeepTheirCapitalsAcrossACut() async {
        let first = await dictate([.speech(3), .pause(0.6), .speech(2)], replies: ["Yesterday.", "I fixed it."])
        let second = await dictate([.speech(3), .pause(0.6), .speech(2)],
                                   replies: ["Send the deck to.", "Priya, then Priya can review it."])

        #expect(first == "Yesterday I fixed it.")
        #expect(second == "Send the deck to Priya, then Priya can review it.")
    }

    @Test func escapeAfterReleaseStopsTheWorkStillQueued() async {
        let gated = GatedSpeechToText()
        let live = LiveTranscriber(wrapping: gated)
        let session = PushToTalkSession(recorder: recorder, speechToText: live, inserter: inserter, now: clock.now,
                                        language: { .hinglish }, live: live)
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(2)]))
        clock.advance(by: 5.6)
        let release = Task { await session.keyUp() }
        for _ in 0..<1_000 where !gated.isHolding { await Task.yield() }
        await session.cancel()  // while the part is being transcribed and the tail is queued
        gated.open()
        await release.value

        #expect(gated.requests == 1)  // the tail was never sent to the model
        #expect(inserter.inserted.isEmpty)
        #expect(events.last == .ignored(.cancelled))
    }

    @Test func aFailedPartStopsTheRestOfTheDictation() async {
        model.failing = [0]
        let session = makeSession()
        var events: [SessionEvent] = []
        session.onEvent = { events.append($0) }

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(3), .pause(0.6), .speech(2)]))
        clock.advance(by: 9.2)
        await session.keyUp()

        #expect(model.requests.count == 1)
        #expect(events.last == .failed(.transcription))
    }

    @Test func neverTwoTranscriptionsAtOnceEvenWhileADiscardedPartFinishes() async {
        let slow = CountingSlowSpeechToText()
        let live = LiveTranscriber(wrapping: slow)
        let session = PushToTalkSession(recorder: recorder, speechToText: live, inserter: inserter, now: clock.now,
                                        language: { .hinglish }, live: live)

        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6)]))
        for _ in 0..<1_000 where slow.active == 0 { await Task.yield() }
        await session.cancel()  // the part is still being transcribed
        session.keyDown()
        recorder.deliver(Self.audio([.speech(3), .pause(0.6), .speech(2)]))
        clock.advance(by: 5.6)
        await session.keyUp()

        #expect(slow.calls >= 3)
        #expect(slow.mostAtOnce == 1)
    }
}

/// A model that holds its first transcription until the test opens it.
@MainActor
final class GatedSpeechToText: SpeechToText {
    private(set) var requests = 0
    private var gate: CheckedContinuation<Void, Never>?
    var isHolding: Bool { gate != nil }

    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        requests += 1
        if requests == 1 { await withCheckedContinuation { gate = $0 } }
        return "words"
    }

    func open() {
        gate?.resume()
        gate = nil
    }
}

/// A model that takes a few milliseconds per clip, so overlapping transcriptions would show.
@MainActor
final class CountingSlowSpeechToText: SpeechToText {
    private(set) var active = 0
    private(set) var mostAtOnce = 0
    private(set) var calls = 0

    func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        calls += 1
        active += 1
        mostAtOnce = max(mostAtOnce, active)
        defer { active -= 1 }
        try? await Task.sleep(for: .milliseconds(20))
        return "words"
    }
}
