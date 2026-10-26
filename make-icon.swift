// Renders AppIcon.icns: ./make-icon.swift  (needs only the Command Line Tools)
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Icon body: 824/1024 of the canvas, per Apple's macOS grid.
    let body = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)

    // Soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    path.fill()
    ctx.restoreGState()

    // Background gradient.
    ctx.saveGState()
    path.addClip()
    let grad = NSGradient(colors: [NSColor(red: 1.00, green: 0.36, blue: 0.40, alpha: 1),
                                   NSColor(red: 0.80, green: 0.08, blue: 0.20, alpha: 1)])!
    grad.draw(in: body, angle: -90)
    // Top sheen.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    ctx.restoreGState()

    // Glyph: arrow pointing into a tray, in white.
    let cx = body.midX, u = body.width / 100
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -u * 1.2), blur: u * 3,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.setFill(); NSColor.white.setStroke()

    let w = 8.5 * u
    let shaft = NSBezierPath()
    shaft.lineWidth = w; shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: cx, y: body.minY + 80 * u))
    shaft.line(to: NSPoint(x: cx, y: body.minY + 40 * u))
    shaft.stroke()
    let head = NSBezierPath()
    head.lineWidth = w; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.move(to: NSPoint(x: cx - 16 * u, y: body.minY + 56 * u))
    head.line(to: NSPoint(x: cx, y: body.minY + 40 * u))
    head.line(to: NSPoint(x: cx + 16 * u, y: body.minY + 56 * u))
    head.stroke()
    let tray = NSBezierPath()
    tray.lineWidth = w; tray.lineCapStyle = .round; tray.lineJoinStyle = .round
    tray.move(to: NSPoint(x: cx - 26 * u, y: body.minY + 32 * u))
    tray.line(to: NSPoint(x: cx - 26 * u, y: body.minY + 22 * u))
    tray.line(to: NSPoint(x: cx + 26 * u, y: body.minY + 22 * u))
    tray.line(to: NSPoint(x: cx + 26 * u, y: body.minY + 32 * u))
    tray.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
