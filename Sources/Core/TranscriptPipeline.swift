import Foundation

/// Everything between the speech model and the focused app: English letters (always), the user's
/// dictionary, then cleanup. The app, the eval runner and the tests all build it here, so an eval run
/// produces exactly the text the app would paste.
@MainActor
public struct TranscriptPipeline {
    /// How long AI cleanup gets before the rules output is used instead (Thorough took up to 2.4 s on long
    /// eval clips).
    public static let cleanupTimeout: Duration = .seconds(4)

    /// Speech to text plus the dictionary and English letters: what dictation and commands share.
    private let transcription: SpeechToText

    /// - Parameters:
    ///   - speech: the speech model (or the router choosing one).
    ///   - terms: the dictionary, read per transcript so edits apply straight away.
    ///   - isEnglishWord: a spell check; real English words are never respelled.
    public init(speech: SpeechToText, terms: @escaping () -> [String],
                isEnglishWord: @escaping @MainActor (String) -> Bool) {
        // The dictionary respells names before cleanup, so the AI and its guard see them right too.
        transcription = DictionarySpeechToText(
            // Always English letters and digits, whichever model or script (user requirement).
            wrapping: LatinScriptSpeechToText(wrapping: speech),
            terms: terms,
            isEnglishWord: isEnglishWord
        )
    }

    /// Dictation: the rules cleanup plus the AI cleanup the user switched on (nil when off). Code editors
    /// and terminals get the raw transcript.
    public func dictation(selectedAI: @escaping () -> TextCleaner?, isCodeContext: @escaping () -> Bool,
                          log: @escaping (String) -> Void) -> SpeechToText {
        CleanupSpeechToText(wrapping: transcription, selectedAI: selectedAI, isCodeContext: isCodeContext,
                            timeout: Self.cleanupTimeout, log: log)
    }

    /// Commands get the rules cleanup but never AI cleanup: it would add seconds, could reword the command
    /// itself, and would send it to the cloud when Cloud cleanup is on.
    public func commands() -> SpeechToText {
        CleanupSpeechToText(wrapping: transcription, selectedAI: { nil }, isCodeContext: { false },
                            timeout: Self.cleanupTimeout, log: { _ in })
    }
}
