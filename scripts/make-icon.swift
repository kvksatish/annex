// Renders assets/AppIcon.icns: two overlapping screens on a blue→purple squircle.
import AppKit

func render(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                          xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 1.0, alpha: 1),
                        NSColor(red: 0.55, green: 0.30, blue: 0.95, alpha: 1)])!.draw(in: bg, angle: -50)
    func screen(_ x: CGFloat, _ y: CGFloat, _ alpha: CGFloat) {
        let r = NSRect(x: x * s, y: y * s, width: 440 * s, height: 286 * s)
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: 28 * s, yRadius: 28 * s).fill()
        NSColor(red: 0.12, green: 0.16, blue: 0.35, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 22 * s, dy: 22 * s), xRadius: 12 * s, yRadius: 12 * s).fill()
    }
    screen(222, 470, 0.55)
    screen(362, 300, 1.0)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                   (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    try! render(CGFloat(px)).write(to: set.appendingPathComponent("icon_\(name).png"))
}
