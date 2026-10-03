import Foundation
import Logging
import OSLog
import AppKit

// MARK: - AppLogger

/// Unified logging facade. Call `AppLogger.bootstrap()` once at launch.
enum AppLogger {

    // MARK: Bootstrap

    static func bootstrap() {
        LoggingSystem.bootstrap { label in
            var handlers: [LogHandler] = []

            // Level policy:
            // - Debug builds: console is .trace, OSLog and file are .debug, so
            //   .debug diagnostics reach every sink and DebugConsoleLogPolicy
            //   is not defeated by the more restrictive OSLog/file levels.
            // - Release builds: OSLog and file stay at .info; the console
            //   handler is compiled out entirely, so behavior is unchanged.
            #if DEBUG
            var console = ConsoleLogHandler(label: label)
            console.logLevel = .trace
            handlers.append(console)
            #endif

            var os = OSLogHandler(label: label)
            #if DEBUG
            os.logLevel = .debug
            #else
            os.logLevel = .info
            #endif
            handlers.append(os)

            #if DEBUG
            var file = FileLogHandler(label: label)
            file.logLevel = .debug
            #else
            let file = FileLogHandler(label: label)
            #endif
            handlers.append(file)

            return MultiplexLogHandler(handlers)
        }
    }

    // MARK: Categories

    static let general    = Logging.Logger(label: "general")
    static let scanner    = Logging.Logger(label: "scanner")
    static let network    = Logging.Logger(label: "network")
    static let ui         = Logging.Logger(label: "ui")
#if OSS
    static let sparkle    = Logging.Logger(label: "sparkle")
#endif
    static let mcp        = Logging.Logger(label: "mcp")
    static let throughput = Logging.Logger(label: "throughput")
    static let location   = Logging.Logger(label: "location")
    static let ble        = Logging.Logger(label: "ble")
    static let guidance   = Logging.Logger(label: "guidance")
    static let apRadar    = Logging.Logger(label: "apRadar")

    /// Backward-compatible alias for `AppLogger.app` call sites.
    static let app = general

    // MARK: Log directory

    static var logDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WiFi Lens")
            .appendingPathComponent("Logs")
    }

    /// Opens the log directory in Finder.
    static func revealInFinder() {
        let dir = logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Deletes app log files and persisted MetricKit payloads.
    static func clearLogs() {
        clearLogs(logWriter: .shared, clearMetricKitPayloads: { MetricKitManager.clearPayloads() })
    }

    static func clearLogs(
        logWriter: LogFileWriter,
        clearMetricKitPayloads: () -> Void
    ) {
        logWriter.clear()
        clearMetricKitPayloads()
    }
}

// MARK: - ConsoleLogHandler

enum DebugConsoleLogPolicy {
    static func shouldWrite(_ level: Logging.Logger.Level) -> Bool {
        switch level {
        case .trace, .debug, .warning, .error, .critical:
            true
        case .info, .notice:
            false
        }
    }
}

/// Writes to stdout with timestamps. Debug builds only.
private struct ConsoleLogHandler: LogHandler {
    let label: String
    var logLevel: Logging.Logger.Level = .trace
    var metadata = Logging.Logger.Metadata()

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        guard DebugConsoleLogPolicy.shouldWrite(event.level) else { return }
        let ts = _timestampFormatter.string(from: Date())
        print("\(ts) [\(event.level.short)] [\(label)] \(event.message)")
    }
}

// MARK: - OSLogHandler

/// Writes to Apple Unified Logging (Console.app).
private struct OSLogHandler: LogHandler {
    let label: String
    var logLevel: Logging.Logger.Level = .info
    var metadata = Logging.Logger.Metadata()

    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.kaoru.wifi-lens"

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let logger = os.Logger(subsystem: Self.subsystem, category: label)
        switch event.level {
        case .trace:    logger.trace("\(event.message)")
        case .debug:    logger.debug("\(event.message)")
        case .info:     logger.info("\(event.message)")
        case .notice:   logger.notice("\(event.message)")
        case .warning:  logger.warning("\(event.message)")
        case .error:    logger.error("\(event.message)")
        case .critical: logger.fault("\(event.message)")
        }
    }
}

// MARK: - FileLogHandler

/// Writes to rotating log files via a serial background queue.
private struct FileLogHandler: LogHandler {
    let label: String
    var logLevel: Logging.Logger.Level = .info
    var metadata = Logging.Logger.Metadata()

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let line = _fileLineFormatter.string(from: Date())
            .appending(" [\(event.level.short)] [\(label)] \(event.message)\n")
        LogFileWriter.shared.enqueue(line)
    }
}

// MARK: - File Writer

final class LogFileWriter: @unchecked Sendable {
    static let shared = LogFileWriter(logDirectory: AppLogger.logDirectory)

    private let logDirectory: URL
    private let queue = DispatchQueue(label: "com.wifilens.logwriter", qos: .utility)
    private let maxSize: Int64 = 5 * 1024 * 1024
    private let maxFiles = 7

    private var handle: FileHandle?
    private var currentSize: Int64 = 0

    init(logDirectory: URL) {
        self.logDirectory = logDirectory
    }

    func enqueue(_ line: String) {
        queue.async { [weak self] in
            self?.write(line)
        }
    }

    /// Clears logs on the writer queue so the active file handle is reset
    /// before any queued write can follow an unlinked inode.
    func clear() {
        queue.sync {
            handle?.closeFile()
            handle = nil
            currentSize = 0

            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(
                at: logDirectory, includingPropertiesForKeys: nil
            ) {
                for item in contents {
                    try? fileManager.removeItem(at: item)
                }
            }

            open()
        }
    }

    func waitForPendingWritesForTesting() {
        queue.sync {}
    }

    private func open() {
        let dir = logDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("wifi-lens.log").path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        currentSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        handle = FileHandle(forUpdatingAtPath: path)
        handle?.seekToEndOfFile()
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if handle == nil { open() }
        if currentSize + Int64(data.count) > maxSize { rotate() }
        do {
            try handle?.write(contentsOf: data)
            currentSize += Int64(data.count)
        } catch {
            open()
            try? handle?.write(contentsOf: data)
            currentSize = Int64(data.count)
        }
    }

    private func rotate() {
        handle?.closeFile()
        let dir = logDirectory
        let base = dir.appendingPathComponent("wifi-lens")

        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let old = base.appendingPathExtension("\(i).log")
            let next = base.appendingPathExtension("\(i + 1).log")
            try? FileManager.default.removeItem(at: next)
            try? FileManager.default.moveItem(at: old, to: next)
        }
        try? FileManager.default.moveItem(at: base.appendingPathExtension("log"),
                                           to: base.appendingPathExtension("1.log"))
        try? FileManager.default.removeItem(at: base.appendingPathExtension("\(maxFiles + 1).log"))

        let current = base.appendingPathExtension("log")
        FileManager.default.createFile(atPath: current.path, contents: nil)
        handle = try? FileHandle(forWritingTo: current)
        currentSize = 0
    }
}

// MARK: - Formatters

private let _timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private let _fileLineFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

// MARK: - Level Short Descriptions

private extension Logging.Logger.Level {
    var short: String {
        switch self {
        case .trace:    "TRC"
        case .debug:    "DBG"
        case .info:     "INF"
        case .notice:   "NTC"
        case .warning:  "WRN"
        case .error:    "ERR"
        case .critical: "CRT"
        }
    }
}
