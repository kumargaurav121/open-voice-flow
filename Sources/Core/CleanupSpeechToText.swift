import Foundation

/// Optional AI rewrite of a transcript (fillers, punctuation, casing). Provided by the LLM package.
@MainActor
public protocol TextCleaner: AnyObject {
    /// - Parameter style: the style of the app the text goes to (an email's is laid out by the AI).
    func clean(_ text: String, style: AppCategory) async throws -> String
}

/// Cleans every transcript: always the rules pass (for dictation with its formatting), plus the AI pass when
/// the user has it switched on, then for dictation the layout (lists) and the app's style. A snippet's cue said as
/// the whole dictation pastes the snippet instead, as saved, in any app. Code editors and
/// terminals get the raw transcript (a "cleaned" shell command is a broken one). Any AI timeout, failure or
/// meaning-changing rewrite falls back to the rules output, and says why.
@MainActor
public final class CleanupSpeechToText: SpeechToText {
    private let model: SpeechToText
    private let selectedAI: () -> TextCleaner?
    /// The style of the app the text goes to, read per transcript.
    private let style: () -> AppCategory
    /// The user's snippets, read per transcript so edits apply straight away.
    private let snippets: () -> [Snippet]
    private let formatting: Bool
    private let timeout: Duration
    /// The AI's time for an email, which it also lays out.
    private let emailTimeout: Duration
    private let log: (String) -> Void
    /// The last transcript before formatting (spoken punctuation, line breaks, AI cleanup, lists), for Undo
    /// Formatting: only the rules cleanup's fillers, spacing, capitals and digits. In a code editor, the raw
    /// transcript it got. For a snippet, the cue as said, through the rules cleanup.
    public private(set) var unformatted: String?
    /// Whether the last transcript was a snippet's cue, so what was pasted is the snippet (not learned from).
    public private(set) var lastWasSnippet = false

    public init(
        wrapping model: SpeechToText,
        selectedAI: @escaping () -> TextCleaner?,
        style: @escaping () -> AppCategory,
        snippets: @escaping () -> [Snippet],
        formatting: Bool,
        timeout: Duration,
        emailTimeout: Duration,
        log: @escaping (String) -> Void
    ) {
        self.model = model
        self.selectedAI = selectedAI
        self.style = style
        self.snippets = snippets
        self.formatting = formatting
        self.timeout = timeout
        self.emailTimeout = emailTimeout
        self.log = log
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        unformatted = nil
        lastWasSnippet = false
        let raw = try await model.transcribe(clip, language: language)
        let style = style()
        if style != .other { log("Style: \(style)") }  // the app's kind, never the text
        if let snippet = Snippet.matching(raw, in: snippets()) {
            log("Snippet: pasting its text as saved")  // never its cue or text
            unformatted = style == .code ? raw : RulesCleanup.clean(raw)
            lastWasSnippet = true
            return snippet.text
        }
        guard style != .code else {
            unformatted = raw
            return raw
        }
        unformatted = RulesCleanup.clean(raw)
        let cleaned = await aiCleaned(Self.rules(raw, formatting: formatting), style: style)
        return formatting ? Self.layout(cleaned, style: style, raw: raw) : cleaned
    }

    /// The AI's rewrite when AI cleanup is on and the guard accepts it; otherwise the rules text.
    private func aiCleaned(_ rules: String, style: AppCategory) async -> String {
        // The menu's current choice, read per transcript: nil when AI cleanup is off.
        guard let ai = selectedAI(), !rules.isEmpty else { return rules }

        let rewritten: String
        let started = ContinuousClock.now
        let timeout = style == .email ? emailTimeout : timeout
        do {
            rewritten = try await withTimeout(timeout) { try await ai.clean(rules, style: style) }
        } catch is TimedOut {
            log("AI cleanup timed out after \(timeout); used rules cleanup")
            return rules
        } catch {
            log("AI cleanup failed (\(logSafe(error))); used rules cleanup")
            return rules
        }
        guard let accepted = Self.accepted(rewritten, over: rules, style: style) else {
            log("AI cleanup rejected (changed the meaning or the line breaks); used rules cleanup")
            return rules
        }
        log("AI cleanup took \(ContinuousClock.now - started)")
        return accepted
    }

    /// The AI's rewrite, tidied, if the guard accepts it in place of the rules text. An email's may add breaks.
    nonisolated public static func accepted(_ rewritten: String, over rules: String, style: AppCategory) -> String? {
        // Some models end a line with spaces (Markdown's line break).
        let trimmed = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        return AICleanupGuard.accepts(original: rules, rewritten: trimmed, mayAddBreaks: style == .email) ? trimmed : nil
    }

    /// The rules pass: the rules cleanup, then with `formatting` (dictation) spoken punctuation and line
    /// breaks. Commands have no formatting: their parser reads one line.
    nonisolated public static func rules(_ raw: String, formatting: Bool) -> String {
        let cleaned = RulesCleanup.clean(raw)
        return formatting ? SpokenPunctuation.apply(cleaned) : cleaned
    }

    /// Dictation's layout after the AI pass (or the rules text it fell back to): spoken lists as numbered lines,
    /// then the app's style. `raw` tells the style which marks were said (a full stop said stays in a chat).
    nonisolated public static func layout(_ cleaned: String, style: AppCategory, raw: String) -> String {
        AppStyle.apply(SpokenLists.apply(cleaned), for: style,
                       saidFullStop: SpokenPunctuation.endsWithSpokenFullStop(RulesCleanup.clean(raw)))
    }
}
