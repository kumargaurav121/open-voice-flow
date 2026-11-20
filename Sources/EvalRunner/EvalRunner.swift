import Audio
import Cloud
import Core
import Foundation
import LLM
import STT

/// ovf-transcribe: transcribe the eval clips with the app's own speech-to-text pipeline
/// (silence trim + WhisperKit), so in-app accuracy and latency can be scored with scripts/eval.
///
/// Each clip is dictated through the app's push-to-talk session, cut at pauses as it arrives.
///   --realtime  plays the audio at speaking pace, so parts are transcribed while it plays and the time is
///               release → text (otherwise the audio arrives at once and the time covers every part)
///   --whole     transcribes each trimmed clip in one go instead, as the app did before transcribing while
///               you speak (v2 ticket 02)
///
///   swift run -c release EvalRunner --name app-oriserve --model-folder <path>   # Hinglish mode
///   swift run -c release EvalRunner --name app-turbo                            # English mode / fallback
///   DEEPGRAM_API_KEY=… swift run -c release EvalRunner --name deepgram --stt deepgram   # cloud, for comparison
///   swift run -c release EvalRunner --name parakeet-v2 --language english --stt parakeet-v2 [--parakeet-folder <path>]
///     NVIDIA Parakeet TDT v2 (the app's English model, in long parts as in the app), from the app's installed folder
///     or another, or v3 (`--stt parakeet-v3`, from another folder only) (v2 tickets 06-07)
///   GROQ_API_KEY=… swift run -c release EvalRunner --name oriserve-groq --model-folder <path> --cleanup cloud --llm groq
/// Cloud keys come from the environment only (never arguments, which end up in shell history).
///   swift run -c release EvalRunner --name app-commands --model-folder <path> --commands   # clips 24-28 as commands
@main
struct EvalRunner {
    @MainActor
    static func main() async throws {
        let args = Arguments(CommandLine.arguments.dropFirst())
        LLMCleaner.configureGPU()
        // --clean-text "<text>": run one text through the rules and the AI cleanup, and stop.
        // --cleanup off|fast|thorough|cloud: the app's AI Cleanup menu (rules always run). Default off.
        // --llm openai|groq [--llm-model <name>]: the cloud LLM for --cleanup cloud.
        let cleanupMode = CleanupMode(storedValue: args["--cleanup"])
        let llmFolder = args["--llm-folder"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? LLMCleaner.folder(for: cleanupMode.isLocal ? cleanupMode : .thorough)!
        let cloudLLM = CloudLLM(service: args["--llm"].flatMap { name in CloudLLM.Service.allCases.first { $0.rawValue.lowercased() == name.lowercased() } } ?? .groq, model: args["--llm-model"])
        let environment = ProcessInfo.processInfo.environment
        let envKey: (APIKeys.Account) -> String? = { environment[$0.environmentVariable] }
        if let text = args["--clean-text"] {
            let cleaner = LLMCleaner(folder: llmFolder)
            try await cleaner.prepare()
            let rules = CleanupSpeechToText.rules(text, formatting: true)  // as dictation
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
        // --ids 3,6,8: only these clips (quick experiments).
        let ids = args["--ids"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }

        let whisper = WhisperKitTranscriber(model: model)
        var breakdown = ""
        whisper.onBreakdown = { breakdown = $0 }
        // Same pipeline as the app.
        // --dictionary "Gurjeet,Supabase": the custom dictionary, as the app applies it.
        let dictionary = args["--dictionary"].map { $0.split(separator: ",").map(String.init) } ?? []
        let localCleaner = cleanupMode.isLocal ? LLMCleaner(folder: llmFolder) : nil
        localCleaner?.vocabulary = { dictionary }
        if let localCleaner { try await localCleaner.prepare() }
        let cleaner: TextCleaner? = cleanupMode == .cloud
            ? OpenAICompatibleCleaner(llm: { cloudLLM }, apiKey: { envKey($0.keyAccount) }, vocabulary: { dictionary })
            : localCleaner
        // --stt deepgram: Deepgram Nova-3 instead of WhisperKit (no fallback here: a failure should show).
        let useDeepgram = args["--stt"] == "deepgram"
        // --stt parakeet-v2|parakeet-v3 [--parakeet-folder <path>]: NVIDIA Parakeet, the app's English model (v2),
        // from the app's installed folder or that one (v3 only from a folder: the app installs v2).
        let parakeetVersion: ParakeetTranscriber.Version? = switch args["--stt"] {
        case "parakeet-v2": .v2
        case "parakeet-v3": .v3
        default: nil
        }
        // A misspelt engine would otherwise quietly run Whisper under the run's name.
        guard args["--stt"].map({ $0 == "deepgram" || parakeetVersion != nil }) ?? true else {
            throw RunnerError.usage("--stt must be one of: deepgram, parakeet-v2, parakeet-v3 (default: WhisperKit)")
        }
        guard parakeetVersion != nil || !args.has("--parakeet-folder") else {
            throw RunnerError.usage("--parakeet-folder goes with --stt parakeet-v2 or parakeet-v3")
        }
        guard parakeetVersion != .v3 || args.has("--parakeet-folder") else {
            throw RunnerError.usage("--stt parakeet-v3 needs --parakeet-folder: the app installs v2 only")
        }
        let parakeet = parakeetVersion.map { version in
            args["--parakeet-folder"].map { ParakeetTranscriber(folder: URL(filePath: $0, directoryHint: .isDirectory), version: version) }
                ?? ParakeetTranscriber(version: version)
        }
        parakeet?.onBreakdown = { breakdown = $0 }
        let speech: SpeechToText = if useDeepgram {
            DeepgramSpeechToText(apiKey: { envKey(.deepgram) }, keyterms: { dictionary })
        } else if let parakeet {
            parakeet
        } else {
            whisper
        }
        // The app's own pipeline, so the transcripts are exactly what the app would paste (into a non-code app).
        // --sentence-pause <seconds>: see LiveTranscriber.sentencePause. Parakeet transcribes in long parts, as in the app.
        let pipeline = TranscriptPipeline(speech: speech, terms: { dictionary }, isEnglishWord: { EnglishWords.contains($0) },
                                          sentencePause: args["--sentence-pause"].flatMap(Double.init) ?? LiveTranscriber.sentencePause,
                                          partLengths: { _ in parakeet == nil ? .short : .long })
        let transcriber = pipeline.dictation(selectedAI: { cleaner }, isCodeContext: { false },
                                             log: { print("     cleanup: \($0)") })
        let commandTranscriber = pipeline.commands()
        let trimmer = SilenceTrimmer()
        let clock = ContinuousClock()

        if useDeepgram {
            print("\(name): Deepgram Nova-3")
        } else if let parakeet {
            print("\(name): loading \(args["--stt"]!)")
            let loadTime = try await clock.measure { try await parakeet.prepare() }
            print("  loaded in \(loadTime)")
        } else {
            print("\(name): loading \(model)")
            let loadTime = try await clock.measure { try await whisper.prepare() }
            print("  loaded in \(loadTime)")
        }

        // --commands: the command clips (24-28) through the command parser, as the app runs them; written
        // to <name>.intents.json for `ovf-eval intents`.
        if args.has("--commands") {
            let commandModel = LLMCleaner(folder: llmFolder)
            try await commandModel.prepare()
            let parser = CommandParser(model: { commandModel })
            let commandIDs = Set(try JSONDecoder().decode([ReferenceRow].self, from: Data(contentsOf: URL(filePath: "docs/eval/references.json")))
                .filter { $0.kind == "command" }.map(\.id))
            var parsed: [IntentRecord] = []
            for row in manifest where commandIDs.contains(row.id) && (ids?.contains(row.id) ?? true) {
                let clip = trimmer.trim(try AudioFileLoader.load(clips.appending(path: row.audio)))
                var text = ""
                var intent: CommandIntent?
                let elapsed = try await clock.measure {
                    text = try await commandTranscriber.transcribe(clip, language: language)
                    intent = await parser.parse(text)
                }
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                parsed.append(IntentRecord(id: row.id, transcript: text, intent: intent.map(IntentRecord.Intent.init), seconds: seconds))
                print(String(format: "  %02d %5.2fs %@", row.id, seconds, intent?.summary ?? "unknown: \(text)"))
            }
            let output = clips.appending(path: "transcripts/\(name).intents.json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(parsed).write(to: output)
            print("wrote \(output.path)")
            return
        }

        var records: [TranscriptRecord] = []
        let dictation = Dictation(transcriber: transcriber, live: pipeline.live, language: language)
        let whole = args.has("--whole"), realtime = args.has("--realtime")
        print(whole ? "  whole clips" : realtime ? "  dictated at speaking pace" : "  dictated, audio at once")
        for row in manifest where ids?.contains(row.id) ?? true {
            let audio = try AudioFileLoader.load(clips.appending(path: row.audio))
            var text = "", seconds = 0.0, cut = ""
            if whole {
                let clip = trimmer.trim(audio)
                let elapsed = try await clock.measure { text = try await transcriber.transcribe(clip, language: language) }
                seconds = elapsed / .seconds(1)
            } else {
                let (pasted, took, timings) = try await dictation.run(audio, realtime: realtime)
                (text, seconds) = (pasted, took)
                cut = timings.map { String(format: " · %d parts, tail %.1fs", $0.parts, $0.tail) } ?? " · nothing pasted"
            }
            records.append(TranscriptRecord(id: row.id, text: text, seconds: seconds))
            print(String(format: "  %02d %5.2fs (%4.1fs audio%@) %@", row.id, seconds, audio.duration, cut, String(text.prefix(50))))
            print("     last transcription: \(breakdown)")
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

private struct ReferenceRow: Decodable {
    var id: Int
    var kind: String?
}

private struct IntentRecord: Encodable {
    struct Intent: Encodable {
        var action = "send_message"
        var app: String
        var to: String
        var text: String

        init(_ intent: CommandIntent) {
            switch intent {
            case .sendMessage(let app, let to, let text): (self.app, self.to, self.text) = (app, to, text)
            }
        }
    }

    var id: Int
    var transcript: String
    var intent: Intent?
    var seconds: Double
}

private struct Arguments {
    private let values: [String: String]

    init(_ arguments: ArraySlice<String>) {
        var values: [String: String] = [:]
        let arguments = Array(arguments)
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            index += 1
            guard key.hasPrefix("--") else { continue }
            // A flag without a value (e.g. --commands) is followed by another flag or nothing.
            if index < arguments.count, !arguments[index].hasPrefix("--") {
                values[key] = arguments[index]
                index += 1
            } else {
                values[key] = ""
            }
        }
        self.values = values
    }

    subscript(key: String) -> String? { values[key] }
    func has(_ key: String) -> Bool { values[key] != nil }
}

enum RunnerError: Error, CustomStringConvertible {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message): message
        }
    }
}
