import Foundation

/// Spells the user's dictionary terms their way in every transcript (see `DictionaryCorrection`). Runs
/// before cleanup, so the AI cleanup and its guard already see the right names.
@MainActor
public final class DictionarySpeechToText: SpeechToText {
    private let model: SpeechToText
    private let terms: () -> [String]
    private let isEnglishWord: @MainActor (String) -> Bool

    /// - Parameters:
    ///   - terms: the dictionary, read per transcript so edits apply straight away.
    ///   - isEnglishWord: a spell check; real English words are never respelled.
    public init(wrapping model: SpeechToText, terms: @escaping () -> [String],
                isEnglishWord: @escaping @MainActor (String) -> Bool = { _ in false }) {
        self.model = model
        self.terms = terms
        self.isEnglishWord = isEnglishWord
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        let transcript = try await model.transcribe(clip, language: language)
        let isEnglishWord = isEnglishWord
        // The correction runs synchronously right here, on the main actor.
        return DictionaryCorrection.correct(transcript, terms: terms(), isEnglishWord: { word in
            MainActor.assumeIsolated { isEnglishWord(word) }
        })
    }
}
