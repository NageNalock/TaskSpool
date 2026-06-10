import AppKit
import Foundation

enum AppWindowController {
    static func showMainWindow(openWindow: () -> Void) {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows
                .filter { $0.canBecomeKey }
                .last?
                .makeKeyAndOrderFront(nil)
        }
    }

    static func hideToMenuBar() {
        NSApplication.shared.windows.forEach { window in
            if window.canHide || window.canBecomeKey {
                window.orderOut(nil)
            }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
