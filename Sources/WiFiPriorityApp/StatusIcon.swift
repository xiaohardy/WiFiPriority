import AppKit
import WiFiPriorityCore

/// A white Wi-Fi mark surrounded by gold stars at fixed clock positions.
enum StatusIcon {
    static func make(state: StatusIndicatorState, paused: Bool) -> NSImage {
        let size = NSSize(width: 33, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            let wifiColor = paused
                ? NSColor(calibratedWhite: 0.54, alpha: 0.86)
                : NSColor.white
            let ringCenter = NSPoint(x: 16.5, y: 11)

            wifiColor.setStroke()
            let wifiCenter = NSPoint(x: 16.5, y: 7)
            for radius: CGFloat in [7.2, 5.0, 2.8] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: wifiCenter, radius: radius, startAngle: 42, endAngle: 138)
                arc.lineWidth = 1.7
                arc.lineCapStyle = .round
                arc.stroke()
            }
            wifiColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: wifiCenter.x - 1.25, y: wifiCenter.y - 1.25,
                                        width: 2.5, height: 2.5)).fill()

            for index in 0..<state.starCount {
                // Index zero is 12 o'clock; each subsequent network advances one hour.
                let angle = CGFloat.pi / 2 - CGFloat(index) * CGFloat.pi / 6
                let center = NSPoint(x: ringCenter.x + cos(angle) * 12.5,
                                     y: ringCenter.y + sin(angle) * 8.1)
                let active = !paused && index == state.activeIndex
                let color = paused
                    ? NSColor(calibratedWhite: 0.54, alpha: 0.86)
                    : active
                        ? NSColor(calibratedRed: 1, green: 0.86, blue: 0.31, alpha: 1)
                        : NSColor(calibratedRed: 1, green: 0.72, blue: 0.16, alpha: 0.69)
                color.setFill()
                starPath(center: center, outer: active ? 2.6 : 1.85,
                         inner: active ? 1.1 : 0.78).fill()
            }
            return true
        }
        image.isTemplate = false // Keep the gold stars when AppKit draws the menu bar item.
        return image
    }

    private static func starPath(center: NSPoint, outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for index in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        return path
    }
}
