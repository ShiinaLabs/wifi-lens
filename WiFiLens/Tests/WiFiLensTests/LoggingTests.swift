import Foundation
import Testing
@testable import WiFi_Lens

@Suite @MainActor struct LogFileWriterTests {
    @Test("clear removes rotated logs and reopens the active log")
    func clearRemovesRotatedLogsAndReopensActiveLog() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("wifi-lens-logging-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let rotatedLog = directory.appendingPathComponent("wifi-lens.1.log")
        try Data("rotated\n".utf8).write(to: rotatedLog)

        let writer = LogFileWriter(logDirectory: directory)
        writer.enqueue("before clear\n")
        writer.clear()

        let activeLog = directory.appendingPathComponent("wifi-lens.log")
        let clearedLog = try String(contentsOf: activeLog, encoding: .utf8)
        #expect(!fileManager.fileExists(atPath: rotatedLog.path))
        #expect(!clearedLog.contains("before clear"))

        writer.enqueue("after clear\n")
        writer.waitForPendingWritesForTesting()
        let reopenedLog = try String(contentsOf: activeLog, encoding: .utf8)
        #expect(reopenedLog.contains("after clear"))
    }

    @Test("clear removes persisted MetricKit payloads")
    func clearRemovesMetricKitPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifi-lens-metrics-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MetricKitPayloadStore(directory: directory)
        store.save(Data("metrics".utf8), filename: "metrics-sample.json")
        store.save(Data("diagnostics".utf8), filename: "diagnostics-sample.json")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)

        store.clear()

        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Clear Logs clears log and MetricKit stores together")
    func clearLogsClearsBothDiagnosticStores() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wifi-lens-clear-logs-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let logsDirectory = root.appendingPathComponent("Logs", isDirectory: true)
        let metricsDirectory = root.appendingPathComponent("Metrics", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let writer = LogFileWriter(logDirectory: logsDirectory)
        try Data("rotated".utf8).write(to: logsDirectory.appendingPathComponent("wifi-lens.1.log"))

        let store = MetricKitPayloadStore(directory: metricsDirectory)
        store.save(Data("payload".utf8), filename: "metrics-sample.json")
        let unrelatedFile = root.appendingPathComponent("unrelated.txt")
        try Data("preserve".utf8).write(to: unrelatedFile)

        AppLogger.clearLogs(logWriter: writer, clearMetricKitPayloads: { store.clear() })

        let activeLog = try String(
            contentsOf: logsDirectory.appendingPathComponent("wifi-lens.log"),
            encoding: .utf8
        )
        #expect(activeLog.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: metricsDirectory.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
    }
}
