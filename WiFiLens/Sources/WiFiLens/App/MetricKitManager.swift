import Foundation
import MetricKit
import WiFiLensCore

/// Receives MetricKit payloads and persists them to disk for debugging
/// and performance analysis. Modeled after CrashReporter — lightweight,
/// self-contained, registered once at app launch.
///
/// Payloads are stored as JSON in the runtime's canonical application-support namespace.
final class MetricKitManager: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitManager()

    private override init() {}

    // MARK: - Directory

    private static let metricsDir: URL = {
        let dir = StorageLocations.current.metrics
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

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

    private static func save(_ data: Data, prefix: String) {
        let safe = prefix.replacingOccurrences(of: ":", with: "-")
        let url = metricsDir.appendingPathComponent("\(safe).json")
        try? data.write(to: url, options: .atomic)
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
