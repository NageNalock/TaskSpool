import Darwin
import Foundation

enum ShellLauncherError: LocalizedError {
    case invalidWorkingDirectory(String)
    case pipeSetupFailed(String)
    case spawnFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkingDirectory(let path):
            return "Working directory does not exist: \(path)"
        case .pipeSetupFailed(let message):
            return "Unable to prepare output pipes: \(message)"
        case .spawnFailed(let code, let message):
            return "Unable to start process (\(code)): \(message)"
        }
    }
}

final class LaunchedShellProcess {
    let pid: pid_t

    private let stdoutReadHandle: FileHandle
    private let stderrReadHandle: FileHandle
    private let waitQueue = DispatchQueue(label: "taskspool.process-wait")
    private let lifecycleLock = NSLock()
    private var completed = false

    init(
        pid: pid_t,
        stdoutReadHandle: FileHandle,
        stderrReadHandle: FileHandle,
        onStdout: @escaping (Data) -> Void,
        onStderr: @escaping (Data) -> Void,
        onTermination: @escaping (ShellTermination) -> Void
    ) {
        self.pid = pid
        self.stdoutReadHandle = stdoutReadHandle
        self.stderrReadHandle = stderrReadHandle

        stdoutReadHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onStdout(data)
            }
        }

        stderrReadHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onStderr(data)
            }
        }

        waitQueue.async { [weak self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 {
                if errno != EINTR {
                    status = errno << 8
                    break
                }
            }
            self?.markCompleted()
            onTermination(ShellTermination(rawStatus: status))
        }
    }

    func terminateGroup() {
        signalGroup(SIGTERM)
    }

    func killGroup() {
        signalGroup(SIGKILL)
    }

    var isCompleted: Bool {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return completed
    }

    private func markCompleted() {
        lifecycleLock.lock()
        completed = true
        lifecycleLock.unlock()

        stdoutReadHandle.readabilityHandler = nil
        stderrReadHandle.readabilityHandler = nil
        try? stdoutReadHandle.close()
        try? stderrReadHandle.close()
    }

    private func signalGroup(_ signal: Int32) {
        let groupResult = Darwin.kill(-pid, signal)
        if groupResult == -1 && errno == ESRCH {
            return
        }

        if groupResult == -1 {
            _ = Darwin.kill(pid, signal)
        }
    }
}

enum ShellLauncher {
    static func launch(
        command: String,
        workingDirectory: String?,
        onStdout: @escaping (Data) -> Void,
        onStderr: @escaping (Data) -> Void,
        onTermination: @escaping (ShellTermination) -> Void
    ) throws -> LaunchedShellProcess {
        let normalizedDirectory = normalizeWorkingDirectory(workingDirectory)
        if let normalizedDirectory, !FileManager.default.fileExists(atPath: normalizedDirectory) {
            throw ShellLauncherError.invalidWorkingDirectory(normalizedDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw ShellLauncherError.pipeSetupFailed(String(cString: strerror(errno)))
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        posix_spawn_file_actions_adddup2(
            &fileActions,
            stdoutPipe.fileHandleForWriting.fileDescriptor,
            STDOUT_FILENO
        )
        posix_spawn_file_actions_adddup2(
            &fileActions,
            stderrPipe.fileHandleForWriting.fileDescriptor,
            STDERR_FILENO
        )

        if let normalizedDirectory {
            let chdirResult = normalizedDirectory.withCString { directoryPointer in
                posix_spawn_file_actions_addchdir_np(&fileActions, directoryPointer)
            }
            if chdirResult != 0 {
                throw ShellLauncherError.invalidWorkingDirectory(normalizedDirectory)
            }
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawnattr_destroy(&attributes)
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        posix_spawnattr_setflags(&attributes, flags)
        posix_spawnattr_setpgroup(&attributes, 0)

        let shellPath = "/bin/zsh"
        let argumentStrings = [shellPath, "-lc", command]
        var arguments: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) }
        arguments.append(nil)
        defer {
            arguments.forEach { pointer in
                if let pointer {
                    free(UnsafeMutableRawPointer(pointer))
                }
            }
        }

        let environmentStrings = mergedEnvironment()
            .map { key, value in "\(key)=\(value)" }
        var environment: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) }
        environment.append(nil)
        defer {
            environment.forEach { pointer in
                if let pointer {
                    free(UnsafeMutableRawPointer(pointer))
                }
            }
        }

        var pid: pid_t = 0
        let spawnResult = shellPath.withCString { shellPointer in
            arguments.withUnsafeMutableBufferPointer { argumentBuffer in
                environment.withUnsafeMutableBufferPointer { environmentBuffer in
                    posix_spawn(
                        &pid,
                        shellPointer,
                        &fileActions,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }

        stdoutPipe.fileHandleForWriting.closeFile()
        stderrPipe.fileHandleForWriting.closeFile()

        guard spawnResult == 0 else {
            throw ShellLauncherError.spawnFailed(
                code: spawnResult,
                message: String(cString: strerror(spawnResult))
            )
        }

        return LaunchedShellProcess(
            pid: pid,
            stdoutReadHandle: stdoutPipe.fileHandleForReading,
            stderrReadHandle: stderrPipe.fileHandleForReading,
            onStdout: onStdout,
            onStderr: onStderr,
            onTermination: onTermination
        )
    }

    private static func normalizeWorkingDirectory(_ path: String?) -> String? {
        guard let path else {
            return nil
        }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }

        if trimmed.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + String(trimmed.dropFirst())
        }

        return NSString(string: trimmed).expandingTildeInPath
    }

    private static func mergedEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            let pathParts = currentPath.split(separator: ":").map(String.init)
            let missingParts = fallbackPath
                .split(separator: ":")
                .map(String.init)
                .filter { !pathParts.contains($0) }
            environment["PATH"] = ([currentPath] + missingParts).joined(separator: ":")
        } else {
            environment["PATH"] = fallbackPath
        }

        environment["SHELL"] = "/bin/zsh"
        return environment
    }
}
