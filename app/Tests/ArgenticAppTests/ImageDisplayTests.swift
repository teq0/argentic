import ArgenticCore
import CoreGraphics
import XCTest
@testable import Argentic
#if os(macOS)
import AppKit
import SwiftUI
#endif

final class ImageDisplayTests: XCTestCase {
    func testActualPixelsUsesPhysicalDisplayPixelsIncludingRetina() {
        for scale: CGFloat in [1, 2, 3] {
            let layout = ImageDisplayLayout(imageSize: CGSize(width: 1600, height: 1200),
                availableSize: CGSize(width: 600, height: 400), mode: .actualPixels, displayScale: scale)
            XCTAssertEqual(layout.displayedSize.width, 1600 / scale, accuracy: 1e-10)
            XCTAssertEqual(layout.displayedSize.height, 1200 / scale, accuracy: 1e-10)
            XCTAssertEqual(layout.magnification, 1, accuracy: 1e-10)
        }
    }

    func testFitPreservesAspectRatioAndReportsUpscaling() {
        let layout = ImageDisplayLayout(imageSize: CGSize(width: 640, height: 480),
            availableSize: CGSize(width: 1200, height: 700), mode: .fitToWindow, displayScale: 2)
        XCTAssertEqual(layout.displayedSize.height, 700, accuracy: 1e-10)
        XCTAssertEqual(layout.displayedSize.width / layout.displayedSize.height, 4 / 3, accuracy: 1e-10)
        XCTAssertLessThanOrEqual(layout.displayedSize.width, 1200)
        XCTAssertEqual(layout.magnification, (700 / 480) * 2, accuracy: 1e-10)
        XCTAssertGreaterThan(layout.magnification, 1, "Fit can enlarge pixels; Actual Pixels must not")
    }

    func testActualPixelsDoesNotEnlargeSmallImagesToFillTheWindow() {
        let layout = ImageDisplayLayout(imageSize: CGSize(width: 320, height: 240),
            availableSize: CGSize(width: 1200, height: 800), mode: .actualPixels, displayScale: 2)
        XCTAssertEqual(layout.displayedSize, CGSize(width: 160, height: 120))
    }

    func testGesturesAndSelectionMapToTheSameImagePixelsInBothModes() throws {
        for mode in ImageDisplayMode.allCases {
            for scale: CGFloat in [1, 2, 3] {
                let layout = ImageDisplayLayout(imageSize: CGSize(width: 1600, height: 1200),
                    availableSize: CGSize(width: 600, height: 400), mode: mode, displayScale: scale)
                let source = CGRect(x: 200, y: 300, width: 400, height: 150)
                let displayed = layout.displayedRect(from: source)
                let start = try XCTUnwrap(layout.imagePoint(from: displayed.origin))
                let end = try XCTUnwrap(layout.imagePoint(from: CGPoint(x: displayed.maxX, y: displayed.maxY)))
                XCTAssertEqual(start.x, source.minX, accuracy: 1e-10)
                XCTAssertEqual(start.y, source.minY, accuracy: 1e-10)
                XCTAssertEqual(end.x, source.maxX, accuracy: 1e-10)
                XCTAssertEqual(end.y, source.maxY, accuracy: 1e-10)
                XCTAssertEqual(layout.imagePoint(from: CGPoint(x: -100, y: -100)), .zero)
                XCTAssertEqual(layout.imagePoint(from: CGPoint(x: 100_000, y: 100_000)), CGPoint(x: 1600, y: 1200))
            }
        }
    }

    func testZeroSizedFitLayoutAndInvalidBackingScaleAreSafe() {
        let hidden = ImageDisplayLayout(imageSize: CGSize(width: 640, height: 480),
            availableSize: .zero, mode: .fitToWindow, displayScale: 2)
        XCTAssertEqual(hidden.displayedSize, .zero)
        XCTAssertNil(hidden.imagePoint(from: .zero))
        let invalid = ImageDisplayLayout(imageSize: .zero,
            availableSize: CGSize(width: 600, height: 400), mode: .actualPixels, displayScale: 2)
        XCTAssertEqual(invalid.displayedSize, .zero)
        let fallback = ImageDisplayLayout(imageSize: CGSize(width: 640, height: 480),
            availableSize: .zero, mode: .actualPixels, displayScale: 0)
        XCTAssertEqual(fallback.magnification, 1)
    }

    @MainActor
    func testDisplayModeDoesNotChangeRenderParametersOrStartRendering() {
        let model = FractalModel(defaults: nil)
        let original = model.parameters
        for mode in ImageDisplayMode.allCases {
            model.imageDisplayMode = mode
            XCTAssertEqual(model.parameters, original)
            XCTAssertFalse(model.isRendering)
        }
    }

    @MainActor
    func testImageDisplayPreferenceIsOptInAndOlderSnapshotsStillLoad() throws {
        let suite = "ArgenticImageDisplay.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = FractalModel(defaults: defaults)
        let other: ImageDisplayMode = ImageDisplayMode.platformDefault == .actualPixels ? .fitToWindow : .actualPixels
        model.imageDisplayMode = other
        XCTAssertEqual(FractalModel(defaults: defaults).imageDisplayMode, .platformDefault)
        model.savedSettingGroups = [.display]
        XCTAssertEqual(FractalModel(defaults: defaults).imageDisplayMode, other)
        let data = try XCTUnwrap(defaults.data(forKey: "savedAppSettings"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "imageDisplayMode")
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: "savedAppSettings")
        XCTAssertEqual(FractalModel(defaults: defaults).imageDisplayMode, .platformDefault)
    }

    #if os(macOS)
    @MainActor
    func testActualPixelsHostsNativeTwoAxisScrollViewForOversizedImage() async throws {
        let model = FractalModel(defaults: nil)
        model.imageDisplayMode = .actualPixels
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 2048, height: 2048, bitsPerComponent: 8,
            bytesPerRow: 2048 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        model.image = try XCTUnwrap(bitmap.makeImage())
        let original = model.parameters
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ContentView(model: model))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func findScrollView(in view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
        }
        let deadline = Date().addingTimeInterval(3)
        while (findScrollView(in: host)?.documentView?.frame.width ?? 0) == 0 && Date() < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        let scroll = try XCTUnwrap(findScrollView(in: host))
        XCTAssertTrue(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.hasVerticalScroller)
        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.width, scroll.contentSize.width)
        XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, scroll.contentSize.height)
        XCTAssertEqual(model.parameters, original)
        XCTAssertFalse(model.isRendering)
    }

    @MainActor
    func testViewMenuContainsImageDisplayOptionsWithoutAnotherViewMenu() throws {
        let menus = try XCTUnwrap(NSApp.mainMenu).items.filter { $0.title == "View" }
        XCTAssertEqual(menus.count, 1)
        let view = try XCTUnwrap(menus.first?.submenu)
        let display = try XCTUnwrap(view.items.first { $0.title == "Image Display" }?.submenu)
        for mode in ImageDisplayMode.allCases {
            XCTAssertTrue(display.items.contains { $0.title == mode.title })
        }
    }
    #endif
}
