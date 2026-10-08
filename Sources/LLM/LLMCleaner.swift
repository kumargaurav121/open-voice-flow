import Core
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// The optional AI cleanup: a small local LLM (Qwen3, 4-bit, via MLX) removes fillers and fixes
/// punctuation and casing. Its output still has to pass `AICleanupGuard` before it's used.
@MainActor
public final class LLMCleaner: TextCleaner {
    static let instructions = """
        You tidy up dictated text. Delete filler words used as hesitations (um, uh, like, you know, basically, \
        actually, I mean, matlab, toh) and words the speaker repeated or restarted. Fix punctuation and \
        capitalisation, and keep question marks. Keep every other word, in the same order and language: the \
        text may mix English and Hindi written in English letters, and must stay that way. Never translate, \
        answer, summarise or add words. Reply with only the tidied text.

        Examples:
        Input: So basically bhai kal ka demo demo ready hai na? Like client ko eleven baje dikhana hai
        Output: Bhai, kal ka demo ready hai na? Client ko eleven baje dikhana hai.
        Input: Hey Priya, I mean, can you can you send me the deck by tomorrow? Matlab urgent hai
        Output: Hey Priya, can you send me the deck by tomorrow? Urgent hai.
        Input: Meeting at 3 pm is confirmed
        Output: Meeting at 3 pm is confirmed.
        """

    /// Where scripts/download-model.sh installs each mode's model.
    public static func folder(for mode: CleanupMode) -> URL? {
        let name: String? = switch mode {
        case .off: nil
        case .fast: "qwen3-1.7b-4bit"            // mlx-community/Qwen3-1.7B-4bit @ 3b1b1768f8f8cf8351c712464f906e86c2b8269e
        case .thorough: "qwen3-4b-instruct-2507-4bit"  // mlx-community/Qwen3-4B-Instruct-2507-4bit @ 50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b
        }
        return name.map { URL.applicationSupportDirectory.appending(path: "open-voice-flow/models/\($0)", directoryHint: .isDirectory) }
    }

    /// Still generating (e.g. after a timeout): a new cleanup is refused rather than run alongside it.
    public struct Busy: Error {}

    private let folder: URL
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var warming: Task<Void, Never>?
    private var generating = false
    /// Bumped by `unload()`, so a load that finishes afterwards is discarded instead of reinstated.
    private var generation = 0

    /// - Parameter folder: the model's local folder (downloaded and pinned by scripts/download-model.sh).
    public init(folder: URL) {
        self.folder = folder
    }

    /// Points MLX at its GPU kernels (built by SwiftPM into `mlx-swift_Cmlx.bundle`). Process-wide: call
    /// once at startup, before any model loads.
    public static func configureGPU() {
        if let metallib = bundledMetallib { GPU.metallib = metallib }
    }

    /// MLX's GPU kernels, built by SwiftPM into `mlx-swift_Cmlx.bundle` and copied into the app's Resources
    /// by scripts/build-app.sh (or next to the binary for command-line tools).
    public static var bundledMetallib: URL? {
        let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        return roots.lazy
            .map { $0.appending(path: "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func isInstalled(at folder: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.contains("config.json") && files.contains("tokenizer.json")
            && files.contains { $0.hasSuffix(".safetensors") }  // single or sharded weights
    }

    /// Loads the model and runs one tiny generation, so the first real cleanup isn't slowed by the GPU's
    /// first-use setup (2.7 s vs ~0.6 s in testing). Safe to call more than once.
    public func prepare() async throws {
        _ = try await loadedContainer()
        if warming == nil {
            warming = Task { _ = try? await self.clean("Okay.") }
        }
        await warming?.value
    }

    public func clean(_ text: String) async throws -> String {
        guard !generating else { throw Busy() }
        generating = true
        defer { generating = false }
        let container = try await loadedContainer()
        // A fresh session per transcript: no history, so one dictation can't steer the next.
        let session = ChatSession(
            container,
            instructions: Self.instructions,
            generateParameters: GenerateParameters(maxTokens: max(32, text.count / 2), temperature: 0),
            additionalContext: ["enable_thinking": false]  // Qwen3 thinks by default
        )
        let reply = try await session.respond(to: text)
        return Self.stripThinking(reply)
    }

    /// Frees the model's memory (switching modes, or turning cleanup off).
    public func unload() {
        generation += 1
        loading?.cancel()
        loading = nil
        warming = nil
        container = nil
    }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        let started = generation
        if loading == nil {
            let folder = folder
            loading = Task { try await loadModelContainer(from: folder, using: HuggingFaceTokenizerLoader()) }
        }
        do {
            let loaded = try await loading!.value
            // Unloaded while loading (mode switched): don't bring the model back.
            guard generation == started else { throw CancellationError() }
            container = loaded
            return loaded
        } catch {
            if generation == started { loading = nil }
            throw error
        }
    }

    /// Qwen3 may still emit an empty <think></think> block with thinking off.
    static func stripThinking(_ reply: String) -> String {
        reply.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
