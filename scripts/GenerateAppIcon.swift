// Roll film-cartridge icon. Original repository artwork, authored as geometry for Roll.
// Copyright (c) 2026 Lucas Cacao Souza. Distributed under the repository MIT license.
// No input images, fonts, SF Symbols, downloaded assets or image-generation service.
// Reproduce: xcrun swift scripts/GenerateAppIcon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("PhotoImporter/Assets.xcassets/AppIcon.appiconset")
let preview = root.appendingPathComponent("docs/branding/roll-icon.png")
let space = CGColorSpaceCreateDeviceRGB()
func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let ivory = color(0xF4EBDD), charcoal = color(0x242424), amber = color(0xC77736)
func rounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
    context.setFillColor(fill)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}
func render(_ size: Int) throws -> CGImage {
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    ctx.setAllowsAntialiasing(true)
    rounded(ctx, CGRect(x: 64, y: 64, width: 896, height: 896), radius: 194, fill: ivory)

    // A short, dark negative with two rows of perforations; intentionally no lettering.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x242424, alpha: 0.16))
    rounded(ctx, CGRect(x: 531, y: 312, width: 290, height: 376), radius: 44, fill: color(0x4C4B40))
    ctx.restoreGState()
    for x in stride(from: 572, through: 752, by: 60) {
        for y in [342, 624] {
            rounded(ctx, CGRect(x: x, y: y, width: 30, height: 34), radius: 8, fill: ivory)
        }
    }
    rounded(ctx, CGRect(x: 580, y: 412, width: 202, height: 168), radius: 16, fill: color(0x74745F))

    // Cartridge silhouette and the smaller winding spindle.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0x242424, alpha: 0.23))
    rounded(ctx, CGRect(x: 238, y: 190, width: 376, height: 620), radius: 74, fill: charcoal)
    ctx.restoreGState()
    rounded(ctx, CGRect(x: 352, y: 760, width: 148, height: 112), radius: 24, fill: color(0x303030))
    ctx.setFillColor(color(0x505047)); ctx.fillEllipse(in: CGRect(x: 352, y: 838, width: 148, height: 42))
    ctx.setFillColor(color(0x191919)); ctx.fillEllipse(in: CGRect(x: 374, y: 849, width: 104, height: 22))

    // Amber paper label, with subtle light/shade from original vector geometry.
    rounded(ctx, CGRect(x: 272, y: 250, width: 308, height: 488), radius: 26, fill: amber)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 272, y: 250, width: 308, height: 488),
                       cornerWidth: 26, cornerHeight: 26, transform: nil)); ctx.clip()
    let stops = [color(0xE0A16A), amber, color(0xA55A29)] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.45, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 272, y: 500),
                               end: CGPoint(x: 580, y: 500), options: [])
    }
    ctx.restoreGState()
    rounded(ctx, CGRect(x: 302, y: 298, width: 16, height: 390), radius: 8, fill: color(0xF4EBDD, alpha: 0.60))
    rounded(ctx, CGRect(x: 262, y: 734, width: 328, height: 51), radius: 22, fill: color(0x363632))
    rounded(ctx, CGRect(x: 262, y: 209, width: 328, height: 51), radius: 22, fill: color(0x30302C))
    ctx.setFillColor(color(0x5E5D52)); ctx.fillEllipse(in: CGRect(x: 262, y: 764, width: 328, height: 38))
    ctx.setFillColor(charcoal); ctx.fillEllipse(in: CGRect(x: 287, y: 773, width: 278, height: 20))
    guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return image
}
func write(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
}
let slots: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in slots { try write(render(size), to: catalog.appendingPathComponent(name)) }
try write(render(1024), to: preview)
print("Generated ten macOS AppIcon slots and docs/branding/roll-icon.png from original geometry.")
