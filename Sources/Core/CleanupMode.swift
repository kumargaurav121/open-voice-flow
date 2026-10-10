import Foundation

/// The menu's AI Cleanup choice. Off by default: it adds time to every dictation.
public enum CleanupMode: String, CaseIterable, Sendable {
    case off
    /// Qwen3-1.7B: ~0.6 s, light touch (mostly punctuation; leaves many fillers).
    case fast
    /// Qwen3-4B-Instruct: ~1.3 s, removes fillers and stutters.
    case thorough
    /// The cloud LLM chosen in Settings (the user's own OpenAI or Groq key). Sends the text off the Mac.
    case cloud

    public init(storedValue: String?) {
        self = storedValue.flatMap(CleanupMode.init(rawValue:)) ?? .off
    }

    /// Runs a model on this Mac (Fast or Thorough).
    public var isLocal: Bool { self == .fast || self == .thorough }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .fast: "Fast (Qwen3-1.7B)"
        case .thorough: "Thorough (Qwen3-4B-Instruct)"
        case .cloud: "Cloud"
        }
    }
}
