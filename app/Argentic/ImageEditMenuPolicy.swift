#if os(macOS)
import AppKit

/// AppKit adds text services independently of SwiftUI's command groups. Keep only our image action.
@MainActor
final class ImageEditMenuPolicy {
    private var observers: [NSObjectProtocol] = []

    func install() {
        guard observers.isEmpty else { return }
        for name in [NSApplication.didUpdateNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Self.keepOnlyCopyImage(in: NSApp.mainMenu) }
            })
        }
        Self.keepOnlyCopyImage(in: NSApp.mainMenu)
    }

    static func keepOnlyCopyImage(in mainMenu: NSMenu?) {
        // Locate our command rather than relying on the system's localized "Edit" menu title.
        guard let edit = mainMenu?.items.compactMap(\.submenu).first(where: { menu in
            menu.items.contains(where: isCopyImageCommand)
        }) else { return }
        for item in edit.items where !isCopyImageCommand(item) {
            edit.removeItem(item)
        }
    }

    private static func isCopyImageCommand(_ item: NSMenuItem) -> Bool {
        item.title == "Copy Image" && item.keyEquivalent == "c" && item.keyEquivalentModifierMask.contains(.command)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
#endif
