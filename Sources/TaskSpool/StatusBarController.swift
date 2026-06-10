import AppKit
import SwiftUI

struct StatusBarInstaller: View {
    @Environment(\.openWindow) private var openWindow
    let store: TaskStore

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                StatusBarController.shared.install(store: store) {
                    AppWindowController.showMainWindow {
                        openWindow(id: "main")
                    }
                }
            }
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private weak var store: TaskStore?
    private var showManager: (() -> Void)?

    func install(store: TaskStore, showManager: @escaping () -> Void) {
        self.store = store
        self.showManager = showManager

        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton(item.button)

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func configureButton(_ button: NSStatusBarButton?) {
        guard let button else {
            return
        }

        button.toolTip = "TaskSpool"

        if let image = Self.loadStatusImage() {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = "TS"
            button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        }
    }

    private static func loadStatusImage() -> NSImage? {
        if let resourceURL = Bundle.main.url(forResource: "status-icon", withExtension: "png", subdirectory: "Brand") {
            return NSImage(contentsOf: resourceURL)
        }

        let developmentPath = FileManager.default.currentDirectoryPath
            + "/Resources/Brand/status-icon.png"
        return NSImage(contentsOfFile: developmentPath)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let showItem = NSMenuItem(
            title: "Show Manager",
            action: #selector(showManagerAction(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let hideItem = NSMenuItem(
            title: "Hide Window",
            action: #selector(hideWindowAction(_:)),
            keyEquivalent: ""
        )
        hideItem.target = self
        menu.addItem(hideItem)
        menu.addItem(.separator())

        guard let store else {
            menu.addItem(NSMenuItem(title: "Not ready", action: nil, keyEquivalent: ""))
            return
        }

        if store.tasks.isEmpty {
            menu.addItem(NSMenuItem(title: "No tasks", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(
                title: "\(store.runningCount) running, \(store.tasks.count) total",
                action: nil,
                keyEquivalent: ""
            ))
            menu.addItem(.separator())

            for task in store.tasks.prefix(8) {
                let item = NSMenuItem(title: task.displayName, action: nil, keyEquivalent: "")
                let submenu = NSMenu()

                submenu.addItem(NSMenuItem(title: task.state.title, action: nil, keyEquivalent: ""))
                submenu.addItem(.separator())
                submenu.addItem(taskMenuItem(title: "Restart", action: #selector(restartTaskAction(_:)), task: task))

                let killItem = taskMenuItem(title: "Kill", action: #selector(killTaskAction(_:)), task: task)
                killItem.isEnabled = task.state.isActive
                submenu.addItem(killItem)

                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let killAllItem = NSMenuItem(
            title: "Kill All",
            action: #selector(killAllAction(_:)),
            keyEquivalent: ""
        )
        killAllItem.target = self
        killAllItem.isEnabled = store.runningCount > 0
        menu.addItem(killAllItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func taskMenuItem(title: String, action: Selector, task: ShellTask) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = task
        return item
    }

    @objc private func showManagerAction(_ sender: NSMenuItem) {
        showManager?()
    }

    @objc private func hideWindowAction(_ sender: NSMenuItem) {
        AppWindowController.hideToMenuBar()
    }

    @objc private func restartTaskAction(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? ShellTask else {
            return
        }
        task.restart()
    }

    @objc private func killTaskAction(_ sender: NSMenuItem) {
        guard let task = sender.representedObject as? ShellTask else {
            return
        }
        task.stop()
    }

    @objc private func killAllAction(_ sender: NSMenuItem) {
        store?.stopAll()
    }

    @objc private func quitAction(_ sender: NSMenuItem) {
        store?.killAllNow()
        NSApplication.shared.terminate(nil)
    }
}
