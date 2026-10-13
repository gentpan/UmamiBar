// Renders Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

// macOS squircle: superellipse |x/a|^n + |y/b|^n = 1, n ~= 5
func squirclePath(in rect: CGRect, n: CGFloat = 5) -> CGPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = CGMutablePath()
    let steps = 512
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * pow(abs(c), 2 / n) * (c >= 0 ? 1 : -1)
        let y = cy + b * pow(abs(s), 2 / n) * (s >= 0 ? 1 : -1)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
        else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(_ ctx: CGContext) {
    let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: iconRect)

    // background gradient
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(red: 0.11, green: 0.50, blue: 0.96, alpha: 1)     // flat brand blue
    let bottom = top
    let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                           end: CGPoint(x: iconRect.midX, y: iconRect.minY),
                           options: [])
    ctx.restoreGState()

    // subtle top sheen
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let sheenTop = CGColor(gray: 1, alpha: 0.14)
    let sheenClear = CGColor(gray: 1, alpha: 0)
    let sheen = CGGradient(colorsSpace: space, colors: [sheenTop, sheenClear] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                           end: CGPoint(x: iconRect.midX, y: iconRect.maxY - 500),
                           options: [])
    ctx.restoreGState()

    // Umami mark glyph: ring outline + filled bowl, from the official
    // 20×20 viewBox scaled onto the icon.
    let glyph = CGColor(gray: 1, alpha: 0.96)

    ctx.saveGState()
    let markRect = iconRect.insetBy(dx: iconRect.width * 0.11, dy: iconRect.height * 0.11)
    ctx.translateBy(x: markRect.minX, y: markRect.minY)
    let unit = markRect.width / 20
    ctx.scaleBy(x: unit, y: unit)

    ctx.setStrokeColor(glyph)
    ctx.setLineWidth(0.9346)
    ctx.addEllipse(in: CGRect(x: 2, y: 1.4, width: 16, height: 16))
    ctx.strokePath()

    let bowl = CGMutablePath()
    bowl.move(to: CGPoint(x: 19.3, y: 7.2))
    bowl.addLine(to: CGPoint(x: 0.7, y: 7.2))
    bowl.addCurve(to: CGPoint(x: 0, y: 7.9),
                  control1: CGPoint(x: 0.3, y: 7.2),
                  control2: CGPoint(x: 0, y: 7.5))
    bowl.addLine(to: CGPoint(x: 0, y: 9.1))
    bowl.addCurve(to: CGPoint(x: 10, y: 19.1),
                  control1: CGPoint(x: 0, y: 14.6),
                  control2: CGPoint(x: 4.5, y: 19.1))
    bowl.addCurve(to: CGPoint(x: 20, y: 9.3),
                  control1: CGPoint(x: 15.4, y: 19.1),
                  control2: CGPoint(x: 19.9, y: 14.8))
    bowl.addLine(to: CGPoint(x: 20, y: 7.9))
    bowl.addCurve(to: CGPoint(x: 19.3, y: 7.2),
                  control1: CGPoint(x: 20, y: 7.5),
                  control2: CGPoint(x: 19.7, y: 7.2))
    bowl.closeSubpath()
    ctx.setFillColor(glyph)
    ctx.addPath(bowl)
    ctx.fillPath()
    ctx.restoreGState()
}

func renderPNG(size: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: size / canvas, y: size / canvas)
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        drawIcon(ctx)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for spec in specs {
    renderPNG(size: spec.px, to: iconset.appendingPathComponent(spec.name).path)
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
print("Wrote \(out.path)")
