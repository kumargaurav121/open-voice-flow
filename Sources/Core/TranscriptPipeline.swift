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
    /// An email's AI cleanup also lays it out: Thorough took 4.5 s on eval item 36 (about 100 words).
    public static let emailCleanupTimeout: Duration = .seconds(8)

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

    /// Dictation: the rules cleanup, spoken punctuation and line breaks, the AI cleanup the user switched on (nil
    /// when off), lists, then the style of the app in front (`frontmostApp`, its bundle ID; in a browser, the page
    /// its window's title names, `frontWindowTitle`) unless switched off in `styles`. Code editors and terminals get
    /// the raw transcript.
    public func dictation(selectedAI: @escaping () -> TextCleaner?, frontmostApp: @escaping () -> String?,
                          frontWindowTitle: @escaping () -> String?, styles: @escaping () -> AppStyles,
                          log: @escaping (String) -> Void) -> CleanupSpeechToText {
        CleanupSpeechToText(wrapping: transcription, selectedAI: selectedAI,
                            style: {
                                var read = false, title: String?
                                let style = styles().style(forApp: frontmostApp()) {
                                    read = true
                                    title = frontWindowTitle()
                                    return title
                                }
                                // A browser page left unstyled: its title's shape, never its text, so a missed Gmail
                                // can be told apart from an unreadable title.
                                if read, style != .email { log("Browser page without the email style: \(AppCategory.shape(ofTitle: title))") }
                                return style
                            },
                            formatting: true, timeout: Self.cleanupTimeout, emailTimeout: Self.emailCleanupTimeout, log: log)
    }

    /// Commands get the rules cleanup but never AI cleanup: it would add seconds, could reword the command
    /// itself, and would send it to the cloud when Cloud cleanup is on. Nor spoken punctuation: a line break
    /// would cut the message off (the parser reads one line).
    public func commands() -> SpeechToText {
        CleanupSpeechToText(wrapping: transcription, selectedAI: { nil }, style: { .other },
                            formatting: false, timeout: Self.cleanupTimeout, emailTimeout: Self.cleanupTimeout, log: { _ in })
    }
}
