import Core
import Foundation
import WhisperKit

/// Local speech-to-text with WhisperKit (Core ML). The model downloads on first use.
@MainActor
public final class WhisperKitTranscriber: SpeechToText {
    /// Interim default (ADR 0003): plain large-v3-turbo until the converted Hinglish model ships in ticket 03.
    public static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    private let engine: WhisperEngine
    private var loading: Task<Void, Error>?

    public init(model: String = defaultModel, modelsDirectory: URL) {
        engine = WhisperEngine(model: model, modelsDirectory: modelsDirectory)
    }

    /// Downloads (if needed) and loads the model. Safe to call more than once.
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
        return try await engine.transcribe(clip.samples, languageCode: language.whisperCode)
    }
}

/// Owns the non-Sendable WhisperKit instance so it never crosses actors.
private actor WhisperEngine {
    private let model: String
    private let modelsDirectory: URL
    private var whisper: WhisperKit?

    init(model: String, modelsDirectory: URL) {
        self.model = model
        self.modelsDirectory = modelsDirectory
    }

    func load() async throws {
        guard whisper == nil else { return }
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        whisper = try await WhisperKit(WhisperKitConfig(
            model: model,
            downloadBase: modelsDirectory,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: true
        ))
    }

    func transcribe(_ samples: [Float], languageCode: String?) async throws -> String {
        guard let loaded = whisper else { throw WhisperKitTranscriberError.notLoaded }
        // WhisperKit isn't Sendable. Only this actor touches it, but actor calls can interleave
        // across the await below; DictationSession never transcribes two clips at once.
        nonisolated(unsafe) let whisper = loaded
        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode,
            detectLanguage: languageCode == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ")
    }
}

public enum WhisperKitTranscriberError: Error {
    case notLoaded
}

extension Language {
    /// Whisper language code; nil lets the model detect it.
    var whisperCode: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .hindi: "hi"
        }
    }
}
