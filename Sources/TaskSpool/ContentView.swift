import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var command = ""
    @State private var workingDirectory = FileManager.default.currentDirectoryPath
    @State private var selectedTaskID: ShellTask.ID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                NewTaskForm(
                    command: $command,
                    workingDirectory: $workingDirectory,
                    onStart: startTask
                )
                Divider()
                TaskListView(
                    tasks: store.tasks,
                    selectedTaskID: $selectedTaskID,
                    onRemove: store.remove
                )
            }
            .navigationSplitViewColumnWidth(min: 310, ideal: 360)
        } detail: {
            if let task = store.task(id: selectedTaskID) {
                TaskDetailView(task: task)
            } else {
                EmptyTaskView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    AppWindowController.hideToMenuBar()
                } label: {
                    Label("Hide to Menu Bar", systemImage: "menubar.rectangle")
                }
            }
        }
        .onAppear {
            if selectedTaskID == nil {
                selectedTaskID = store.tasks.first?.id
            }
        }
    }

    private func startTask() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let task = store.addTask(command: trimmed, workingDirectory: workingDirectory)
        selectedTaskID = task.id
        command = ""
    }
}

private struct NewTaskForm: View {
    @Binding var command: String
    @Binding var workingDirectory: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("python3 xxx", text: $command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(onStart)

            HStack(spacing: 8) {
                TextField("Working directory", text: $workingDirectory)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                Button(action: chooseDirectory) {
                    Label("Choose Folder", systemImage: "folder")
                }

                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
}

private struct TaskListView: View {
    let tasks: [ShellTask]
    @Binding var selectedTaskID: ShellTask.ID?
    let onRemove: (ShellTask) -> Void

    var body: some View {
        List(selection: $selectedTaskID) {
            ForEach(tasks) { task in
                TaskRowView(task: task)
                    .tag(task.id)
                    .contextMenu {
                        Button("Restart") {
                            task.restart()
                        }
                        Button("Kill") {
                            task.stop()
                        }
                        Divider()
                        Button("Remove") {
                            onRemove(task)
                        }
                    }
            }
        }
        .overlay {
            if tasks.isEmpty {
                EmptyTaskView()
            }
        }
    }
}

private struct TaskRowView: View {
    @ObservedObject var task: ShellTask

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(task.state.tint)
                    .frame(width: 8, height: 8)
                Text(task.displayName)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }

            HStack {
                Text(task.state.title)
                    .font(.caption)
                    .foregroundStyle(task.state.tint)
                Spacer()
                Text(task.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TaskDetailView: View {
    @ObservedObject var task: ShellTask

    var body: some View {
        VStack(spacing: 0) {
            TaskHeaderView(task: task)
            Divider()
            LogConsoleView(logs: task.logs)
        }
    }
}

private struct TaskHeaderView: View {
    @ObservedObject var task: ShellTask

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(task.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Label(task.state.title, systemImage: task.state.isActive ? "bolt.fill" : "circle")
                    .foregroundStyle(task.state.tint)
            }

            HStack(spacing: 8) {
                Button {
                    task.stop()
                } label: {
                    Label("Kill", systemImage: "stop.fill")
                }
                .disabled(!task.state.isActive)

                Button {
                    task.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }

                Button {
                    task.clearLogs()
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }

                Spacer()

                Text(task.workingDirectory.isEmpty ? "~" : task.workingDirectory)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

private struct LogConsoleView: View {
    let logs: [LogEntry]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logs) { entry in
                        LogLineView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logs.last?.id) { newValue in
                guard let newValue else {
                    return
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .bottom)
                }
            }
        }
    }
}

private struct LogLineView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp, style: .time)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(entry.stream.rawValue)
                .foregroundStyle(entry.stream.color)
                .frame(width: 54, alignment: .leading)
            Text(entry.text)
                .foregroundStyle(entry.stream.color)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyTaskView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("No background task")
                .font(.headline)
            Text("Enter a shell command to start a managed process.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
