import Core
import FluidAudio
import Foundation
import ModelStore

/// English mode's speech-to-text: NVIDIA Parakeet TDT on Core ML, through FluidAudio (ADR 0013). It reads a long
/// stretch of speech in one pass, with no 30-second window and no word-by-word decoding: 0.3 s for 45 s of
/// speech. It loads only from the model store's folder of pinned, checksum-verified files (`AsrModels.loadLocal`
/// never downloads).
@MainActor
public final class ParakeetTranscriber: SpeechToText {
    public enum Version: Sendable {
        /// English only: the app's (v2 ticket 06).
        case v2
        /// 25 European languages, no Hindi: tried by the eval only.
        case v3
    }

    /// FluidAudio's own time for each transcription, for the session log.
    public var onBreakdown: (String) -> Void = { _ in }
    private let folder: URL
    private let version: AsrModelVersion
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    /// From the start of the first load until it ends (about 30 s the first time: the Neural Engine compile).
    public private(set) var isLoading = false

    public init(folder: URL = BuiltInModels.parakeet.installedFolder, version: Version = .v2) {
        self.folder = folder
        self.version = switch version {
        case .v2: .v2
        case .v3: .v3
        }
    }

    /// Loads the installed model and warms it up. Safe to call more than once, also while a load is running.
    public func prepare() async throws {
        _ = try await loaded()
    }

    /// Parakeet v2 hears English only; the router sends it nothing else.
    public func transcribe(_ clip: AudioClip, language: Core.Language) async throws -> String {
        let (text, breakdown) = try await Self.transcribe(clip.samples, with: try await loaded(), version: version)
        onBreakdown(breakdown)
        return text
    }

    private func loaded() async throws -> AsrManager {
        if let manager { return manager }
        let load = loading ?? startLoading()
        do {
            let manager = try await load.value
            self.manager = manager
            isLoading = false
            return manager
        } catch {
            // Only if no other caller has started a new load since this one failed.
            if loading == load {
                loading = nil
                isLoading = false
            }
            throw error
        }
    }

    private func startLoading() -> Task<AsrManager, Error> {
        let folder = folder, version = version
        let load = Task {
            // Off the main thread: loading reads and compiles the models synchronously.
            let models = try await Task.detached { try AsrModels.loadLocal(from: folder, version: version) }.value
            let manager = AsrManager(models: models)
            // As for Whisper: the first inference sets up the Neural Engine, so spend it on a second of silence.
            _ = try? await Self.transcribe(Array(repeating: 0, count: Int(AudioClip.speechSampleRate)),
                                           with: manager, version: version)
            return manager
        }
        loading = load
        isLoading = true
        return load
    }

    private static func transcribe(_ samples: [Float], with manager: AsrManager,
                                   version: AsrModelVersion) async throws -> (text: String, breakdown: String) {
        // FluidAudio refuses under 0.3 s; a part cut at a pause can be shorter, so pad it with silence.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Int(AudioClip.speechSampleRate))
        let padded = samples + Array(repeating: 0, count: max(0, minimum - samples.count))
        // Each call is a separate clip or part: a fresh decoder state, as FluidAudio does for one-shot calls.
        var state = try TdtDecoderState(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(padded, decoderState: &state)
        return (result.text, String(format: "audio %.1fs processing %.2fs", result.duration, result.processingTime))
    }
}
