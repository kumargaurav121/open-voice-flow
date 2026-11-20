import Foundation

/// Optional AI rewrite of a transcript (fillers, punctuation, casing). Provided by the LLM package.
@MainActor
public protocol TextCleaner: AnyObject {
    func clean(_ text: String) async throws -> String
}

/// Cleans every transcript: always the rules pass (for dictation with its formatting), plus the AI pass when
/// the user has it switched on. Code editors and terminals get the raw transcript (a "cleaned" shell command
/// is a broken one). Any AI timeout, failure or meaning-changing rewrite falls back to the rules output, and
/// says why.
@MainActor
public final class CleanupSpeechToText: SpeechToText {
    private let model: SpeechToText
    private let selectedAI: () -> TextCleaner?
    private let isCodeContext: () -> Bool
    private let formatting: Bool
    private let timeout: Duration
    private let log: (String) -> Void

    public init(
        wrapping model: SpeechToText,
        selectedAI: @escaping () -> TextCleaner?,
        isCodeContext: @escaping () -> Bool,
        formatting: Bool,
        timeout: Duration,
        log: @escaping (String) -> Void
    ) {
        self.model = model
        self.selectedAI = selectedAI
        self.isCodeContext = isCodeContext
        self.formatting = formatting
        self.timeout = timeout
        self.log = log
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        let raw = try await model.transcribe(clip, language: language)
        guard !isCodeContext() else { return raw }
        let rules = Self.rules(raw, formatting: formatting)
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
            log("AI cleanup failed (\(logSafe(error))); used rules cleanup")
            return rules
        }
        // Some models end a line with spaces (Markdown's line break).
        let trimmed = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        guard AICleanupGuard.accepts(original: rules, rewritten: trimmed) else {
            log("AI cleanup rejected (changed the meaning or the line breaks); used rules cleanup")
            return rules
        }
        log("AI cleanup took \(ContinuousClock.now - started)")
        return trimmed
    }

    /// The rules pass: the rules cleanup, then with `formatting` (dictation) spoken punctuation and line
    /// breaks. Commands have no formatting: their parser reads one line.
    nonisolated public static func rules(_ raw: String, formatting: Bool) -> String {
        let cleaned = RulesCleanup.clean(raw)
        return formatting ? SpokenPunctuation.apply(cleaned) : cleaned
    }
}
