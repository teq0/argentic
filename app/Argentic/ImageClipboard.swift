import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

extension FractalModel {
    #if os(macOS)
    @discardableResult
    func copyImage(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let image else { return false }
        guard let png = imageData(as: .png) else {
            message = "Could not encode the image for copying."
            return false
        }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        // PNG retains embedded settings; TIFF supports apps expecting the traditional macOS image type.
        if let tiff = NSBitmapImageRep(cgImage: image).representation(using: .tiff, properties: [:]) {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            message = "Could not copy the image to the clipboard."
            return false
        }
        return true
    }
    #else
    @discardableResult
    func copyImage() -> Bool {
        guard image != nil else { return false }
        guard let png = imageData(as: .png) else {
            message = "Could not encode the image for copying."
            return false
        }
        UIPasteboard.general.setItems([[UTType.png.identifier: png]])
        return true
    }
    #endif
}
