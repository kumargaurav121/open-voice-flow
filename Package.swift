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
    ],
    targets: [
        // Session pipeline, domain types and provider protocols. No platform frameworks.
        .target(name: "Core"),
        // Mic capture and silence trimming.
        .target(name: "Audio", dependencies: ["Core"]),
        // Speech-to-text providers.
        .target(name: "STT", dependencies: ["Core", .product(name: "WhisperKit", package: "WhisperKit")]),
        // Getting text into the focused app.
        .target(name: "Insertion", dependencies: ["Core"]),
        // Menu-bar app: hotkeys, permissions, wiring.
        .executableTarget(name: "OpenVoiceFlow", dependencies: ["Core", "Audio", "STT", "Insertion"]),
        // Runs the app's speech-to-text over the eval clips, for scoring with scripts/eval.
        .executableTarget(name: "EvalRunner", dependencies: ["Core", "Audio", "STT"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "AudioTests", dependencies: ["Audio"]),
        .testTarget(name: "STTTests", dependencies: ["STT"]),
        .testTarget(name: "EvalRunnerTests", dependencies: ["EvalRunner"]),
    ]
)
