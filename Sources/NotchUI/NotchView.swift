import SwiftUI

/// Observable state the view renders; owned and updated by `NotchController`.
@MainActor
@Observable
final class NotchViewModel {
    var phase = NotchStateMachine.Phase.idle
    var history = WaveformLevels().history(count: NotchPanelBody.barCount)
    var context: DictationContext?
    var screen = ScreenInfo(frame: .zero, notch: nil, menuBarHeight: 32)
    var onClick: () -> Void = {}
}

/// The overlay. On a MacBook the notch grows down into the panel; on a display without a notch the same
/// panel floats just below the menu bar.
struct NotchView: View {
    let model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let panel = NotchGeometry.panelFrame(on: model.screen)
        let size = NotchGeometry.Size(for: model.phase)
        let visible = size != nil
        let target = NotchGeometry.shape(for: size ?? .compact, on: model.screen)
        let shape = visible ? target : collapsed(from: target)

        ZStack(alignment: .top) {
            OverlayShape(shape)
                .fill(.black)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)

            NotchPanelBody(
                model: model,
                cameraWidth: model.screen.notch?.width ?? 0,
                headerHeight: model.screen.notch?.height ?? NotchGeometry.floatingHeaderHeight,
                shoulder: shape.topRadius,
                visible: visible,
                reduceMotion: reduceMotion
            )
        }
        .frame(width: shape.frame.width, height: shape.frame.height, alignment: .top)
        .contentShape(OverlayShape(shape))
        .onTapGesture { model.onClick() }
        // Fades as it shrinks, so a slightly mis-measured notch never leaves a black sliver at idle.
        .opacity(visible ? 1 : 0)
        .offset(x: shape.frame.midX - panel.midX, y: panel.maxY - shape.frame.maxY)
        .frame(width: panel.width, height: panel.height, alignment: .top)
        .animation(animation, value: model.phase)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// One spring drives size, corners and content together. Opening carries a little momentum
    /// (like the Dynamic Island); closing settles without bounce. Reduce Motion gets a plain fade.
    private var animation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return model.phase == .idle
            ? .spring(response: 0.45, dampingFraction: 1)
            : .spring(response: 0.42, dampingFraction: 0.8)
    }

    /// Where the shape returns to, the way it came out: into the camera housing on a MacBook, into a
    /// small pill at the top centre elsewhere.
    private func collapsed(from shape: NotchGeometry.Shape) -> NotchGeometry.Shape {
        var collapsed = shape
        let core = model.screen.notch?.size ?? CGSize(width: 120, height: NotchGeometry.floatingHeaderHeight)
        collapsed.frame = CGRect(x: shape.frame.midX - core.width / 2, y: shape.frame.maxY - core.height,
                                 width: core.width, height: core.height)
        collapsed.topRadius = 0
        collapsed.bottomRadius = core.height / 2
        return collapsed
    }

    private var accessibilityLabel: String {
        switch model.phase {
        case .idle: ""
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .inserted: "Text inserted"
        case .command(let result): result.text
        case .acting(let progress): progress.headline
        case .sent(let recipient, let confirmed): confirmed ? "Sent to \(recipient ?? "Slack")" : "Probably sent to \(recipient ?? "Slack"), check Slack"
        case .stopped: "Stopped, nothing sent"
        case .error(let error, _): error.message
        }
    }
}

struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// Blur + scale + opacity together, so new content reads as a material settling into focus.
    static var materialize: AnyTransition {
        .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
            .combined(with: .scale(scale: 0.9, anchor: .top))
            .combined(with: .opacity)
    }
}

/// The notch, grown: a square top whose corners flare outward into the menu bar through concave
/// shoulders, and rounded bottom corners (geometry from boring.notch / DynamicNotchKit). Floating style
/// is a continuous rounded rect.
struct OverlayShape: Shape {
    var style: NotchGeometry.Style
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(_ shape: NotchGeometry.Shape) {
        style = shape.style
        topRadius = shape.topRadius
        bottomRadius = shape.bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { (topRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        if style == .floating {
            return RoundedRectangle(cornerRadius: min(bottomRadius, rect.height / 2), style: .continuous).path(in: rect)
        }
        let t = min(topRadius, rect.width / 4)  // shoulder
        let b = min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2)  // bottom corner
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left shoulder: curves from the menu bar edge into the notch's side.
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Right shoulder.
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
