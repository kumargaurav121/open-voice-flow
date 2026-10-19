import AppKit

/// The app icon's mark for the menu bar: a voice wave that settles into a line, ending at a text cursor.
/// Drawn as a vector template image, so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarIcon {
    static func image(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            wave().stroke()
            NSBezierPath(roundedRect: NSRect(x: 14.6, y: 4.2, width: 1.8, height: 9.6), xRadius: 0.9, yRadius: 0.9).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Same curve as Resources/AppIcon.svg: swells in, then decays over two and a half cycles into a flat line.
    private static func wave() -> NSBezierPath {
        let (start, end, lineEnd, middle, amplitude) = (1.6, 11.0, 12.6, 9.0, 6.8)
        let path = NSBezierPath()
        for step in 0...120 {
            let t = Double(step) / 120
            let envelope = sin(.pi * min(t / 0.25, 1) / 2) * pow(1 - t, 1.1)
            let point = NSPoint(x: start + (end - start) * t, y: middle - amplitude * envelope * sin(2 * .pi * 2.5 * t))
            step == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.line(to: NSPoint(x: lineEnd, y: middle))
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }
}
