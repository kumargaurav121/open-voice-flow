import Foundation
import Observation

/// A modifier key that can be held for push-to-talk. Modifiers never type a character, so holding one
/// can't leak into the focused app.
public enum TriggerKey: String, Codable, CaseIterable, Sendable {
    case fn, rightOption, rightCommand, rightControl, rightShift

    public var displayName: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "Right ⌥ Option"
        case .rightCommand: "Right ⌘ Command"
        case .rightControl: "Right ⌃ Control"
        case .rightShift: "Right ⇧ Shift"
        }
    }

    /// Short form for tight spaces (the Recent menu).
    public var symbol: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .rightControl: "⌃"
        case .rightShift: "⇧"
        }
    }
}

extension TriggerKey {
    public struct State: Equatable, Sendable {
        public var down: Bool
        /// Another modifier is held too: a shortcut, not push-to-talk.
        public var otherModifiers: Bool
    }

    // CGEventFlags raw values: the generic modifier bits, plus the per-side "device" bits that tell
    // Right ⌥ from Left ⌥.
    private static let fnBit: UInt64 = 0x80_0000
    private static let genericBits: [UInt64] = [0x2_0000, 0x4_0000, 0x8_0000, 0x10_0000]  // ⇧ ⌃ ⌥ ⌘
    private static let deviceBits: UInt64 = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000

    /// This key's own bits: (generic, device side).
    private var bits: (generic: UInt64, device: UInt64) {
        switch self {
        case .fn: (Self.fnBit, 0)
        case .rightShift: (0x2_0000, 0x04)
        case .rightControl: (0x4_0000, 0x2000)
        case .rightOption: (0x8_0000, 0x40)
        case .rightCommand: (0x10_0000, 0x10)
        }
    }

    /// Reads a flags-changed event's modifier flags for this key.
    public func state(flags: UInt64) -> State {
        let own = bits
        let down = self == .fn ? flags & Self.fnBit != 0 : flags & own.device != 0
        let otherGeneric = (Self.genericBits + [Self.fnBit]).filter { $0 != own.generic }.contains { flags & $0 != 0 }
        let otherSide = flags & Self.deviceBits & ~own.device != 0
        return State(down: down, otherModifiers: otherGeneric || otherSide)
    }
}

/// Hold-to-talk keys for dictation and commands (Esc always cancels).
public struct Hotkeys: Codable, Equatable, Sendable {
    public var dictate: TriggerKey
    public var command: TriggerKey

    public init(dictate: TriggerKey = .fn, command: TriggerKey = .rightOption) {
        self.dictate = dictate
        self.command = command
    }

    /// One key can't do both.
    public var conflict: Bool { dictate == command }
}

public enum SpeechProvider: String, Codable, CaseIterable, Sendable {
    /// WhisperKit on this Mac (the Hinglish model or turbo).
    case local
    /// Deepgram Nova-3 with the user's own key. Sends audio off the Mac.
    case deepgram
}

/// The cloud LLM used when AI Cleanup is set to Cloud.
public struct CloudLLM: Codable, Equatable, Sendable {
    public enum Service: String, Codable, CaseIterable, Sendable {
        case openAI, groq
    }

    public var service: Service
    /// Nil = the service's default model.
    public var model: String?

    public init(service: Service = .groq, model: String? = nil) {
        self.service = service
        self.model = model
    }
}

/// Everything about how dictation behaves, kept as one value so several named modes later is only a UI
/// change. Versioned and decoded leniently: a field from a newer version, or a value this version doesn't
/// know, falls back to its default instead of losing the rest.
public struct Mode: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var language: Language = .hinglish
    public var cleanup: CleanupMode = .off
    public var speech: SpeechProvider = .local
    public var cloudLLM = CloudLLM()
    public var hotkeys = Hotkeys()
    /// Seconds the notch counts down before an action sends (Esc stops it).
    public var sendCountdown = Self.defaultSendCountdown {
        didSet { sendCountdown = Self.clampedCountdown(sendCountdown) }
    }
    public static let sendCountdownRange = 1...10
    public static let defaultSendCountdown = 3

    static func clampedCountdown(_ seconds: Int) -> Int {
        min(max(seconds, sendCountdownRange.lowerBound), sendCountdownRange.upperBound)
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, language, cleanup, speech, cloudLLM, hotkeys, sendCountdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0.flatMap(T.init(rawValue:)) } ?? fallback
        }
        language = value(.language, .hinglish)
        cleanup = value(.cleanup, .off)
        speech = value(.speech, .local)
        cloudLLM = (try? container.decodeIfPresent(LenientCloudLLM.self, forKey: .cloudLLM))?.value ?? CloudLLM()
        hotkeys = (try? container.decodeIfPresent(LenientHotkeys.self, forKey: .hotkeys))?.value ?? Hotkeys()
        let countdown = (try? container.decodeIfPresent(Int.self, forKey: .sendCountdown)) ?? nil
        sendCountdown = countdown.map(Self.clampedCountdown) ?? Self.defaultSendCountdown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(language.rawValue, forKey: .language)
        try container.encode(cleanup.rawValue, forKey: .cleanup)
        try container.encode(speech.rawValue, forKey: .speech)
        try container.encode(cloudLLM, forKey: .cloudLLM)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(sendCountdown, forKey: .sendCountdown)
    }
}

/// Decodes each field on its own so one unknown value doesn't discard its neighbours.
private struct LenientHotkeys: Decodable {
    let value: Hotkeys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Hotkeys()
        func key(_ name: CodingKeys, _ fallback: TriggerKey) -> TriggerKey {
            (try? container.decodeIfPresent(String.self, forKey: name)).flatMap { $0.flatMap(TriggerKey.init(rawValue:)) } ?? fallback
        }
        let decoded = Hotkeys(dictate: key(.dictate, defaults.dictate), command: key(.command, defaults.command))
        // A fallback can land on the other action's key; one key can't do both.
        value = decoded.conflict ? defaults : decoded
    }
    private enum CodingKeys: String, CodingKey { case dictate, command }
}

private struct LenientCloudLLM: Decodable {
    let value: CloudLLM
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let service = (try? container.decodeIfPresent(String.self, forKey: .service)).flatMap { $0.flatMap(CloudLLM.Service.init(rawValue:)) }
        let model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? nil
        value = CloudLLM(service: service ?? .groq, model: model)
    }
    private enum CodingKeys: String, CodingKey { case service, model }
}

extension Language: Codable {}
extension CleanupMode: Codable {}

/// The saved Mode, in local preferences.
@MainActor
@Observable
public final class ModeStore {
    static let key = "mode"

    public var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            if let data = try? JSONEncoder().encode(mode) { defaults.set(data, forKey: Self.key) }
            onChange(oldValue, mode)
        }
    }

    /// Called after each change, wherever it came from (menu or Settings), with the old and new values.
    @ObservationIgnored public var onChange: (_ old: Mode, _ new: Mode) -> Void = { _, _ in }
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            mode = (try? JSONDecoder().decode(Mode.self, from: data)) ?? Mode()
        } else {
            // Settings from before modes existed: carried over, saved as the Mode, then removed.
            var migrated = Mode()
            migrated.language = defaults.string(forKey: "language").flatMap(Language.init(rawValue:)) ?? .hinglish
            migrated.cleanup = CleanupMode(storedValue: defaults.string(forKey: "cleanupMode"))
            mode = migrated
            if let data = try? JSONEncoder().encode(migrated) { defaults.set(data, forKey: Self.key) }
            defaults.removeObject(forKey: "language")
            defaults.removeObject(forKey: "cleanupMode")
        }
    }
}
