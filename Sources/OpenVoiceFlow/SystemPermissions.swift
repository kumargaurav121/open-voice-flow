import AppKit
import AVFoundation
import Core

/// Reads and requests the macOS permissions dictation depends on.
@MainActor
enum SystemPermissions {
    static func current() -> Permissions {
        Permissions(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess()
        )
    }

    /// Triggers the system prompts for anything not yet decided.
    static func requestMissing() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    static func openSettings(for permission: Permission) {
        let pane = switch permission {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        open("x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
