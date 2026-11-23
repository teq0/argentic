#if os(macOS)
import AppKit
import ArgenticCore
import XCTest
@testable import Argentic

final class LyapunovMenuTests: XCTestCase {
    @MainActor
    func testClearIsAnActionEnabledOnlyWhileLyapunovIsActive() throws {
        let render = try XCTUnwrap(NSApp.mainMenu?.items.first { $0.title == "Render" }?.submenu)
        let lyapunov = try XCTUnwrap(render.items.first { $0.title.hasPrefix("Lyapunov") }?.submenu)
        lyapunov.update()
        let clear = try XCTUnwrap(lyapunov.items.first { $0.title == "Clear" })
        let startup = ExampleCatalog.startupParameters
        let active = (101...120).contains(startup.formula) || (30...32).contains(startup.render)
        // SwiftUI may omit the native action while the command is disabled.
        if active { XCTAssertNotNil(clear.action) }
        XCTAssertEqual(clear.state, .off, "Clear is a command, not a checked mode")
        XCTAssertEqual(clear.isEnabled, active)
        XCTAssertFalse(lyapunov.items.contains { $0.title == "Off" })
        if !active {
            for title in ["Map", "Derivative", "Mapping"] {
                let submenu = try XCTUnwrap(lyapunov.items.first { $0.title == title }?.submenu)
                XCTAssertTrue(submenu.items.allSatisfy { $0.state == .off }, "Inactive \(title) must not show a selection")
            }
        }
    }
}
#endif
