import Foundation

/// Optional AI rewrite of a transcript (fillers, punctuation, casing). Provided by the LLM package.
@MainActor
public protocol TextCleaner: AnyObject {
    func clean(_ text: String) async throws -> String
}

/// Cleans every transcript: always the rules pass, plus the AI pass when the user has it switched on.
/// Code editors and terminals get the raw transcript (a "cleaned" shell command is a broken one). Any
/// AI timeout, failure or meaning-changing rewrite falls back to the rules output, and says why.
@MainActor
public final class CleanupSpeechToText: SpeechToText {
    private let model: SpeechToText
    private let selectedAI: () -> TextCleaner?
    private let isCodeContext: () -> Bool
    private let timeout: Duration
    private let log: (String) -> Void

    public init(
        wrapping model: SpeechToText,
        selectedAI: @escaping () -> TextCleaner?,
        isCodeContext: @escaping () -> Bool,
        timeout: Duration,
        log: @escaping (String) -> Void
    ) {
        self.model = model
        self.selectedAI = selectedAI
        self.isCodeContext = isCodeContext
        self.timeout = timeout
        self.log = log
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        let raw = try await model.transcribe(clip, language: language)
        guard !isCodeContext() else { return raw }
        let rules = RulesCleanup.clean(raw)
        // The menu's current choice, read per transcript: nil when AI cleanup is off.
        guard let ai = selectedAI(), !rules.isEmpty else { return rules }

        let rewritten: String
        let started = ContinuousClock.now
        do {
            rewritten = try await withTimeout(timeout) { try await ai.clean(rules) }
        } catch is TimedOut {
            log("AI cleanup timed out after \(timeout); used rules cleanup")
            return rules
        } catch {
            log("AI cleanup failed (\(error)); used rules cleanup")
            return rules
        }
        let trimmed = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AICleanupGuard.accepts(original: rules, rewritten: trimmed) else {
            log("AI cleanup rejected (changed the meaning): \"\(trimmed.prefix(80))\"; used rules cleanup")
            return rules
        }
        log("AI cleanup took \(ContinuousClock.now - started)")
        return trimmed
    }

    private struct TimedOut: Error {}

    /// Returns the work's result, or throws `TimedOut` after `limit` even if the work ignores cancellation
    /// (a model mid-generation may not check for it); the work is cancelled either way.
    private func withTimeout(_ limit: Duration, _ work: @escaping @MainActor () async throws -> String) async throws -> String {
        let race = Race()
        return try await withCheckedThrowingContinuation { continuation in
            let worker = Task { @MainActor in
                let result: Result<String, Error>
                do { result = .success(try await work()) } catch { result = .failure(error) }
                race.timer?.cancel()
                race.finish(continuation, with: result)
            }
            race.timer = Task { @MainActor in
                guard (try? await Task.sleep(for: limit)) != nil else { return }  // cancelled: work won
                worker.cancel()
                race.finish(continuation, with: .failure(TimedOut()))
            }
        }
    }
}

/// Resumes a continuation exactly once: whichever of the work and the timer finishes first wins.
@MainActor
private final class Race {
    private var done = false
    var timer: Task<Void, Never>?

    func finish(_ continuation: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        guard !done else { return }
        done = true
        continuation.resume(with: result)
    }
}
