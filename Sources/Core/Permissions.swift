import Foundation

public enum Permission: CaseIterable, Sendable {
    case microphone, accessibility, inputMonitoring

    public var displayName: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }
}

/// Which of the permissions dictation needs are currently granted.
public struct Permissions: Equatable, Sendable {
    public var microphone: Bool
    public var accessibility: Bool
    public var inputMonitoring: Bool

    public init(microphone: Bool, accessibility: Bool, inputMonitoring: Bool) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var missing: [Permission] {
        Permission.allCases.filter { !isGranted($0) }
    }

    /// Menu-bar warning text, or nil when everything is granted.
    public var warning: String? {
        let missing = missing
        guard !missing.isEmpty else { return nil }
        return "Missing permissions: " + missing.map(\.displayName).joined(separator: ", ")
    }

    private func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .microphone: microphone
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        }
    }
}
