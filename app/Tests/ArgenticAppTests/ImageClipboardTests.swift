#if os(macOS)
import AppKit
import ImageIO
import XCTest
@testable import Argentic

final class ImageClipboardTests: XCTestCase {
    @MainActor
    func testCopyUsesFullResolutionRegardlessOfDisplayScaling() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let model = FractalModel(defaults: nil)
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
            bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        model.image = try XCTUnwrap(bitmap.makeImage())
        for mode in ImageDisplayMode.allCases {
            model.imageDisplayMode = mode
            XCTAssertTrue(model.copyImage(to: pasteboard))
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                let data = try XCTUnwrap(pasteboard.data(forType: type))
                let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(image.width, 48)
                XCTAssertEqual(image.height, 32)
            }
        }
    }

    @MainActor
    func testCopyWithoutImageDoesNotClearExistingClipboardContents() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Keep this clipboard content", forType: .string)
        let model = FractalModel(defaults: nil)
        XCTAssertFalse(model.copyImage(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep this clipboard content")
    }

    @MainActor
    func testEditMenuContainsOnlyCopyImage() throws {
        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
        let actions = edit.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(actions.map(\.title), ["Copy Image"])
        let copy = try XCTUnwrap(actions.first)
        XCTAssertEqual(copy.keyEquivalent, "c")
        XCTAssertTrue(copy.keyEquivalentModifierMask.contains(.command))
    }

    @MainActor
    func testNoEmptyFormatMenuIsCreated() throws {
        let menu = try XCTUnwrap(NSApp.mainMenu)
        XCTAssertFalse(menu.items.contains { $0.title == "Format" })
    }

    @MainActor
    func testSystemTextItemsAreRemovedWhenMenuBeginsTracking() throws {
        let edit = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
        edit.addItem(NSMenuItem(title: "Writing Tools", action: nil, keyEquivalent: ""))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Emoji & Symbols", action: nil, keyEquivalent: ""))
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: edit)
        XCTAssertEqual(edit.items.map(\.title), ["Copy Image"], "The real launch-installed observer must remove late system additions")
    }

    @MainActor
    func testEditMenuPolicyDoesNotModifyOtherMenus() {
        let main = NSMenu()
        let file = NSMenu()
        file.addItem(NSMenuItem(title: "Open", action: nil, keyEquivalent: "o"))
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file
        main.addItem(fileItem)
        let edit = NSMenu()
        edit.addItem(NSMenuItem(title: "Copy Image", action: nil, keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Cut", action: nil, keyEquivalent: "x"))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        ImageEditMenuPolicy.keepOnlyCopyImage(in: main)
        XCTAssertEqual(edit.items.map(\.title), ["Copy Image"])
        XCTAssertEqual(file.items.map(\.title), ["Open"])
    }
}
#endif
