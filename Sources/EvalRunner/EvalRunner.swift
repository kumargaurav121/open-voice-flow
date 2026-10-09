import Audio
import Core
import Foundation
import LLM
import STT

/// ovf-transcribe: transcribe the eval clips with the app's own speech-to-text pipeline
/// (silence trim + WhisperKit), so in-app accuracy and latency can be scored with scripts/eval.
///
///   swift run -c release EvalRunner --name app-oriserve --model-folder <path>   # Hinglish mode
///   swift run -c release EvalRunner --name app-turbo                            # English mode / fallback
@main
struct EvalRunner {
    @MainActor
    static func main() async throws {
        let args = Arguments(CommandLine.arguments.dropFirst())
        LLMCleaner.configureGPU()
        // --clean-text "<text>": run one text through the rules and the AI cleanup, and stop.
        // --cleanup off|fast|thorough: the app's AI Cleanup menu (rules always run). Default off.
        let cleanupMode = CleanupMode(storedValue: args["--cleanup"])
        let llmFolder = args["--llm-folder"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? LLMCleaner.folder(for: cleanupMode == .off ? .thorough : cleanupMode)!
        if let text = args["--clean-text"] {
            let cleaner = LLMCleaner(folder: llmFolder)
            try await cleaner.prepare()
            let rules = RulesCleanup.clean(text)
            let clock = ContinuousClock()
            var ai = ""
            let took = try await clock.measure { ai = try await cleaner.clean(rules) }
            print("raw:   \(text)\nrules: \(rules)\nai:    \(ai)  (\(took), guard \(AICleanupGuard.accepts(original: rules, rewritten: ai) ? "accepts" : "rejects"))")
            return
        }
        let clips = URL(filePath: args["--clips"] ?? "docs/eval/clips", directoryHint: .isDirectory)
        guard let language = Language(rawValue: args["--language"] ?? "hinglish") else {
            throw RunnerError.usage("--language must be one of: \(Language.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let model: SpeechModel = args["--model-folder"].map { .hinglish(folder: URL(filePath: $0, directoryHint: .isDirectory)) } ?? .turbo
        guard let name = args["--name"] else {
            throw RunnerError.usage("--name is required (the config name ovf-eval will score)")
        }

        let manifest = try JSONDecoder().decode([ManifestRow].self, from: Data(contentsOf: clips.appending(path: "manifest.json")))
        guard !manifest.isEmpty else { throw RunnerError.usage("manifest is empty") }

        let whisper = WhisperKitTranscriber(model: model)
        var breakdown = ""
        whisper.onBreakdown = { breakdown = $0 }
        // Same pipeline as the app.
        let cleaner = cleanupMode == .off ? nil : LLMCleaner(folder: llmFolder)
        if let cleaner { try await cleaner.prepare() }
        let transcriber = CleanupSpeechToText(
            wrapping: LatinScriptSpeechToText(wrapping: whisper), selectedAI: { cleaner },
            isCodeContext: { false }, timeout: .seconds(5),
            log: { print("     cleanup: \($0)") }
        )
        let trimmer = SilenceTrimmer()
        let clock = ContinuousClock()

        print("\(name): loading \(model)")
        let loadTime = try await clock.measure { try await whisper.prepare() }
        print("  loaded in \(loadTime)")

        var records: [TranscriptRecord] = []
        for row in manifest {
            let clip = trimmer.trim(try AudioFileLoader.load(clips.appending(path: row.audio)))
            var text = ""
            let elapsed = try await clock.measure { text = try await transcriber.transcribe(clip, language: language) }
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            records.append(TranscriptRecord(id: row.id, text: text, seconds: seconds))
            print(String(format: "  %02d %5.2fs (%4.1fs audio) %@", row.id, seconds, clip.duration, String(text.prefix(50))))
            print("     \(breakdown)")
        }

        let output = clips.appending(path: "transcripts/\(name).json")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TranscriptsFile.encode(records).write(to: output)
        print("wrote \(output.path)")
    }
}

private struct ManifestRow: Decodable {
    var id: Int
    var audio: String
}

private struct Arguments {
    private let values: [String: String]

    init(_ arguments: ArraySlice<String>) {
        var values: [String: String] = [:]
        var iterator = arguments.makeIterator()
        while let key = iterator.next() {
            if key.hasPrefix("--"), let value = iterator.next() { values[key] = value }
        }
        self.values = values
    }

    subscript(key: String) -> String? { values[key] }
}

enum RunnerError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message): message
        }
    }
}
