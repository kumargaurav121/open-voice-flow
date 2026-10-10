import AppKit
import Core
import SwiftUI

/// Shows dictation progress in an overlay hanging from the notch of the active screen.
@MainActor
public final class NotchController {
    private var machine = NotchStateMachine()
    private var waveform = WaveformLevels()
    private let model = NotchViewModel()
    private let panel: NotchPanel
    private let currentDecibels: @MainActor () -> Float
    private let modeTitle: @MainActor () -> String
    private var levelTimer: Timer?
    private var collapseTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// - Parameters:
    ///   - currentDecibels: the mic's latest loudness, polled while listening.
    ///   - modeTitle: the dictation mode shown beside the camera, e.g. "Hinglish".
    public init(currentDecibels: @escaping @MainActor () -> Float, modeTitle: @escaping @MainActor () -> String) {
        self.currentDecibels = currentDecibels
        self.modeTitle = modeTitle
        panel = NotchPanel()
        panel.contentView = NSHostingView(rootView: NotchView(model: model))
        model.onClick = { [weak self] in self?.apply(.clicked) }
    }

    public func handle(_ event: SessionEvent) {
        guard case .listening = event else {
            apply(.session(event))
            return
        }
        // We're a menu-bar app, so the frontmost app is the one being dictated into.
        let target = NSWorkspace.shared.frontmostApplication
        model.context = DictationContext(appName: target?.localizedName ?? "", appIcon: target?.icon,
                                         mode: modeTitle(), startedAt: .now)
        waveform = WaveformLevels()  // a fresh trace for every press, even straight after a ✓
        model.history = waveform.history(count: NotchPanelBody.barCount)
        if moveToActiveScreen(target) {
            // Let the jump to the new screen render first, so the panel grows out of the right notch
            // instead of sliding over from the old position.
            DispatchQueue.main.async { [weak self] in self?.apply(.session(event)) }
        } else {
            apply(.session(event))
        }
    }

    /// Progress of an action running in an app (the Slack DM).
    public func handle(_ event: ActionEvent) {
        apply(.action(event))
    }

    private func apply(_ input: NotchStateMachine.Input) {
        let effect = machine.handle(input)
        model.phase = machine.phase
        if case .returnToIdle(let delay, let token) = effect {
            collapseTask?.cancel()
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.apply(.timerFired(token))
            }
        }
        updateLevelTimer()
        // Only an error is clickable; otherwise clicks fall through to the menu bar underneath.
        if case .error = machine.phase { panel.ignoresMouseEvents = false } else { panel.ignoresMouseEvents = true }
        if machine.phase != .idle {
            hideTask?.cancel()
            panel.orderFrontRegardless()
        } else {
            // Take the (now transparent) panel off screen once the collapse spring has settled.
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled, let self, self.machine.phase == .idle else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func updateLevelTimer() {
        guard case .listening = machine.phase else {
            levelTimer?.invalidate()
            levelTimer = nil
            // The last trace stays on screen through transcribing; the next press starts a fresh one.
            return
        }
        guard levelTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.waveform.update(decibels: self.currentDecibels())
                self.model.history = self.waveform.history(count: NotchPanelBody.barCount)
            }
        }
        // .common so the waveform keeps moving while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    /// Puts the panel on the screen the user is typing on. Returns true when that changed the screen.
    private func moveToActiveScreen(_ target: NSRunningApplication?) -> Bool {
        guard let screen = Self.screen(of: target) else { return false }
        let info = ScreenInfo(screen)
        guard info != model.screen else { return false }
        model.screen = info
        // The panel is sized for the largest state plus shadow; the view animates the shape inside it.
        panel.setFrame(NotchGeometry.panelFrame(on: info), display: true)
        return true
    }

    /// The screen holding the target app's focused window. `NSScreen.main` follows *our* key window,
    /// which a menu-bar app never has, so ask Accessibility; fall back to the screen under the mouse.
    private static func screen(of app: NSRunningApplication?) -> NSScreen? {
        if let app, let frame = focusedWindowFrame(of: app) {
            // AX reports top-left-origin coordinates relative to the primary screen; flip to AppKit's.
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let centre = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) { return screen }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    private static func focusedWindowFrame(of app: NSRunningApplication) -> CGRect? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = window as! AXUIElement  // type checked above
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}

extension ScreenInfo {
    @MainActor
    init(_ screen: NSScreen) {
        let frame = screen.frame
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        var notch: CGRect?
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // Auxiliary areas are the menu bar strips either side of the camera housing. Use only their
            // widths, so the result doesn't depend on which coordinate space they're reported in.
            let height = screen.safeAreaInsets.top
            notch = CGRect(x: frame.minX + left.width, y: frame.maxY - height,
                           width: frame.width - left.width - right.width, height: height)
        }
        self.init(frame: frame, notch: notch, menuBarHeight: menuBar > 0 ? menuBar : 24)
    }
}

/// Borderless, non-activating, above the menu bar, on every Space and over full-screen apps.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        // Not `isFloatingPanel`: setting it resets `level` to .floating (3), which draws the panel *under*
        // the menu bar and hides it in full-screen apps.
    }

    // Never take keyboard focus from the app being dictated into.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
