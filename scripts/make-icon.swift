// Renders the app icon: a minimal disc on a dark squircle. Usage: swift scripts/make-icon.swift <outdir>
import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = s / 1024
    // Squircle background (macOS grid: 824pt body inset 100pt).
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1),
                                 CGColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    let c = CGPoint(x: s / 2, y: s / 2)
    // Disc body
    let r = 300 * k
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setFillColor(CGColor(gray: 0.055, alpha: 1)); ctx.fillPath()
    // Grooves
    var gr = r - 14 * k
    var i = 0
    while gr > 92 * k {
        ctx.addEllipse(in: CGRect(x: c.x - gr, y: c.y - gr, width: 2 * gr, height: 2 * gr))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: i % 3 == 0 ? 0.075 : 0.035))
        ctx.setLineWidth(max(1, 1.6 * k)); ctx.strokePath()
        gr -= 11 * k; i += 1
    }
    // Soft light sweep across the disc
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0.25, 0.5, 0.75])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: c.x - r, y: c.y + r), end: CGPoint(x: c.x + r, y: c.y - r), options: [])
    ctx.restoreGState()
    // Rim
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16)); ctx.setLineWidth(3 * k); ctx.strokePath()
    // Label + spindle hole
    let lr = 78 * k
    ctx.addEllipse(in: CGRect(x: c.x - lr, y: c.y - lr, width: 2 * lr, height: 2 * lr))
    ctx.setFillColor(CGColor(gray: 0.95, alpha: 1)); ctx.fillPath()
    let hr = 15 * k
    ctx.addEllipse(in: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr))
    ctx.setFillColor(CGColor(gray: 0.07, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // Inner border of the squircle
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08)); ctx.setLineWidth(2 * k); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try! render(1024).write(to: outDir.appendingPathComponent("icon-1024.png"))
print("wrote \(iconset.path)")
