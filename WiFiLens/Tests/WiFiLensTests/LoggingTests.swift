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
}
