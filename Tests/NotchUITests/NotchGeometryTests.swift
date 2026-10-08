import CoreGraphics
import Testing
@testable import NotchUI

struct NotchGeometryTests {
    // 14" MacBook Pro: 1512x982 points, notch ~185x32 centred at the top. AppKit origin is bottom-left.
    let laptop = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                            notch: CGRect(x: 663.5, y: 950, width: 185, height: 32),
                            menuBarHeight: 32)
    // External display to the right, no notch.
    let external = ScreenInfo(frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
                              notch: nil,
                              menuBarHeight: 25)

    @Test func onTheMacBookTheNotchGrowsDownIntoAPanel() {
        let shape = NotchGeometry.shape(for: .compact, on: laptop)

        #expect(shape.style == .notch)
        #expect(shape.frame.midX == laptop.notch!.midX)
        #expect(shape.frame.maxY == laptop.frame.maxY)
        #expect(shape.frame.height == laptop.notch!.height + NotchGeometry.panelBodyHeight)
        #expect(shape.frame.width == NotchGeometry.panelWidth)
        #expect(shape.frame.width > laptop.notch!.width + 2 * NotchGeometry.panelSideMinimum)
    }

    @Test func detailsGrowTheSamePanelFurtherDown() {
        let panel = NotchGeometry.shape(for: .compact, on: laptop)
        let message = NotchGeometry.shape(for: .message, on: laptop)
        let details = NotchGeometry.shape(for: .details, on: laptop)

        #expect(message == panel)  // listening → transcribing → ✓ / error only change the content
        #expect(details.frame.maxY == panel.frame.maxY && details.frame.midX == panel.frame.midX)
        #expect(details.frame.height > panel.frame.height && details.frame.width == panel.frame.width)
    }

    @Test func thePanelFlaresIntoTheMenuBarAndHasSoftBottomCorners() {
        let shape = NotchGeometry.shape(for: .compact, on: laptop)

        #expect(shape.topRadius > 0)
        #expect(shape.bottomRadius > shape.topRadius)
    }

    @Test func withoutANotchTheSamePanelFloatsBelowTheMenuBar() {
        let shape = NotchGeometry.shape(for: .compact, on: external)

        #expect(shape.style == .floating)
        #expect(shape.frame.midX == external.frame.midX)
        #expect(shape.frame.maxY == external.frame.maxY - external.menuBarHeight - NotchGeometry.floatingGap)
        #expect(shape.frame.width == NotchGeometry.panelWidth)
        #expect(shape.frame.height == NotchGeometry.floatingHeaderHeight + NotchGeometry.panelBodyHeight)
        #expect(shape.topRadius == 0 && shape.bottomRadius > 0)
    }

    @Test func theFloatingPanelGrowsDownForDetailsLikeTheNotchOne() {
        let panel = NotchGeometry.shape(for: .compact, on: external)
        let message = NotchGeometry.shape(for: .message, on: external)
        let details = NotchGeometry.shape(for: .details, on: external)

        #expect(message == panel)
        #expect(details.frame.maxY == panel.frame.maxY && details.frame.width == panel.frame.width)
        #expect(details.frame.height > panel.frame.height)
    }

    @Test func thePillStaysOnItsOwnScreen() {
        for size in [NotchGeometry.Size.compact, .message, .details] {
            let frame = NotchGeometry.shape(for: size, on: external).frame
            #expect(external.frame.contains(frame), "\(size) spills off the external display")
        }
    }

    @Test func thePanelLeavesRoomForTheShadowAroundTheLargestShape() {
        for screen in [laptop, external] {
            let panel = NotchGeometry.panelFrame(on: screen)
            let largest = NotchGeometry.shape(for: .details, on: screen).frame

            #expect(panel.minX <= largest.minX - NotchGeometry.shadowPadding)
            #expect(panel.maxX >= largest.maxX + NotchGeometry.shadowPadding)
            #expect(panel.minY <= largest.minY - NotchGeometry.shadowPadding)
            #expect(panel.maxY == screen.frame.maxY)
        }
    }

    @Test(arguments: [NotchStateMachine.Phase.listening(.dictation), .transcribing, .inserted])
    func activePhasesUseTheCompactSize(phase: NotchStateMachine.Phase) {
        #expect(NotchGeometry.Size(for: phase) == .compact)
    }

    @Test func errorsUseTheMessageSizeUntilExpanded() {
        let error = NotchError(.transcription)

        #expect(NotchGeometry.Size(for: .error(error, expanded: false)) == .message)
        #expect(NotchGeometry.Size(for: .error(error, expanded: true)) == .details)
        #expect(NotchGeometry.Size(for: .idle) == nil)
    }
}
