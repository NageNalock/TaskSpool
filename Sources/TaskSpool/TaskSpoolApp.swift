import SwiftUI

@main
struct TaskSpoolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()

    var body: some Scene {
        Window("TaskSpool", id: "main") {
            ContentView()
                .environmentObject(store)
                .background(StatusBarInstaller(store: store))
                .frame(minWidth: 940, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit TaskSpool") {
                    store.killAllNow()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
