import Core
import Foundation
import WhisperKit

/// Local speech-to-text with WhisperKit (Core ML).
@MainActor
public final class WhisperKitTranscriber: SpeechToText {
    /// Hub name of the turbo fallback, downloaded on first use.
    nonisolated static let turboModel = "openai_whisper-large-v3-v20240930_turbo"

    public let model: SpeechModel
    private let engine: WhisperEngine
    private var loading: Task<Void, Error>?

    /// - Parameter modelsDirectory: where hub models (turbo) are downloaded.
    public init(model: SpeechModel, modelsDirectory: URL) {
        self.model = model
        engine = WhisperEngine(model: model, modelsDirectory: modelsDirectory)
    }

    /// Loads (downloading turbo if needed) the model. Safe to call more than once.
    public func prepare() async throws {
        if loading == nil {
            let engine = engine
            loading = Task { try await engine.load() }
        }
        do {
            try await loading?.value
        } catch {
            loading = nil
            throw error
        }
    }

    public func transcribe(_ clip: AudioClip, language: Language) async throws -> String {
        try await prepare()
        return try await engine.transcribe(clip.samples, setup: DecodingSetup(language: language, model: model))
    }
}

/// Owns the non-Sendable WhisperKit instance so it never crosses actors.
private actor WhisperEngine {
    private let model: SpeechModel
    private let modelsDirectory: URL
    private var whisper: WhisperKit?

    init(model: SpeechModel, modelsDirectory: URL) {
        self.model = model
        self.modelsDirectory = modelsDirectory
    }

    func load() async throws {
        guard whisper == nil else { return }
        let config: WhisperKitConfig
        switch model {
        case .hinglish(let folder):
            guard SpeechModel.isHinglishModelInstalled(at: folder) else {
                throw WhisperKitTranscriberError.modelMissing(folder)
            }
            // The tokenizer comes from the model folder (written by scripts/convert-model.sh).
            config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: folder,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
        case .turbo:
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            config = WhisperKitConfig(
                model: WhisperKitTranscriber.turboModel,
                downloadBase: modelsDirectory,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true
            )
        }
        whisper = try await WhisperKit(config)
    }

    func transcribe(_ samples: [Float], setup: DecodingSetup) async throws -> String {
        guard let loaded = whisper else { throw WhisperKitTranscriberError.notLoaded }
        // WhisperKit isn't Sendable. Only this actor touches it, but actor calls can interleave
        // across the await below; DictationSession never transcribes two clips at once.
        nonisolated(unsafe) let whisper = loaded
        let options = DecodingOptions(
            task: .transcribe,
            language: setup.languageCode,
            usePrefillCache: setup.usesPrefillCache,
            detectLanguage: setup.languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }
}

public enum WhisperKitTranscriberError: Error {
    case notLoaded
    case modelMissing(URL)
}
