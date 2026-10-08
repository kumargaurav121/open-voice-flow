// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenVoiceFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenVoiceFlow", targets: ["OpenVoiceFlow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.13.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", .upToNextMinor(from: "3.32.3")),
        // Same swift-transformers WhisperKit pins (1.1.x); used for the LLM's tokenizer.
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMinor(from: "1.1.6")),
    ],
    targets: [
        // Session pipeline, domain types and provider protocols. No platform frameworks.
        .target(name: "Core"),
        // Mic capture and silence trimming.
        .target(name: "Audio", dependencies: ["Core"]),
        // Speech-to-text providers.
        .target(name: "STT", dependencies: ["Core", .product(name: "WhisperKit", package: "WhisperKit")]),
        // Optional AI cleanup with a local LLM (MLX).
        .target(name: "LLM", dependencies: [
            "Core",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ]),
        // Getting text into the focused app.
        .target(name: "Insertion", dependencies: ["Core"]),
        // The notch overlay: state machine, geometry, panel and views.
        .target(name: "NotchUI", dependencies: ["Core"]),
        // Menu-bar app: hotkeys, permissions, wiring.
        .executableTarget(name: "OpenVoiceFlow", dependencies: ["Core", "Audio", "STT", "LLM", "Insertion", "NotchUI"]),
        // Runs the app's speech-to-text over the eval clips, for scoring with scripts/eval.
        .executableTarget(name: "EvalRunner", dependencies: ["Core", "Audio", "STT", "LLM"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
        .testTarget(name: "STTTests", dependencies: ["STT"]),
        .testTarget(name: "EvalRunnerTests", dependencies: ["EvalRunner"]),
        .testTarget(name: "NotchUITests", dependencies: ["NotchUI"]),
    ]
)
