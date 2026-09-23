#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A flat, scalable version of the sound ribbon used in the website hero.
// Run from the repository root through scripts/generate-app-icon.sh.

let iconSizes: [(String, Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64),
    ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512),
]

func ribbonPoint(_ t: CGFloat) -> CGPoint {
    let envelope = pow(max(sin(.pi * t), 0), 0.8)
    return CGPoint(
        x: 132 + 760 * t,
        y: 420 + 180 * t + 90 * envelope * sin(4 * .pi * t - 0.36)
    )
}

func stripePoint(_ t: CGFloat, index: Int, count: Int) -> CGPoint {
    let offset = CGFloat(index - count / 2) * 19
    let point = ribbonPoint(t)
    let before = ribbonPoint(max(0, t - 0.001))
    let after = ribbonPoint(min(1, t + 0.001))
    let dx = after.x - before.x
    let dy = after.y - before.y
    let length = hypot(dx, dy)
    let taper = pow(max(sin(.pi * t), 0), 0.65)
    return CGPoint(x: point.x - dy / length * offset * taper,
                   y: point.y + dx / length * offset * taper)
}

func drawRibbonStripe(in context: CGContext, index: Int, count: Int) {
    let samples = 240
    context.setLineCap(.round)
    for sample in 0..<samples {
        let start = CGFloat(sample) / CGFloat(samples)
        let end = CGFloat(sample + 1) / CGFloat(samples)
        let middle = (start + end) / 2
        let taper = pow(max(sin(.pi * middle), 0), 0.65)
        context.setLineWidth(2 + 10 * taper)
        context.move(to: stripePoint(start, index: index, count: count))
        context.addLine(to: stripePoint(end, index: index, count: count))
        context.strokePath()
    }
}

func drawRibbon(in context: CGContext) {
    let blues: [(CGFloat, CGFloat, CGFloat)] = [
        (0.07, 0.25, 0.78), (0.08, 0.31, 0.86), (0.09, 0.38, 0.93),
        (0.07, 0.34, 0.91), (0.05, 0.28, 0.84),
    ]
    for (index, blue) in blues.enumerated() {
        context.setStrokeColor(CGColor(red: blue.0, green: blue.1, blue: blue.2, alpha: 1))
        drawRibbonStripe(in: context, index: index, count: blues.count)
    }
}

func pngData(for image: CGImage) -> Data {
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

func renderIcon(size: Int) -> Data {
    let pixels = size * size * 4
    var buffer = [UInt8](repeating: 0, count: pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let image: CGImage = buffer.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: colorSpace, bitmapInfo: bitmapInfo)!
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let tile = CGPath(roundedRect: CGRect(x: 22, y: 22, width: 980, height: 980),
                          cornerWidth: 222, cornerHeight: 222, transform: nil)
        context.addPath(tile)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillPath()
        context.addPath(tile)
        context.setStrokeColor(CGColor(red: 0.86, green: 0.89, blue: 0.94, alpha: 1))
        context.setLineWidth(3)
        context.strokePath()

        drawRibbon(in: context)
        return context.makeImage()!
    }

    return pngData(for: image)
}

func renderBrandMark() -> Data {
    let width = 800
    let height = 330
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let image: CGImage = buffer.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.translateBy(x: -110, y: -340)
        drawRibbon(in: context)
        return context.makeImage()!
    }
    return pngData(for: image)
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

var icon = Data("icns".utf8)
appendBigEndian(0, to: &icon)
var pngBySize: [Int: Data] = [:]
for (type, size) in iconSizes {
    let png = pngBySize[size] ?? renderIcon(size: size)
    pngBySize[size] = png
    icon.append(contentsOf: type.utf8)
    appendBigEndian(UInt32(png.count + 8), to: &icon)
    icon.append(png)
}
var totalLength = UInt32(icon.count).bigEndian
withUnsafeBytes(of: &totalLength) { icon.replaceSubrange(4..<8, with: $0) }

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
try pngBySize[1024]!.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
try icon.write(to: root.appendingPathComponent("Resources/AppIcon.icns"))
try pngBySize[1024]!.write(to: root.appendingPathComponent("website/assets/app-icon.png"))
try pngBySize[128]!.write(to: root.appendingPathComponent("website/assets/favicon.png"))
try renderBrandMark().write(to: root.appendingPathComponent("website/assets/brand-mark.png"))
