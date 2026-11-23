// Builds the macOS-only rounded tile. The opaque iOS master remains unchanged.
// Invoked by generate_app_icon.py; no third-party image libraries are required.
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum IconError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

@MainActor
func renderMacIcon() throws {
    guard CommandLine.arguments.count == 3 else {
        throw IconError.failed("Usage: render_macos_icon.swift <source.png> <output.png>")
    }
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
              bytesPerRow: 1024 * 4, space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
        throw IconError.failed("Could not load the artwork or create the macOS icon canvas.")
    }

    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let tile = canvas.insetBy(dx: 100, dy: 100)
    let mask = RoundedRectangle(cornerRadius: 180, style: .continuous).path(in: tile).cgPath
    context.clear(canvas)

    // Draw a subtle shadow under the tile, leaving the outer canvas transparent.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: CGColor(gray: 0, alpha: 0.18))
    context.addPath(mask)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(mask)
    context.clip()
    context.interpolationQuality = .high
    context.draw(artwork, in: tile)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.failed("Could not create the macOS icon PNG.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.failed("Could not save the macOS icon PNG.")
    }
}

do {
    try MainActor.assumeIsolated { try renderMacIcon() }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
