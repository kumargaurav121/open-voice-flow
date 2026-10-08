import Core
import Foundation

/// Which speech model to run.
public enum SpeechModel: Sendable, Equatable {
    /// Oriserve Hinglish Whisper (turbo-sized, Roman-script output), converted by us; loaded from a local folder.
    case hinglish(folder: URL)
    /// Stock Whisper large-v3-turbo from Argmax's hub repo: English mode, and Hinglish mode's fallback
    /// until the Hinglish model is installed.
    case turbo

    public static var modelsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "open-voice-flow/models", directoryHint: .isDirectory)
    }

    public static var hinglishFolder: URL {
        modelsDirectory.appending(path: "oriserve-hinglish", directoryHint: .isDirectory)
    }

    /// Model for Hinglish mode: the Hinglish model once installed (onboarding, ticket 07), turbo until then.
    public static var preferredHinglish: SpeechModel {
        isHinglishModelInstalled(at: hinglishFolder) ? .hinglish(folder: hinglishFolder) : .turbo
    }

    /// Needs every Core ML stage plus the model's own tokenizer.json; without it WhisperKit silently
    /// falls back to the stock tokenizer.
    public static func isHinglishModelInstalled(at folder: URL) -> Bool {
        ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "tokenizer.json"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }
}

/// How to prompt the decoder for a language on a given model (see docs/eval/reports/2026-10-08-bakeoff.md).
struct DecodingSetup: Equatable {
    /// Whisper language code to force, or nil to let the model detect it.
    var languageCode: String?
    var usesPrefillCache: Bool

    init(language: Language, model: SpeechModel) {
        switch (model, language) {
        case (.hinglish, _):
            // Oriserve writes Roman Hinglish under <|en|> (same score as auto-detect, but deterministic);
            // <|hi|> wrecks its English. Our conversions ship without prefill data.
            self.init(languageCode: "en", usesPrefillCache: false)
        case (.turbo, .hinglish):
            // Fallback only: forcing hi on turbo breaks its English, so let it detect.
            self.init(languageCode: nil, usesPrefillCache: true)
        case (.turbo, .english):
            self.init(languageCode: "en", usesPrefillCache: true)
        }
    }

    private init(languageCode: String?, usesPrefillCache: Bool) {
        self.languageCode = languageCode
        self.usesPrefillCache = usesPrefillCache
    }
}
