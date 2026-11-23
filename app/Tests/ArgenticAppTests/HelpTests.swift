import XCTest
@testable import Argentic
#if os(macOS)
import AppKit
#endif

final class HelpTests: XCTestCase {
    func testBundledGuideContainsControlAndFeatureTopics() throws {
        let document = try XCTUnwrap(HelpDocument.load(), "FEATURES.md must be copied into the application bundle")
        let titles = Set(document.topics.map(\.title))
        for title in ["Getting started", "Classic Mandelbrot", "Startup sizing and screen space", "Image display, actual pixels and scrolling", "Bundled examples and the starting image", "Toolbar and status bar", "Click zooming", "Small zoom steps",
                      "Rectangle zooming and Back history", "Formulas, render methods and transforms",
                      "Colour controls", "Fractal parameters and Julia mode", "Image size and anti-aliasing",
                      "CPU and Metal GPU rendering", "Opening pictures and parameter files",
                      "Saving pictures and fractal settings", "Saved Settings and startup defaults",
                      "Full screen and keyboard shortcuts"] {
            XCTAssertTrue(titles.contains(title), "Missing Help topic: \(title)")
        }
        XCTAssertEqual(Set(document.topics.map(\.id)).count, document.topics.count)
        XCTAssertTrue(document.topics.allSatisfy { !$0.markdown.isEmpty })
    }

    func testSearchMatchesTitlesAndBodyIgnoringCase() {
        let document = HelpDocument(markdown: """
        # Guide

        Welcome to Argentic.

        ## Rendering

        The CPU uses double precision.

        ## Saving

        PNG keeps embedded settings.
        """)
        XCTAssertEqual(document.topics.map(\.title), ["About Argentic", "Rendering", "Saving"])
        XCTAssertEqual(document.topics.filter { $0.matches("renderING") }.map(\.title), ["Rendering"])
        XCTAssertEqual(document.topics.filter { $0.matches("  DOUBLE PRECISION  ") }.map(\.title), ["Rendering"])
        XCTAssertEqual(document.topics.filter { $0.matches("embedded") }.map(\.title), ["Saving"])
        XCTAssertEqual(document.topics.filter { $0.matches(" ") }.count, 3)
        XCTAssertTrue(document.topics.filter { $0.matches("not-a-feature") }.isEmpty)
    }

    func testHelpBlockParserPreservesSubheadingsListsAndInlineMarkdown() {
        let blocks = HelpBlock.parse("""
        First paragraph
        continues here.

        ### Toolbar

        - **Draw** renders.
        - **Back** restores coordinates.

        Last paragraph with `PNG`.
        """)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .heading, .bullet, .bullet, .paragraph])
        XCTAssertEqual(blocks.map(\.text), ["First paragraph continues here.", "Toolbar", "**Draw** renders.",
                                          "**Back** restores coordinates.", "Last paragraph with `PNG`."])
        XCTAssertEqual(blocks.map(\.id), [0, 1, 2, 3, 4])
    }

    func testMissingResourceAndEmptyGuideAreHandled() {
        XCTAssertNil(HelpDocument.load(bundle: Bundle(for: HelpTests.self)))
        XCTAssertTrue(HelpDocument(markdown: "# Empty guide\n\n").topics.isEmpty)
        XCTAssertTrue(HelpBlock.parse("").isEmpty)
    }

    #if os(macOS)
    @MainActor
    func testHelpMenuExposesBundledGuide() throws {
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map { items(in: $0) } ?? []) }
        }
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let helpMenu = try XCTUnwrap(menu.items.first { $0.title == "Help" }?.submenu)
        let help = try XCTUnwrap(items(in: helpMenu).first { $0.title == "Argentic Help" })
        XCTAssertNotNil(help.action)
        XCTAssertTrue(help.keyEquivalentModifierMask.contains(.command))
        XCTAssertTrue(["?", "/"].contains(help.keyEquivalent))
    }
    #endif
}
