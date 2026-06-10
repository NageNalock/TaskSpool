import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [ShellTask] = []

    var runningCount: Int {
        tasks.filter { $0.state.isActive }.count
    }

    func addTask(command: String, workingDirectory: String) -> ShellTask {
        let task = ShellTask(command: command, workingDirectory: workingDirectory)
        tasks.insert(task, at: 0)
        task.start()
        return task
    }

    func task(id: ShellTask.ID?) -> ShellTask? {
        guard let id else {
            return tasks.first
        }
        return tasks.first { $0.id == id } ?? tasks.first
    }

    func remove(_ task: ShellTask) {
        if task.state.isActive {
            task.forceKill()
        }
        tasks.removeAll { $0.id == task.id }
    }

    func stopAll() {
        tasks.forEach { task in
            if task.state.isActive {
                task.stop()
            }
        }
    }

    func killAllNow() {
        tasks.forEach { task in
            if task.state.isActive {
                task.forceKill()
            }
        }
    }
}
