import Core
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import ModelStore

/// The optional AI cleanup: a small local LLM (Qwen3, 4-bit, via MLX) removes fillers and fixes
/// punctuation and casing. Its output still has to pass `AICleanupGuard` before it's used.
@MainActor
public final class LLMCleaner: TextCleaner {

    /// Each mode's model folder, as installed by onboarding from the pinned manifests (ModelStore).
    public static func folder(for mode: CleanupMode) -> URL? {
        switch mode {
        case .off, .cloud: nil
        case .fast: BuiltInModels.cleanupFast.installedFolder
        case .thorough: BuiltInModels.cleanupThorough.installedFolder
        }
    }

    /// The user's dictionary, given to the model as spelling context.
    public var vocabulary: () -> [String] = { [] }


    /// Still generating (e.g. after a timeout): a new cleanup is refused rather than run alongside it.
    public struct Busy: Error {}

    private let folder: URL
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?
    private var warming: Task<Void, Never>?
    private var generating = false
    /// Bumped by `unload()`, so a load that finishes afterwards is discarded instead of reinstated.
    private var generation = 0

    /// - Parameter folder: the model's local folder (see `folder(for:)`).
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
        try await respond(to: text, instructions: CleanupPrompt.instructions(vocabulary: vocabulary()),
                          maxTokens: max(32, text.count / 2))
    }

    /// One reply in a fresh session: no history, so one dictation or command can't steer the next.
    /// `waitIfBusy`: wait (up to 3 s) for a generation in progress, e.g. the warm-up, instead of refusing.
    private func respond(to text: String, instructions: String, maxTokens: Int, waitIfBusy: Bool = false) async throws -> String {
        if waitIfBusy {
            let deadline = ContinuousClock.now + .seconds(3)
            while generating, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        }
        guard !generating else { throw Busy() }
        generating = true
        defer { generating = false }
        let container = try await loadedContainer()
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
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
    static func stripThinking(_ reply: String) -> String { ModelReply.strippingThinking(reply) }
}

extension LLMCleaner: CommandModel {
    /// Turns a command the rules didn't recognise into the JSON `CommandSchema` checks.
    public func reply(to command: String, instructions: String) async throws -> String {
        // A command pressed while the model warms up waits for it rather than coming back "not understood".
        try await respond(to: "Command: \(command)", instructions: instructions, maxTokens: max(120, command.count), waitIfBusy: true)
    }
}
