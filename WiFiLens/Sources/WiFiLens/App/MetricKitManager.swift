import Foundation
import MetricKit

/// Receives MetricKit payloads and persists them to disk for debugging
/// and performance analysis. Modeled after CrashReporter — lightweight,
/// self-contained, registered once at app launch.
///
/// Payloads are stored as JSON in:
/// ~/Library/Application Support/WiFi Lens/Metrics/
final class MetricKitManager: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitManager()
    private static let payloadStore = MetricKitPayloadStore(
        directory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WiFi Lens/Metrics")
    )

    private override init() {}

    // MARK: - Registration

    @MainActor static func start() {
        MXMetricManager.shared.add(shared)
        AppLogger.app.info("MetricKit subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Self.save(data, prefix: "metrics-\(ts)-\(payload.timeStampBegin.timeIntervalSince1970)")
            Self.logPayload(payload)
        }
    }

    /// Crash diagnostics delivered alongside metric payloads.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Self.save(data, prefix: "diagnostics-\(ts)-\(payload.timeStampBegin.timeIntervalSince1970)")
            let crashCount = payload.crashDiagnostics?.count ?? 0
            let hangCount = payload.hangDiagnostics?.count ?? 0
            AppLogger.app.warning("MetricKit diagnostics received — \(crashCount) crash, \(hangCount) hang entries")
        }
    }

    // MARK: - Helpers

    static func clearPayloads() {
        payloadStore.clear()
    }

    private static func save(_ data: Data, prefix: String) {
        let safe = prefix.replacingOccurrences(of: ":", with: "-")
        payloadStore.save(data, filename: "\(safe).json")
    }

    private static func logPayload(_ payload: MXMetricPayload) {
        let formatter = ByteCountFormatter()
        let peakMem = formatter.string(
            fromByteCount: Int64(payload.memoryMetrics?.peakMemoryUsage.value ?? 0)
        )
        AppLogger.app.info(
            "MetricKit payload received — peakMem=\(peakMem)"
        )
    }
}

struct MetricKitPayloadStore: Sendable {
    let directory: URL

    func save(_ data: Data, filename: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(filename), options: .atomic)
    }

    func clear() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
