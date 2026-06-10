import Foundation

@MainActor
final class ShellTask: ObservableObject, Identifiable {
    let id = UUID()
    let createdAt = Date()

    @Published var command: String
    @Published var workingDirectory: String
    @Published private(set) var state: ShellTaskState = .idle
    @Published private(set) var logs: [LogEntry] = []

    private var process: LaunchedShellProcess?
    private var activeRunID: UUID?
    private var restartRequested = false

    init(command: String, workingDirectory: String) {
        self.command = command
        self.workingDirectory = workingDirectory
    }

    var displayName: String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 54 {
            return trimmed
        }
        return String(trimmed.prefix(51)) + "..."
    }

    func start() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            state = .failed(message: "Command is empty")
            appendSystemLog("Command is empty.")
            return
        }

        guard !state.isActive else {
            appendSystemLog("Task is already running.")
            return
        }

        let runID = UUID()
        activeRunID = runID
        restartRequested = false

        do {
            appendSystemLog("Starting: \(trimmedCommand)")
            let launchedProcess = try ShellLauncher.launch(
                command: trimmedCommand,
                workingDirectory: workingDirectory,
                onStdout: { [weak self] data in
                    Task { @MainActor in
                        self?.appendOutput(data, stream: .stdout, runID: runID)
                    }
                },
                onStderr: { [weak self] data in
                    Task { @MainActor in
                        self?.appendOutput(data, stream: .stderr, runID: runID)
                    }
                },
                onTermination: { [weak self] termination in
                    Task { @MainActor in
                        self?.handleTermination(termination, runID: runID)
                    }
                }
            )
            process = launchedProcess
            state = .running(pid: launchedProcess.pid)
            appendSystemLog("Started with PID \(launchedProcess.pid).")
        } catch {
            process = nil
            activeRunID = nil
            state = .failed(message: error.localizedDescription)
            appendSystemLog(error.localizedDescription)
        }
    }

    func stop() {
        guard let process, let pid = state.pid else {
            appendSystemLog("Task is not running.")
            return
        }

        state = .stopping(pid: pid)
        appendSystemLog("Sending SIGTERM to process group \(pid).")
        process.terminateGroup()

        let runID = activeRunID
        Task { [weak self, weak process] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                guard
                    let self,
                    self.activeRunID == runID,
                    self.state.isActive,
                    let process,
                    !process.isCompleted
                else {
                    return
                }
                self.appendSystemLog("Process did not exit after SIGTERM; sending SIGKILL.")
                process.killGroup()
            }
        }
    }

    func forceKill() {
        guard let process, let pid = state.pid else {
            return
        }

        state = .stopping(pid: pid)
        appendSystemLog("Sending SIGKILL to process group \(pid).")
        process.killGroup()
    }

    func restart() {
        if state.isActive {
            restartRequested = true
            appendSystemLog("Restart requested.")
            stop()
        } else {
            appendSystemLog("Restarting.")
            start()
        }
    }

    func clearLogs() {
        logs.removeAll(keepingCapacity: true)
    }

    private func handleTermination(_ termination: ShellTermination, runID: UUID) {
        guard activeRunID == runID else {
            return
        }

        process = nil
        activeRunID = nil

        if let exitCode = termination.exitCode {
            state = .exited(code: exitCode)
            appendSystemLog("Process exited with code \(exitCode).")
        } else if let signal = termination.signal {
            state = .signaled(signal: signal)
            appendSystemLog("Process terminated by signal \(signal).")
        } else {
            state = .failed(message: "Process ended with unknown status \(termination.rawStatus)")
            appendSystemLog("Process ended with unknown status \(termination.rawStatus).")
        }

        if restartRequested {
            restartRequested = false
            start()
        }
    }

    private func appendOutput(_ data: Data, stream: TaskOutputStream, runID: UUID) {
        guard activeRunID == runID else {
            return
        }

        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        appendLog(text, stream: stream)
    }

    private func appendSystemLog(_ text: String) {
        appendLog(text + "\n", stream: .system)
    }

    private func appendLog(_ text: String, stream: TaskOutputStream) {
        logs.append(LogEntry(timestamp: Date(), stream: stream, text: text))
        if logs.count > 4_000 {
            logs.removeFirst(logs.count - 4_000)
        }
    }
}
