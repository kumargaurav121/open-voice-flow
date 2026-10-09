import Core
import Foundation
import WhisperKit

/// Local speech-to-text with WhisperKit (Core ML).
@MainActor
public final class WhisperKitTranscriber: SpeechToText {
    public let model: SpeechModel
    /// Where each transcription's time went (encode, decode, fallbacks), for the session log.
    public var onBreakdown: (String) -> Void = { _ in }
    private let engine: WhisperEngine
    private var loading: Task<Void, Error>?

    public init(model: SpeechModel) {
        self.model = model
        engine = WhisperEngine(model: model)
    }

    /// Loads the installed model. Safe to call more than once.
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
        let (text, breakdown) = try await engine.transcribe(clip.samples, setup: DecodingSetup(language: language, model: model))
        onBreakdown(breakdown)
        return text
    }
}

/// Owns the non-Sendable WhisperKit instance so it never crosses actors.
private actor WhisperEngine {
    private let model: SpeechModel
    private var whisper: WhisperKit?

    init(model: SpeechModel) {
        self.model = model
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
            // Neural Engine for encoder and decoder: on the GPU the encoder's fixed 30 s window cost ~2 s per
            // clip, over the 1.5 s target. The first ANE load compiles once (minutes) and is then cached.
            config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: folder,
                computeOptions: ModelComputeOptions(
                    melCompute: .cpuAndGPU,
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine,
                    prefillCompute: .cpuOnly
                ),
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
        case .turbo:
            // Installed by onboarding from pinned, checksummed files (ADR 0010); never fetched here.
            let folder = SpeechModel.turboFolder
            guard FileManager.default.fileExists(atPath: folder.appending(path: "AudioEncoder.mlmodelc").path) else {
                throw WhisperKitTranscriberError.modelMissing(folder)
            }
            config = WhisperKitConfig(
                modelFolder: folder.path,
                tokenizerFolder: SpeechModel.turboTokenizerFolder,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
        }
        whisper = try await WhisperKit(config)
        // The first inference after loading is slow (the Neural Engine sets up on first use); spend it on a
        // second of silence now so the user's first dictation is as fast as the rest.
        _ = try? await transcribe(Array(repeating: 0, count: Int(AudioClip.speechSampleRate)),
                                  setup: DecodingSetup(language: .english, model: model))
    }

    func transcribe(_ samples: [Float], setup: DecodingSetup) async throws -> (text: String, breakdown: String) {
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
        let text = results.map(\.text).joined(separator: " ")
        guard let timings = results.first?.timings else { return (text, "") }
        let breakdown = String(
            format: "audio %.1fs encode %.2fs (%.0f runs) decode %.2fs (%.0f tokens, %.0f fallbacks, %.0f windows) pipeline %.2fs",
            timings.inputAudioSeconds, timings.encoding, timings.totalEncodingRuns, timings.decodingLoop,
            timings.totalDecodingLoops, timings.totalDecodingFallbacks, timings.totalDecodingWindows, timings.fullPipeline
        )
        return (text, breakdown)
    }
}

public enum WhisperKitTranscriberError: LocalizedError {
    case notLoaded
    case modelMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: "The speech model isn't loaded"
        case .modelMissing(let folder): "The speech model isn't installed (\(folder.lastPathComponent))"
        }
    }
}
