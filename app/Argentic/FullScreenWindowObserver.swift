#if os(macOS)
import AppKit
import SwiftUI

extension Notification.Name {
    static let argenticWillTerminate = Notification.Name("ArgenticWillTerminate")
}

/// Install native menu policy and capture window state before AppKit tears down windows.
@MainActor
final class ApplicationLifecycle: NSObject, NSApplicationDelegate {
    private let editMenuPolicy = ImageEditMenuPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        editMenuPolicy.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NotificationCenter.default.post(name: .argenticWillTerminate, object: sender)
        return .terminateNow
    }
}

/// Uses the native full-screen action, including the green window button and macOS Spaces.
struct FullScreenWindowObserver: NSViewRepresentable {
    var model: FractalModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ view: WindowProbe, context: Context) {
        context.coordinator.attach(to: view.window)
    }

    static func dismantleNSView(_ view: WindowProbe, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class WindowProbe: NSView {
        var windowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChanged?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private let model: FractalModel
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var restored = false
        private var closing = false
        private var restoreFullScreen = false
        private var transitioning = false
        private var restoreQueued = false

        init(model: FractalModel) { self.model = model }

        func attach(to window: NSWindow?) {
            // SwiftUI can briefly remove the probe from its window during a native full-screen transition.
            // Keep tracking the original window until a replacement arrives or dismantleNSView is called.
            guard let window else { return }
            guard self.window !== window else { return }
            detach()
            self.window = window
            restored = false
            closing = false
            transitioning = false
            restoreQueued = false
            restoreFullScreen = model.isFullScreen
            // Our opt-in preference, not macOS's automatic restoration, owns this state.
            window.isRestorable = false
            window.tabbingMode = .disallowed
            model.fullScreenStateProvider = { [weak self] in self?.stateForSaving }

            observe(NSWindow.didBecomeKeyNotification, object: window) { [weak self] in self?.restoreIfVisible() }
            observe(NSWindow.didUpdateNotification, object: window) { [weak self] in self?.restoreIfVisible() }
            observe(NSWindow.didResizeNotification, object: window) { [weak self] in self?.captureState() }
            observe(NSWindow.didResignKeyNotification, object: window) { [weak self] in self?.captureState() }
            observe(NSWindow.willEnterFullScreenNotification, object: window) { [weak self] in self?.transitioning = true }
            observe(NSWindow.didEnterFullScreenNotification, object: window) { [weak self] in self?.finishedTransition(true) }
            observe(NSWindow.willExitFullScreenNotification, object: window) { [weak self] in self?.transitioning = true }
            observe(NSWindow.didExitFullScreenNotification, object: window) { [weak self] in self?.finishedTransition(false) }
            observe(.argenticWillTerminate, object: nil) { [weak self] in self?.prepareToClose() }
            observe(NSWindow.willCloseNotification, object: window) { [weak self] in
                self?.prepareToClose()
            }
            DispatchQueue.main.async { [weak self] in self?.restoreIfVisible() }
        }

        private func restoreIfVisible() {
            guard !restored, !closing, !transitioning, !restoreQueued,
                  let window, window.isVisible, window.isKeyWindow else { return }
            if window.styleMask.contains(.fullScreen) == restoreFullScreen {
                restored = true
                model.isFullScreen = restoreFullScreen
                return
            }
            // Key-window notifications arrive during window ordering/layout. Request native full screen
            // on the next turn, and retain the saved state until didEnter/didExit confirms completion.
            restoreQueued = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                self.restoreQueued = false
                guard !self.restored, !self.closing, !self.transitioning,
                      window.isVisible, window.isKeyWindow else { return }
                if window.styleMask.contains(.fullScreen) == self.restoreFullScreen {
                    self.restored = true
                    self.model.isFullScreen = self.restoreFullScreen
                } else {
                    window.toggleFullScreen(nil)
                }
            }
        }

        private var stateForSaving: Bool? {
            guard let window else { return nil }
            if closing || transitioning || !restored { return model.isFullScreen }
            return window.styleMask.contains(.fullScreen)
        }

        private func captureState() {
            guard restored, !closing, !transitioning, let state = stateForSaving else { return }
            model.isFullScreen = state
        }

        private func finishedTransition(_ fullScreen: Bool) {
            guard !closing else { return }
            transitioning = false
            restored = true
            model.isFullScreen = fullScreen
        }

        private func prepareToClose() {
            guard !closing else { return }
            let state = stateForSaving ?? model.isFullScreen
            closing = true
            model.isFullScreen = state
            model.saveSettings()
        }

        private func observe(_ name: Notification.Name, object: AnyObject?, action: @escaping @MainActor () -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            })
        }

        func detach() {
            captureState()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            window = nil
        }
    }
}
#endif
