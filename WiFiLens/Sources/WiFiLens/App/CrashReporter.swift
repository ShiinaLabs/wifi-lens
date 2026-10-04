import Foundation
import WiFiLensCore

/// Lightweight crash reporter — writes stack traces to disk for review on the next launch.
enum CrashReporter {
    private static let logDir: URL = {
        let dir = StorageLocations.current.crashLogs
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func consumeCrashLog() -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil) else { return nil }
        let crashFiles = files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "log" }
        guard !crashFiles.isEmpty else { return nil }

        var all: [String] = []
        for url in crashFiles {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8), !text.isEmpty {
                all.append(text)
            }
            try? FileManager.default.removeItem(at: url)
        }
        return all.isEmpty ? nil : all.joined(separator: "\n---\n")
    }

    static func register() {
        NSSetUncaughtExceptionHandler(exceptionHandler)
        signal(SIGILL,  crashHandler)
        signal(SIGTRAP, crashHandler)
        signal(SIGABRT, crashHandler)
        signal(SIGBUS,  crashHandler)
        signal(SIGSEGV, crashHandler)
    }

    fileprivate static func write(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let safeName = ts.replacingOccurrences(of: ":", with: "-")
        let entry = "[\(ts)] \(message)\n"
        let url = logDir.appendingPathComponent("crash-\(safeName).log")
        try? entry.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

// MARK: - C function pointers (must not capture context)

private func crashHandler(_ sig: Int32) {
    let name = switch sig {
    case SIGILL:  "SIGILL"
    case SIGTRAP: "SIGTRAP"
    case SIGABRT: "SIGABRT"
    case SIGBUS:  "SIGBUS"
    case SIGSEGV: "SIGSEGV"
    default:      "SIGNAL(\(sig))"
    }
    let trace = Thread.callStackSymbols.joined(separator: "\n")
    CrashReporter.write("Signal \(name):\n\(trace)")
    signal(sig, SIG_DFL)
    kill(getpid(), sig)
}

private func exceptionHandler(_ exception: NSException) {
    let trace = exception.callStackSymbols.joined(separator: "\n")
    let msg = "NSException: \(exception.name.rawValue)\n\(exception.reason ?? "")\n\(trace)"
    CrashReporter.write(msg)
}
