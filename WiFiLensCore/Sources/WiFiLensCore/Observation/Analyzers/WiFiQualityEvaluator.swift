import Foundation

enum WiFiQualityEvaluator {
    static func evaluate(
        currentStatus: WiFiCurrentStatus,
        gatewayLatency: GatewayLatencyResult? = nil
    ) -> WiFiQualityResult {
        let rssi = currentStatus.rssi ?? -100
        let level = evaluateLevel(rssi: rssi, latencyMs: gatewayLatency?.latencyMs)
        let signalLabel = Self.signalLabel(rssi: rssi)
        let latencyLabel = Self.latencyLabel(ms: gatewayLatency?.latencyMs)
        let summary = Self.summary(level: level, signalLabel: signalLabel, latencyLabel: latencyLabel)
        return WiFiQualityResult(level: level, signalLabel: signalLabel, latencyLabel: latencyLabel, summary: summary)
    }

    private static func evaluateLevel(rssi: Int, latencyMs: Double?) -> WiFiQualityLevel {
        if rssi >= -55 {
            if let ms = latencyMs, ms < 50 { return .good }
            if latencyMs == nil { return .good }
            return .fair
        }
        if rssi >= -70 {
            if let ms = latencyMs, ms < 100 { return .fair }
            return .poor
        }
        return .poor
    }

    private static func signalLabel(rssi: Int) -> String {
        if rssi >= -55 { return String(localized: "observation.signal.strong", comment: "Strong signal") }
        if rssi >= -70 { return String(localized: "observation.signal.good", comment: "Good signal") }
        if rssi >= -85 { return String(localized: "observation.signal.moderate", comment: "Moderate signal") }
        return String(localized: "observation.signal.weak", comment: "Weak signal")
    }

    private static func latencyLabel(ms: Double?) -> String {
        guard let ms else { return String(localized: "observation.latency.unavailable", comment: "Latency unavailable") }
        if ms < 50 { return String(localized: "observation.latency.normal", comment: "Normal latency") }
        if ms < 100 { return String(localized: "observation.latency.elevated", comment: "Elevated latency") }
        return String(localized: "observation.latency.high", comment: "High latency")
    }

    private static func summary(level: WiFiQualityLevel, signalLabel: String, latencyLabel: String) -> String {
        switch level {
        case .good:    return String(localized: "observation.summary.good", comment: "Good connection summary")
        case .fair:    return String(localized: "observation.summary.fair", comment: "Fair connection summary")
        case .poor:    return String(localized: "observation.summary.poor", comment: "Poor connection summary")
        case .unknown: return String(localized: "observation.summary.unknown", comment: "Unknown connection summary")
        }
    }
}
