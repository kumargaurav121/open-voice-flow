import Testing
@testable import Core

@MainActor
final class FakeCleaner: TextCleaner {
    var reply: (String) -> String = { $0 }
    var delay: Duration = .zero
    var error: Error?
    private(set) var inputs: [String] = []

    func clean(_ text: String) async throws -> String {
        inputs.append(text)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return reply(text)
    }
}

@MainActor
struct CleanupSpeechToTextTests {
    let clip = AudioClip(samples: [0.1], sampleRate: 16_000)
    let model = FakeSpeechToText()
    let ai = FakeCleaner()
    var aiEnabled = false
    var codeContext = false
    var logs: [String] = []

    mutating func transcribe(_ spoken: String, timeout: Duration = .seconds(1)) async throws -> (String, [String]) {
        model.transcript = spoken
        var logged: [String] = []
        let selected: TextCleaner? = aiEnabled ? ai : nil, code = codeContext
        let cleanup = CleanupSpeechToText(wrapping: model, selectedAI: { selected }, isCodeContext: { code },
                                          timeout: timeout, log: { logged.append($0) })
        let text = try await cleanup.transcribe(clip, language: .hinglish)
        return (text, logged)
    }

    @Test mutating func aiOffRunsOnlyTheRules() async throws {
        aiEnabled = false

        let (text, _) = try await transcribe("um, ship it today")

        #expect(text == "Ship it today")
        #expect(ai.inputs.isEmpty)
    }

    @Test mutating func aiOnCleansTheRulesOutput() async throws {
        aiEnabled = true
        ai.reply = { _ in "Ship it today." }

        let (text, _) = try await transcribe("um, so ship it today")

        #expect(ai.inputs == ["So ship it today"])
        #expect(text == "Ship it today.")
    }

    @Test mutating func codeEditorsGetTheRawTranscript() async throws {
        aiEnabled = true
        codeContext = true

        let (text, _) = try await transcribe("um git commit dash m fix")

        #expect(text == "um git commit dash m fix")
        #expect(ai.inputs.isEmpty)
    }

    @Test mutating func aSlowAIFallsBackToTheRulesAndSaysWhy() async throws {
        aiEnabled = true
        ai.delay = .seconds(2)

        let (text, logs) = try await transcribe("um, ship it today", timeout: .milliseconds(50))

        #expect(text == "Ship it today")
        #expect(logs.contains { $0.contains("timed out") })
    }

    @Test mutating func aFailingAIFallsBackToTheRulesAndSaysWhy() async throws {
        aiEnabled = true
        ai.error = FakeError()

        let (text, logs) = try await transcribe("um, ship it today")

        #expect(text == "Ship it today")
        #expect(logs.contains { $0.contains("failed") })
    }

    @Test mutating func aRewriteTheGuardRejectsFallsBackToTheRules() async throws {
        aiEnabled = true
        ai.reply = { _ in "Sure! Here's a nicer version: Let's deploy everything immediately." }

        let (text, logs) = try await transcribe("um, ship it today")

        #expect(text == "Ship it today")
        #expect(logs.contains { $0.contains("rejected") })
        #expect(!logs.contains { $0.contains("deploy") })  // the log never holds transcript text
    }

    @Test mutating func aFailureIsLoggedWithoutTheProvidersOwnMessage() async throws {
        // A provider's error can echo part of the API key ("Incorrect API key provided: sk-proj-****abcd").
        aiEnabled = true
        ai.error = ChattyError()

        let (_, logs) = try await transcribe("um, ship it today")

        #expect(logs.contains { $0.contains("failed") && $0.contains("HTTP 401") })
        #expect(!logs.contains { $0.contains("sk-proj") })
    }
}

/// An error whose description holds secrets, with a safe summary for the log.
private struct ChattyError: LogSafeError, CustomStringConvertible {
    var description: String { "Incorrect API key provided: sk-proj-****abcd" }
    var logDescription: String { "HTTP 401 from OpenAI" }
}

struct CodeContextTests {
    @Test(arguments: ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2",
                      "com.jetbrains.intellij", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.mitchellh.ghostty",
                      "dev.warp.Warp-Stable"])
    func codeEditorsAndTerminalsAreRecognised(bundleID: String) {
        #expect(CodeContext.isCodeEditor(bundleID: bundleID))
    }

    @Test(arguments: ["com.apple.TextEdit", "com.tinyspeck.slackmacgap", "com.google.Chrome", "com.apple.mail"])
    func everydayAppsAreNot(bundleID: String) {
        #expect(!CodeContext.isCodeEditor(bundleID: bundleID))
    }
}

@MainActor
struct CleanupSelectionTests {
    @Test func theCleanerInUseFollowsTheMenuChoiceAtTranscriptionTime() async throws {
        let model = FakeSpeechToText()
        model.transcript = "ship it today"
        let fast = FakeCleaner(), thorough = FakeCleaner()
        var choice: TextCleaner? = fast
        let cleanup = CleanupSpeechToText(wrapping: model, selectedAI: { choice }, isCodeContext: { false },
                                          timeout: .seconds(1), log: { _ in })
        let clip = AudioClip(samples: [0.1], sampleRate: 16_000)

        _ = try await cleanup.transcribe(clip, language: .english)
        choice = thorough
        _ = try await cleanup.transcribe(clip, language: .english)
        choice = nil
        _ = try await cleanup.transcribe(clip, language: .english)

        #expect(fast.inputs.count == 1)
        #expect(thorough.inputs.count == 1)
    }
}

struct CleanupModeTests {
    @Test func offIsTheDefaultForUnknownOrMissingSettings() {
        #expect(CleanupMode(storedValue: nil) == .off)
        #expect(CleanupMode(storedValue: "whatever") == .off)
        #expect(CleanupMode(storedValue: "thorough") == .thorough)
    }
}
