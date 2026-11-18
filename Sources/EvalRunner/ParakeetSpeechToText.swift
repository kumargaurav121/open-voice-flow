import Core
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT through FluidAudio (Core ML), for the English-mode test (v2 ticket 06). Loads only from a
/// folder of pinned, checksum-verified files: `AsrModels.loadLocal` never downloads or resolves a repository.
@MainActor
final class ParakeetSpeechToText: SpeechToText {
    /// FluidAudio's own time for each transcription, for the runner's log.
    var onBreakdown: (String) -> Void = { _ in }
    private let folder: URL
    private let version: AsrModelVersion
    private var manager: AsrManager?

    /// `--stt parakeet-v2` or `parakeet-v3`; nil for any other engine.
    init?(stt: String?, folder: URL) {
        switch stt {
        case "parakeet-v2": version = .v2
        case "parakeet-v3": version = .v3
        default: return nil
        }
        self.folder = folder
    }

    func prepare() async throws {
        guard manager == nil else { return }
        let manager = AsrManager(models: try AsrModels.loadLocal(from: folder, version: version))
        // As for Whisper: the first inference sets up the Neural Engine, so spend it on a second of silence.
        _ = try? await transcribe(manager, Array(repeating: 0, count: Int(AudioClip.speechSampleRate)))
        self.manager = manager
    }

    func transcribe(_ clip: AudioClip, language: Core.Language) async throws -> String {
        try await prepare()
        guard let manager else { throw ParakeetError.notLoaded }
        return try await transcribe(manager, clip.samples)
    }

    private func transcribe(_ manager: AsrManager, _ samples: [Float]) async throws -> String {
        // FluidAudio refuses under 0.3 s; a part cut at a pause can be shorter, so pad it with silence.
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: Int(AudioClip.speechSampleRate))
        let padded = samples + Array(repeating: 0, count: max(0, minimum - samples.count))
        // Each call is a separate clip or part: a fresh decoder state, as FluidAudio does for one-shot calls.
        var state = try TdtDecoderState(decoderLayers: version.decoderLayers)
        let result = try await manager.transcribe(padded, decoderState: &state)
        onBreakdown(String(format: "audio %.1fs processing %.2fs", result.duration, result.processingTime))
        return result.text
    }
}

enum ParakeetError: Error {
    case notLoaded
}
