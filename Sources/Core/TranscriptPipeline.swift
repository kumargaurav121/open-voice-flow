import Foundation

/// Everything between the speech model and the focused app: the speech, transcribed live (in parts while the
/// user speaks, joined at release), then on the whole text English letters (always), the user's dictionary
/// and cleanup. The app, the eval runner and the tests all build it here, so an eval run produces exactly
/// the text the app would paste.
@MainActor
public struct TranscriptPipeline {
    /// How long AI cleanup gets before the rules output is used instead (Thorough took up to 2.4 s on long
    /// eval clips).
    public static let cleanupTimeout: Duration = .seconds(4)

    /// Every transcription, one at a time; dictation feeds it live audio (`PushToTalkSession`'s `live`).
    public let live: LiveTranscriber
    /// The live transcription in English letters with the dictionary's spellings.
    private let transcription: SpeechToText

    /// - Parameters:
    ///   - speech: the speech model (or the router choosing one).
    ///   - terms: the dictionary, read per transcript so edits apply straight away.
    ///   - isEnglishWord: a spell check; real English words are never respelled.
    ///   - sentencePause: see `LiveTranscriber.sentencePause`.
    ///   - partLengths: how long parts get in each language (see `LiveTranscriber.init`).
    public init(speech: SpeechToText, terms: @escaping () -> [String],
                isEnglishWord: @escaping @MainActor (String) -> Bool,
                sentencePause: TimeInterval = LiveTranscriber.sentencePause,
                partLengths: @escaping (Language) -> PauseCutter.Lengths = { _ in .short }) {
        live = LiveTranscriber(wrapping: speech, sentencePause: sentencePause, partLengths: partLengths)
        // The dictionary respells names before cleanup, so the AI and its guard see them right too.
        transcription = DictionarySpeechToText(
            // Always English letters and digits, whichever model or script (user requirement).
            wrapping: LatinScriptSpeechToText(wrapping: live),
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
