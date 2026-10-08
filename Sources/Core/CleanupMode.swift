import Foundation

/// The menu's AI Cleanup choice. Off by default: it adds time to every dictation.
public enum CleanupMode: String, CaseIterable, Sendable {
    case off
    /// Qwen3-1.7B: ~0.6 s, light touch (mostly punctuation; leaves many fillers).
    case fast
    /// Qwen3-4B-Instruct: ~1.3 s, removes fillers and stutters.
    case thorough

    public init(storedValue: String?) {
        self = storedValue.flatMap(CleanupMode.init(rawValue:)) ?? .off
    }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .fast: "Fast (Qwen3-1.7B)"
        case .thorough: "Thorough (Qwen3-4B-Instruct)"
        }
    }
}
