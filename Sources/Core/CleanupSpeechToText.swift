import Foundation

/// Optional AI rewrite of a transcript (fillers, punctuation, casing). Provided by the LLM package.
@MainActor
public protocol TextCleaner: AnyObject {
    func clean(_ text: String) async throws -> String
}

/// Cleans every transcript: always the rules pass (for dictation with its formatting), plus the AI pass when
/// the user has it switched on, then for dictation the layout (lists). Code editors and terminals get the raw
/// transcript (a "cleaned" shell command is a broken one). Any AI timeout, failure or meaning-changing rewrite
/// falls back to the rules output, and says why.
@MainActor
public final class CleanupSpeechToText: SpeechToText {
    private let model: SpeechToText
    private let selectedAI: () -> TextCleaner?
    private let isCodeContext: () -> Bool
    private let formatting: Bool
    private let timeout: Duration
    private let log: (String) -> Void
    /// The last transcript before formatting (spoken punctuation, line breaks, AI cleanup, lists), for Undo
    /// Formatting: only the rules cleanup's fillers, spacing, capitals and digits. In a code editor, the raw
    /// transcript it got.
    public private(set) var unformatted: String?

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
        unformatted = nil
        let raw = try await model.transcribe(clip, language: language)
        guard !isCodeContext() else {
            unformatted = raw
            return raw
        }
        unformatted = RulesCleanup.clean(raw)
        let cleaned = await aiCleaned(Self.rules(raw, formatting: formatting))
        return formatting ? Self.layout(cleaned) : cleaned
    }

    /// The AI's rewrite when AI cleanup is on and the guard accepts it; otherwise the rules text.
    private func aiCleaned(_ rules: String) async -> String {
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
        guard let accepted = Self.accepted(rewritten, over: rules) else {
            log("AI cleanup rejected (changed the meaning or the line breaks); used rules cleanup")
            return rules
        }
        log("AI cleanup took \(ContinuousClock.now - started)")
        return accepted
    }

    /// The AI's rewrite, tidied, if the guard accepts it in place of the rules text.
    nonisolated public static func accepted(_ rewritten: String, over rules: String) -> String? {
        // Some models end a line with spaces (Markdown's line break).
        let trimmed = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        return AICleanupGuard.accepts(original: rules, rewritten: trimmed) ? trimmed : nil
    }

    /// The rules pass: the rules cleanup, then with `formatting` (dictation) spoken punctuation and line
    /// breaks. Commands have no formatting: their parser reads one line.
    nonisolated public static func rules(_ raw: String, formatting: Bool) -> String {
        let cleaned = RulesCleanup.clean(raw)
        return formatting ? SpokenPunctuation.apply(cleaned) : cleaned
    }

    /// Dictation's layout after the AI pass (or the rules text it fell back to): spoken lists as numbered lines.
    nonisolated public static func layout(_ cleaned: String) -> String {
        SpokenLists.apply(cleaned)
    }
}
