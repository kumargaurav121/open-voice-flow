import AppKit
import Core
import SwiftUI
import Testing
@testable import NotchUI

/// Renders each overlay state to PNG for eyeballing the design. Off unless OVF_SNAPSHOT_DIR is set:
///   OVF_SNAPSHOT_DIR=/tmp/notch swift test --filter NotchSnapshotRender
@MainActor
struct NotchSnapshotRender {
    nonisolated static let directory = ProcessInfo.processInfo.environment["OVF_SNAPSHOT_DIR"]

    @Test(.enabled(if: directory != nil))
    func renderEveryState() throws {
        let laptop = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                notch: CGRect(x: 663.5, y: 950, width: 185, height: 32), menuBarHeight: 32)
        let external = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), notch: nil, menuBarHeight: 25)
        var loud = WaveformLevels()
        for db: Float in [-30, -18, -12] { loud.update(decibels: db) }
        let phases: [(String, NotchStateMachine.Phase)] = [
            ("listening", .listening(.dictation)), ("transcribing", .transcribing), ("inserted", .inserted),
            ("error", .error(NotchError(.insertion), expanded: false)), ("details", .error(NotchError(.insertion), expanded: true)),
        ]
        for (screenName, screen) in [("notch", laptop), ("floating", external)] {
            for (name, phase) in phases {
                let model = NotchViewModel()
                model.screen = screen
                model.phase = phase
                var speech = WaveformLevels()
                for index in 0..<40 { speech.update(decibels: -40 + 28 * Float(abs(sin(Double(index) * 0.55)))) }
                model.history = speech.history(count: NotchPanelBody.barCount)
                model.context = DictationContext(appName: "TextEdit", appIcon: NSWorkspace.shared.icon(forFile: "/System/Applications/TextEdit.app"),
                                                 mode: "Hinglish", startedAt: .now.addingTimeInterval(-4))
                let panel = NotchGeometry.panelFrame(on: screen)
                let scene = ZStack(alignment: .top) {
                    // Menu bar backdrop, with the hardware notch drawn where it physically is.
                    LinearGradient(colors: [Color(white: 0.85), Color(white: 0.7)], startPoint: .top, endPoint: .bottom)
                    Color(white: 0.93).frame(height: screen.menuBarHeight)
                    if let notch = screen.notch {
                        UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black)
                            .frame(width: notch.width, height: notch.height)
                    }
                    NotchView(model: model)
                }
                .frame(width: panel.width, height: panel.height)
                let renderer = ImageRenderer(content: scene)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { Issue.record("render failed"); return }
                try png.write(to: URL(filePath: Self.directory!).appending(path: "\(screenName)-\(name).png"))
            }
        }
    }
}
