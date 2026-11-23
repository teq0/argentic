#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import Argentic

final class FullScreenWindowTests: XCTestCase {
    @MainActor
    private final class TestWindow: NSWindow {
        var visibleForTesting = false
        var keyForTesting = true
        var fullScreenForTesting = false
        var toggleCount = 0
        var didToggle: (() -> Void)?
        override var isVisible: Bool { visibleForTesting }
        override var isKeyWindow: Bool { visibleForTesting && keyForTesting }
        override var styleMask: NSWindow.StyleMask {
            get {
                fullScreenForTesting ? super.styleMask.union(.fullScreen) : super.styleMask.subtracting(.fullScreen)
            }
            set { super.styleMask = newValue }
        }
        override func toggleFullScreen(_ sender: Any?) { toggleCount += 1; didToggle?() }
    }

    @MainActor
    private func window() -> TestWindow {
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @MainActor
    func testNoCustomFullScreenCommandRemains() throws {
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { item in [item] + (item.submenu.map { items(in: $0) } ?? []) }
        }
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let fullScreenItems = items(in: menu).filter { $0.title.hasPrefix("Enter Full Screen") || $0.title.hasPrefix("Exit Full Screen") }
        // AppKit creates its system item lazily; it may be absent in an XCTest-hosted menu.
        XCTAssertLessThanOrEqual(fullScreenItems.count, 1)
        for item in fullScreenItems {
            XCTAssertFalse(item.title.contains("(Fn"), "Leave the native menu item and shortcut untouched")
        }
    }

    @MainActor
    func testNativeWindowTabbingAndTabMenuCommandsAreDisabled() throws {
        XCTAssertFalse(NSWindow.allowsAutomaticWindowTabbing)
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map { items(in: $0) } ?? []) }
        }
        let tabActions = Set([
            NSStringFromSelector(#selector(NSWindow.toggleTabBar(_:))),
            NSStringFromSelector(#selector(NSWindow.toggleTabOverview(_:))),
            NSStringFromSelector(#selector(NSWindow.mergeAllWindows(_:))),
            NSStringFromSelector(#selector(NSWindow.moveTabToNewWindow(_:))),
        ])
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let commands = items(in: menu).filter { item in
            item.action.map { tabActions.contains(NSStringFromSelector($0)) } ?? false
        }
        XCTAssertTrue(commands.isEmpty, "Tab commands must not be offered for the single-image window: \(commands.map(\.title))")
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ArgenticFullScreenTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @MainActor
    func testRestorationWaitsForVisibleWindowAndOnlyRunsOnce() async {
        let model = FractalModel(defaults: nil)
        model.isFullScreen = true
        let window = window()
        let coordinator = FullScreenWindowObserver.Coordinator(model: model)
        coordinator.attach(to: window)
        defer { coordinator.detach() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(window.toggleCount, 0)
        window.visibleForTesting = true
        window.keyForTesting = false
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(window.toggleCount, 0, "Wait until the window is actually ready for full screen")
        window.keyForTesting = true
        let toggled = expectation(description: "Native restoration is queued after window ordering")
        window.didToggle = { toggled.fulfill() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        await fulfillment(of: [toggled], timeout: 2)
        XCTAssertEqual(window.toggleCount, 1)
        XCTAssertFalse(window.isRestorable)
        XCTAssertEqual(window.tabbingMode, .disallowed)
        window.fullScreenForTesting = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
        XCTAssertTrue(model.isFullScreen, "Keep the last completed state until an exit finishes")
        window.fullScreenForTesting = false
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertFalse(model.isFullScreen)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(window.toggleCount, 1, "Do not restore again when the window regains focus")
    }

    @MainActor
    func testWindowedLaunchAndClosingDoNotEraseFullScreenPreference() {
        let model = FractalModel(defaults: nil)
        let window = window()
        window.visibleForTesting = true
        let coordinator = FullScreenWindowObserver.Coordinator(model: model)
        coordinator.attach(to: window)
        defer { coordinator.detach() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        XCTAssertEqual(window.toggleCount, 0)
        NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
        window.fullScreenForTesting = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertTrue(model.isFullScreen)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertTrue(model.isFullScreen)
    }

    @MainActor
    func testQuittingCapturesActualWindowStateBeforeFullScreenTeardown() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = [.fullScreen]
            let window = window()
            window.visibleForTesting = true
            let coordinator = FullScreenWindowObserver.Coordinator(model: model)
            coordinator.attach(to: window)
            defer { coordinator.detach() }
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

            // Even if the completed-entry notification was missed, read the real native state.
            window.fullScreenForTesting = true
            XCTAssertFalse(model.isFullScreen)
            XCTAssertEqual(ApplicationLifecycle().applicationShouldTerminate(NSApp), .terminateNow)
            XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen)

            // AppKit may exit full screen after the user has already requested Quit.
            NotificationCenter.default.post(name: NSWindow.willExitFullScreenNotification, object: window)
            window.fullScreenForTesting = false
            NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
            model.saveSettings()
            XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen)
        }
    }

    @MainActor
    func testSaveSettingsReadsNativeStateAndHonoursOptOut() throws {
        try withDefaults { defaults in
            let model = FractalModel(defaults: defaults)
            model.savedSettingGroups = [.fullScreen]
            let window = window()
            window.visibleForTesting = true
            let coordinator = FullScreenWindowObserver.Coordinator(model: model)
            coordinator.attach(to: window)
            defer { coordinator.detach() }
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            window.fullScreenForTesting = true
            model.saveSettings()
            XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen)
            model.savedSettingGroups = []
            XCTAssertFalse(FractalModel(defaults: defaults).isFullScreen)
        }
    }

    @MainActor
    func testTemporaryProbeDetachmentDoesNotLoseFullScreenTracking() {
        let model = FractalModel(defaults: nil)
        let window = window()
        window.visibleForTesting = true
        let coordinator = FullScreenWindowObserver.Coordinator(model: model)
        coordinator.attach(to: window)
        defer { coordinator.detach() }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        coordinator.attach(to: nil)
        window.fullScreenForTesting = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertTrue(model.isFullScreen)
        coordinator.attach(to: window)
        XCTAssertEqual(window.toggleCount, 0, "Do not run launch restoration again during a view move")
    }

    @MainActor
    func testHostedWindowProbeInstallsNativeTracking() async throws {
        let model = FractalModel(defaults: nil)
        let window = window()
        let host = NSHostingView(rootView: Color.clear
            .frame(width: 200, height: 200)
            .background(FullScreenWindowObserver(model: model).allowsHitTesting(false)))
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let deadline = Date().addingTimeInterval(2)
        while model.fullScreenStateProvider == nil && Date() < deadline {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(model.fullScreenStateProvider, "The real SwiftUI/AppKit bridge must attach to its window")
        window.visibleForTesting = true
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        window.fullScreenForTesting = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertTrue(model.isFullScreen)
        XCTAssertTrue(model.fullScreenStateForSaving)
    }

    @MainActor
    func testPendingRestorationDoesNotOverwriteSavedFullScreenWithWindowedState() async throws {
        let suite = "ArgenticPendingFullScreen.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = FractalModel(defaults: defaults)
        seed.savedSettingGroups = [.fullScreen]
        seed.isFullScreen = true
        let model = FractalModel(defaults: defaults)
        let window = window()
        window.visibleForTesting = true
        let coordinator = FullScreenWindowObserver.Coordinator(model: model)
        coordinator.attach(to: window)
        defer { coordinator.detach() }
        let toggled = expectation(description: "Native restore request")
        window.didToggle = { [weak window] in
            // Save after the request is issued, but before AppKit begins its animation.
            model.saveSettings()
            XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen,
                          "Requesting native full screen is not a completed restoration")
            if let window {
                NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: window)
            }
            toggled.fulfill()
        }
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        model.saveSettings()
        XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen, "Preserve state while the request is queued")
        await fulfillment(of: [toggled], timeout: 2)
        XCTAssertEqual(window.toggleCount, 1)
        XCTAssertFalse(window.styleMask.contains(.fullScreen))
        model.saveSettings()
        XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen, "Preserve state while the animation is in progress")
        window.fullScreenForTesting = true
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        model.saveSettings()
        XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen)
    }

    @MainActor
    func testNativeFullScreenPersistsAndRestores() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ARGENTIC_NATIVE_FULLSCREEN_TEST"] == "1"
                || environment["TEST_RUNNER_ARGENTIC_NATIVE_FULLSCREEN_TEST"] == "1" else {
            throw XCTSkip("Opt-in native Spaces test; set TEST_RUNNER_ARGENTIC_NATIVE_FULLSCREEN_TEST=1 on an interactive Mac")
        }
        let oldPolicy = NSApp.activationPolicy()
        print("NATIVE FULL SCREEN activation policy: \(oldPolicy.rawValue)")
        _ = NSApp.setActivationPolicy(.regular)
        defer { _ = NSApp.setActivationPolicy(oldPolicy) }
        let suite = "ArgenticNativeFullScreen.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var windows: [NSWindow] = []
        defer { windows.forEach { $0.close() } }
        var traceObservers: [NSObjectProtocol] = []
        defer { traceObservers.forEach(NotificationCenter.default.removeObserver) }
        var completedEntries: Set<ObjectIdentifier> = []

        func waitFor(_ message: String, timeout: TimeInterval = 12, _ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(condition(), message)
            if !condition() { throw NSError(domain: "NativeFullScreenTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func makeWindow(_ model: FractalModel) -> NSWindow {
            model.renderingBackend = .cpu
            model.parameters.width = 32
            model.parameters.height = 24
            model.parameters.maxIterations = 8
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 720, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Argentic Native Full-Screen Regression Test"
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            windows.append(window)
            for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                         NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                traceObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        if name == NSWindow.didEnterFullScreenNotification { completedEntries.insert(ObjectIdentifier(window)) }
                        print("NATIVE FULL SCREEN event \(name.rawValue): native=\(window.styleMask.contains(.fullScreen)), model=\(model.isFullScreen), provider=\(model.fullScreenStateForSaving)")
                    }
                })
            }
            NSApp.activate()
            print("NATIVE FULL SCREEN activation request: \(NSRunningApplication.current.activate(options: [.activateAllWindows]))")
            window.makeKeyAndOrderFront(nil)
            return window
        }

        let model = FractalModel(defaults: defaults)
        model.savedSettingGroups = [.fullScreen]
        let first = makeWindow(model)
        do {
            try await waitFor("The first native window did not become ready; click its title bar to activate it", timeout: 60) {
                first.isKeyWindow && model.fullScreenStateProvider != nil && !model.isRendering && model.progress == 1
            }
        } catch {
            print("NATIVE FULL SCREEN readiness: visible=\(first.isVisible), key=\(first.isKeyWindow), active=\(NSApp.isActive), provider=\(model.fullScreenStateProvider != nil), image=\(model.image != nil)")
            throw error
        }
        first.toggleFullScreen(nil)
        do {
            try await waitFor("The native window did not enter full screen, or its observer missed the transition") {
                completedEntries.contains(ObjectIdentifier(first)) && first.styleMask.contains(.fullScreen) && model.isFullScreen
            }
        } catch {
            print("NATIVE FULL SCREEN entry failure: native=\(first.styleMask.contains(.fullScreen)), model=\(model.isFullScreen), provider=\(model.fullScreenStateForSaving)")
            throw error
        }
        print("NATIVE FULL SCREEN: entered; model=\(model.isFullScreen), provider=\(model.fullScreenStateForSaving)")
        model.saveSettings()
        XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen, "A completed native full-screen entry must be saved")

        _ = ApplicationLifecycle().applicationShouldTerminate(NSApp)
        let exit = expectation(forNotification: NSWindow.didExitFullScreenNotification, object: first)
        first.toggleFullScreen(nil)
        await fulfillment(of: [exit], timeout: 12)
        first.close()
        XCTAssertTrue(FractalModel(defaults: defaults).isFullScreen, "Quit teardown must not overwrite full screen")

        let restored = FractalModel(defaults: defaults)
        print("NATIVE FULL SCREEN: reloaded; model=\(restored.isFullScreen)")
        let second = makeWindow(restored)
        try await waitFor("A fresh native window did not restore the saved full-screen state") {
            completedEntries.contains(ObjectIdentifier(second)) && second.styleMask.contains(.fullScreen) && restored.isFullScreen
        }
        print("NATIVE FULL SCREEN: restored a fresh native window")
        let finalExit = expectation(forNotification: NSWindow.didExitFullScreenNotification, object: second)
        second.toggleFullScreen(nil)
        await fulfillment(of: [finalExit], timeout: 12)
    }
}
#endif
