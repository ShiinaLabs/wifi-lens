import Foundation
import WiFiLensCoreRust

enum WiFiQualityEvaluator {
    static func evaluate(
        currentStatus: WiFiCurrentStatus,
        gatewayLatency: GatewayLatencyResult? = nil
    ) -> WiFiQualityResult {
        guard WiFiLinkEvidenceValidator.assessment(for: currentStatus)?.state == .associated,
            currentStatus.metricsAttribution == .verified,
            let rssi = currentStatus.rssi
        else {
            return unknownResult
        }

        let validLatency: Double?
        if case .replied(let latency) = WiFiGatewayEvidenceValidator.verdict(
            for: gatewayLatency,
            currentStatus: currentStatus
        ) {
            validLatency = latency
        } else {
            validLatency = nil
        }
        guard
            let assessment = ObservationAnalysisRustBridge.quality(
                eligible: true,
                rssi: rssi,
                latencyMs: validLatency
            )
        else {
            return unknownResult
        }

        let level: WiFiQualityLevel
        switch assessment.level {
        case WIFI_LENS_QUALITY_LEVEL_UNKNOWN: level = .unknown
        case WIFI_LENS_QUALITY_LEVEL_GOOD: level = .good
        case WIFI_LENS_QUALITY_LEVEL_FAIR: level = .fair
        case WIFI_LENS_QUALITY_LEVEL_POOR: level = .poor
        default:
            assertionFailure("Rust quality evaluator returned level code \(assessment.level)")
            return unknownResult
        }

        let signalLabel: String
        switch assessment.signal_band {
        case WIFI_LENS_SIGNAL_BAND_UNKNOWN:
            signalLabel = String(localized: "observation.quality.unknown", comment: "Unknown signal label")
        case WIFI_LENS_SIGNAL_BAND_STRONG:
            signalLabel = String(localized: "observation.signal.strong", comment: "Strong signal")
        case WIFI_LENS_SIGNAL_BAND_GOOD:
            signalLabel = String(localized: "observation.signal.good", comment: "Good signal")
        case WIFI_LENS_SIGNAL_BAND_MODERATE:
            signalLabel = String(localized: "observation.signal.moderate", comment: "Moderate signal")
        case WIFI_LENS_SIGNAL_BAND_WEAK:
            signalLabel = String(localized: "observation.signal.weak", comment: "Weak signal")
        default:
            assertionFailure("Rust quality evaluator returned signal band code \(assessment.signal_band)")
            return unknownResult
        }
        let latencyLabel: String
        switch assessment.latency_band {
        case WIFI_LENS_LATENCY_BAND_UNAVAILABLE:
            latencyLabel = String(localized: "observation.latency.unavailable", comment: "Latency unavailable")
        case WIFI_LENS_LATENCY_BAND_NORMAL:
            latencyLabel = String(localized: "observation.latency.normal", comment: "Normal latency")
        case WIFI_LENS_LATENCY_BAND_ELEVATED:
            latencyLabel = String(localized: "observation.latency.elevated", comment: "Elevated latency")
        case WIFI_LENS_LATENCY_BAND_HIGH:
            latencyLabel = String(localized: "observation.latency.high", comment: "High latency")
        default:
            assertionFailure("Rust quality evaluator returned latency band code \(assessment.latency_band)")
            return unknownResult
        }
        let summary =
            switch level {
            case .good:
                String(localized: "observation.summary.good", comment: "Good connection summary")
            case .fair:
                String(localized: "observation.summary.fair", comment: "Fair connection summary")
            case .poor:
                String(localized: "observation.summary.poor", comment: "Poor connection summary")
            case .unknown:
                String(localized: "observation.summary.unknown", comment: "Unknown connection summary")
            }
        return WiFiQualityResult(
            level: level,
            signalLabel: signalLabel,
            latencyLabel: latencyLabel,
            summary: summary
        )
    }

    private static var unknownResult: WiFiQualityResult {
        WiFiQualityResult(
            level: .unknown,
            signalLabel: String(localized: "observation.quality.unknown", comment: "Unknown signal label"),
            latencyLabel: String(localized: "observation.latency.unavailable", comment: "Latency unavailable"),
            summary: String(localized: "observation.summary.unknown", comment: "Unknown connection summary")
        )
    }
}

enum ObservationAnalysisRustBridge {
    static func quality(eligible: Bool, rssi: Int?, latencyMs: Double?) -> WiFiLensQualityResult? {
        var flags: UInt32 = 0
        if eligible { flags |= WIFI_LENS_QUALITY_ELIGIBLE }
        if rssi != nil { flags |= WIFI_LENS_QUALITY_HAS_RSSI }
        if latencyMs != nil { flags |= WIFI_LENS_QUALITY_HAS_LATENCY }
        let input = WiFiLensQualityInput(
            flags: flags,
            rssi: Int64(rssi ?? 0),
            latency_ms: latencyMs ?? 0
        )
        var output = WiFiLensQualityResult()
        let status = withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                wifi_lens_evaluate_quality(inputPointer, outputPointer)
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust quality evaluation returned status \(status)")
            return nil
        }
        return output
    }

    static func diagnosis(
        associated: Bool,
        metricsVerified: Bool,
        rssi: Int?,
        channelQualityScore: Int?,
        security: String?,
        phyMode: String?
    ) -> WiFiLensDiagnosticResult? {
        var flags: UInt32 = 0
        if associated { flags |= WIFI_LENS_DIAGNOSTIC_ASSOCIATED }
        if metricsVerified { flags |= WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED }
        var rssiValue: Int64 = 0
        var channelScoreValue: Int32 = 0
        var phyCode = WIFI_LENS_PHY_OTHER
        if metricsVerified {
            if let rssi {
                flags |= WIFI_LENS_DIAGNOSTIC_HAS_RSSI
                rssiValue = Int64(rssi)
            }
            if let channelQualityScore {
                flags |= WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE
                channelScoreValue = Int32(channelQualityScore)
            }
            if let security, !security.isEmpty, security != "—" {
                flags |= WIFI_LENS_DIAGNOSTIC_SECURITY_KNOWN
                if security.contains("WPA3") {
                    flags |= WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3
                }
            }
            phyCode =
                switch phyMode {
                case "802.11n": WIFI_LENS_PHY_11N
                case "802.11ac": WIFI_LENS_PHY_11AC
                default: WIFI_LENS_PHY_OTHER
                }
        }
        let input = WiFiLensDiagnosticInput(
            flags: flags,
            rssi: rssiValue,
            channel_quality_score: channelScoreValue,
            phy_generation: phyCode
        )
        var output = WiFiLensDiagnosticResult()
        let status = withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                wifi_lens_evaluate_diagnosis(inputPointer, outputPointer)
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust diagnosis evaluation returned status \(status)")
            return nil
        }
        return output
    }
}
