import AppKit
import SwiftUI

/// The onboarding window: a single fixed-size panel with the title bar blended into the content.
@MainActor
public final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let model: OnboardingModel
    private var window: NSWindow?

    public init(model: OnboardingModel) {
        self.model = model
    }

    public func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Set Up Open Voice Flow"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            window.delegate = self
            window.center()
            self.window = window
        }
        model.startWatchingPermissions()
        // A menu-bar app isn't active by default, and macOS 14's cooperative activation can decline a
        // plain activate(); onboarding is something the user just launched, so take focus.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        model.stopWatchingPermissions()
    }
}
