import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/draw_icon.swift OUTPUT.png")
}

let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 215, yRadius: 215)
let blue = NSGradient(
    starting: NSColor(calibratedRed: 0.03, green: 0.52, blue: 0.83, alpha: 1),
    ending: NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.37, alpha: 1)
)!
blue.draw(in: tile, angle: -60)

// Soft light behind the Wi-Fi mark keeps the icon legible at small sizes.
let glow = NSGradient(
    starting: NSColor(calibratedWhite: 1, alpha: 0.15),
    ending: NSColor(calibratedWhite: 1, alpha: 0)
)!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: 85, y: 160, width: 800, height: 800)), relativeCenterPosition: .zero)

let center = NSPoint(x: 487, y: 283)
NSColor.white.setStroke()
for (radius, width) in [(315.0, 58.0), (218.0, 58.0), (121.0, 58.0)] {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 43, endAngle: 137)
    arc.lineWidth = width
    arc.lineCapStyle = .round
    arc.stroke()
}
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)).fill()

// One warm star denotes the preferred network without adding tiny text.
let star = NSBezierPath()
let starCenter = NSPoint(x: 766, y: 749)
for point in 0..<10 {
    let angle = CGFloat.pi / 2 + CGFloat(point) * CGFloat.pi / 5
    let radius: CGFloat = point.isMultiple(of: 2) ? 93 : 43
    let next = NSPoint(
        x: starCenter.x + cos(angle) * radius,
        y: starCenter.y + sin(angle) * radius
    )
    if point == 0 { star.move(to: next) } else { star.line(to: next) }
}
star.close()
NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.25, alpha: 1).setFill()
star.fill()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
