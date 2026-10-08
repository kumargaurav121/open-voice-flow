import CoreGraphics

/// What the overlay needs to know about a screen, in AppKit global coordinates (origin bottom-left).
public struct ScreenInfo: Sendable, Equatable {
    public var frame: CGRect
    /// The camera housing, or nil on displays without one.
    public var notch: CGRect?
    public var menuBarHeight: CGFloat

    public init(frame: CGRect, notch: CGRect?, menuBarHeight: CGFloat) {
        self.frame = frame
        self.notch = notch
        self.menuBarHeight = menuBarHeight
    }
}

/// Where the overlay sits and how it's shaped.
///
/// On a notched display the notch itself grows down into a panel (NotchNook-style): concave shoulders flare
/// its top corners into the menu bar (geometry from boring.notch / DynamicNotchKit), the camera sits in
/// the panel's top row, and content lives below it. Without a notch the same panel floats just below the
/// menu bar, with fully rounded corners.
public enum NotchGeometry {
    public enum Size: Sendable, Equatable {
        /// Listening, transcribing, ✓.
        case compact
        /// A one-line error.
        case message
        /// The error with its details, after a click.
        case details

        public init?(for phase: NotchStateMachine.Phase) {
            switch phase {
            case .idle: return nil
            case .listening, .transcribing, .inserted: self = .compact
            case .error(_, let expanded): self = expanded ? .details : .message
            }
        }
    }

    public enum Style: Sendable, Equatable {
        /// Grows out of the hardware notch; square top with concave shoulders.
        case notch
        /// Free-floating rounded pill.
        case floating
    }

    public struct Shape: Sendable, Equatable {
        public var frame: CGRect
        /// Concave shoulder radius at the top corners (0 when floating).
        public var topRadius: CGFloat
        public var bottomRadius: CGFloat
        public var style: Style
    }

    /// Without a notch: the same panel floats this far below the menu bar, with a header row in place of
    /// the camera row.
    public static let floatingGap: CGFloat = 6
    public static let floatingHeaderHeight: CGFloat = 30

    /// MacBook: the notch grows down into a panel. The camera row holds context beside the camera;
    /// the body below holds the mic, the live waveform and the timer (or the error).
    public static let panelWidth: CGFloat = 400
    public static let panelBodyHeight: CGFloat = 60
    static let panelDetailsHeight: CGFloat = 64
    /// Each side of the camera must keep at least this much room for the context row.
    static let panelSideMinimum: CGFloat = 80

    /// Shadow only shows when open; the panel reserves room so it isn't clipped.
    public static let shadowPadding: CGFloat = 20

    public static func shape(for size: Size, on screen: ScreenInfo) -> Shape {
        if let notch = screen.notch {
            let width = max(panelWidth, notch.width + 2 * panelSideMinimum)
            let height = notch.height + panelBodyHeight + (size == .details ? panelDetailsHeight : 0)
            let frame = CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
            return Shape(frame: frame, topRadius: 10, bottomRadius: 26, style: .notch)
        }
        let height = floatingHeaderHeight + panelBodyHeight + (size == .details ? panelDetailsHeight : 0)
        let top = screen.frame.maxY - screen.menuBarHeight - floatingGap
        let frame = CGRect(x: screen.frame.midX - panelWidth / 2, y: top - height, width: panelWidth, height: height)
        return Shape(frame: frame, topRadius: 0, bottomRadius: 26, style: .floating)
    }

    /// The panel: big enough for the largest shape plus its shadow, hanging from the top of the screen.
    /// The view animates the visible shape inside it, so the window itself never resizes mid-spring.
    public static func panelFrame(on screen: ScreenInfo) -> CGRect {
        let largest = shape(for: .details, on: screen).frame
        let minY = largest.minY - shadowPadding
        return CGRect(x: largest.minX - shadowPadding, y: minY,
                      width: largest.width + 2 * shadowPadding, height: screen.frame.maxY - minY)
    }
}
