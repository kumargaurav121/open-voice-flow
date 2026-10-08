import Foundation

/// Sends each clip to the model chosen for the selected language: no single model is best at both
/// English and Hinglish (see docs/eval/reports/2026-10-08-bakeoff.md).
@MainActor
public final class LanguageRoutedSpeechToText: SpeechToText {
    public struct NoModel: Error {
        public let language: Language
    }

    private let routes: [Language: SpeechToText]

    public init(routes: [Language: SpeechToText]) {
        self.routes = routes
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        guard let model = routes[language] else { throw NoModel(language: language) }
        return try await model.transcribe(clip, language: language)
    }
}
