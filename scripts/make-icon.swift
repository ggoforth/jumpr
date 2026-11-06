// Draws Jumpr's placeholder icon — a yellow (FFD60A) rounded square with a black bold
// "J" — at every size an .iconset needs, up to 1024 px.
// Usage: swift scripts/make-icon.swift <output.iconset>   (run by `make icon`)
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(pixels n: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: n, height: n)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(n)
    // macOS icon grid: an 824/1024 body centred on the canvas, corner radius ~185/1024.
    let body = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 100 / 1024, dy: s * 100 / 1024)
    NSColor(srgbRed: 0xFF / 255.0, green: 0xD6 / 255.0, blue: 0x0A / 255.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024).fill()

    let text = NSAttributedString(string: "J", attributes: [
        .font: NSFont.systemFont(ofSize: s * 0.58, weight: .bold),
        .foregroundColor: NSColor.black,
    ])
    // Centre the glyph's ink, not its line box.
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let origin = CGPoint(x: body.midX - bounds.midX, y: body.midY - bounds.midY)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = origin
    CTLineDraw(line, ctx)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try draw(pixels: points * scale).write(to: out.appendingPathComponent(name))
    }
}
print("Wrote \(out.path)")
