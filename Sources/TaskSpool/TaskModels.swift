import Foundation
import SwiftUI

enum TaskOutputStream: String {
    case stdout = "STDOUT"
    case stderr = "STDERR"
    case system = "SYSTEM"

    var color: Color {
        switch self {
        case .stdout:
            return .primary
        case .stderr:
            return .red
        case .system:
            return .secondary
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: TaskOutputStream
    let text: String
}

enum ShellTaskState: Equatable {
    case idle
    case running(pid: pid_t)
    case stopping(pid: pid_t)
    case exited(code: Int32)
    case signaled(signal: Int32)
    case failed(message: String)

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .running(let pid):
            return "Running #\(pid)"
        case .stopping(let pid):
            return "Stopping #\(pid)"
        case .exited(let code):
            return "Exited \(code)"
        case .signaled(let signal):
            return "Killed SIG\(signal)"
        case .failed:
            return "Failed"
        }
    }

    var isActive: Bool {
        switch self {
        case .running, .stopping:
            return true
        case .idle, .exited, .signaled, .failed:
            return false
        }
    }

    var pid: pid_t? {
        switch self {
        case .running(let pid), .stopping(let pid):
            return pid
        case .idle, .exited, .signaled, .failed:
            return nil
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .green
        case .stopping:
            return .orange
        case .exited(let code):
            return code == 0 ? .secondary : .red
        case .signaled:
            return .orange
        case .failed:
            return .red
        }
    }
}

struct ShellTermination: Equatable {
    let rawStatus: Int32

    var exitCode: Int32? {
        if rawStatus & 0x7f == 0 {
            return (rawStatus >> 8) & 0xff
        }
        return nil
    }

    var signal: Int32? {
        let signal = rawStatus & 0x7f
        return signal == 0 ? nil : signal
    }
}
