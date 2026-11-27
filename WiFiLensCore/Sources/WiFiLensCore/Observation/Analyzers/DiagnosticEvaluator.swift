import Foundation
import WiFiLensCoreRust

enum DiagnosticEvaluator {
    static func evaluate(
        currentStatus: WiFiCurrentStatus,
        channelAnalysis: [ChannelQuality]? = nil,
        channelRecommendations: [ChannelRecommendation]? = nil
    ) -> DiagnosticResult {
        let associated = WiFiLinkEvidenceValidator.assessment(for: currentStatus)?.state == .associated
        guard associated else { return .unknown }

        let metricsVerified = currentStatus.metricsAttribution == .verified
        let currentChannel = channelAnalysis?.first(where: { $0.isCurrentChannel })
        let channelScore = metricsVerified ? currentChannel?.qualityScore : nil
        let accessPointCount = metricsVerified ? currentChannel?.apCount ?? 0 : 0
        let security = metricsVerified ? currentStatus.security ?? "" : ""
        guard
            let assessment = ObservationAnalysisRustBridge.diagnosis(
                associated: associated,
                metricsVerified: metricsVerified,
                rssi: currentStatus.rssi,
                channelQualityScore: channelScore,
                security: security,
                phyMode: currentStatus.phyMode
            )
        else {
            return .unknown
        }

        switch assessment.kind {
        case WIFI_LENS_DIAGNOSTIC_EXCELLENT:
            return DiagnosticResult(
                icon: "star.fill",
                title: String(localized: "observation.diagnosis.excellent.title", comment: "Excellent connection"),
                message: String(
                    localized: "observation.diagnosis.excellent.message", comment: "Excellent connection message"),
                severity: .excellent
            )
        case WIFI_LENS_DIAGNOSTIC_WEAK_SIGNAL:
            return DiagnosticResult(
                icon: "wifi.slash",
                title: String(localized: "observation.diagnosis.weak_signal.title", comment: "Weak signal"),
                message: String(localized: "observation.diagnosis.weak_signal.message", comment: "Weak signal advice"),
                severity: .critical
            )
        case WIFI_LENS_DIAGNOSTIC_CONGESTED:
            let channelNumber = currentStatus.channel ?? 0
            let recommendationList =
                channelRecommendations?.prefix(2).map { "\($0.channel)" }
                .joined(separator: " / ") ?? ""
            return DiagnosticResult(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "observation.diagnosis.congested.title", comment: "Congested channel"),
                message: String(
                    format: String(
                        localized: "observation.diagnosis.congested.message_fmt",
                        comment: "Congested channel with details"),
                    channelNumber,
                    accessPointCount,
                    recommendationList
                ),
                severity: .warning
            )
        case WIFI_LENS_DIAGNOSTIC_MEDIOCRE:
            return DiagnosticResult(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "observation.diagnosis.mediocre.title", comment: "Mediocre channel"),
                message: String(
                    localized: "observation.diagnosis.mediocre.message", comment: "Mediocre channel advice"),
                severity: .warning
            )
        case WIFI_LENS_DIAGNOSTIC_WEAK_SECURITY:
            return DiagnosticResult(
                icon: "lock.open.fill",
                title: String(localized: "observation.diagnosis.security.title", comment: "Weak security"),
                message: String(
                    format: String(
                        localized: "observation.diagnosis.security.message_fmt",
                        comment: "Security advice with type"),
                    security
                ),
                severity: .warning
            )
        case WIFI_LENS_DIAGNOSTIC_OLD_PHY_11N, WIFI_LENS_DIAGNOSTIC_OLD_PHY_11AC:
            let version = assessment.kind == WIFI_LENS_DIAGNOSTIC_OLD_PHY_11N ? "4" : "5"
            return DiagnosticResult(
                icon: "speedometer",
                title: String(localized: "observation.diagnosis.old_phy.title", comment: "Older Wi-Fi generation"),
                message: String(
                    format: String(
                        localized: "observation.diagnosis.old_phy.message_fmt", comment: "PHY upgrade advice"),
                    version
                ),
                severity: .warning
            )
        case WIFI_LENS_DIAGNOSTIC_OK:
            return DiagnosticResult(
                icon: "checkmark.circle.fill",
                title: String(localized: "observation.diagnosis.ok.title", comment: "Acceptable connection"),
                message: String(localized: "observation.diagnosis.ok.message", comment: "General advice"),
                severity: .ok
            )
        case WIFI_LENS_DIAGNOSTIC_UNKNOWN:
            return .unknown
        default:
            assertionFailure("Rust diagnosis evaluator returned kind code \(assessment.kind)")
            return .unknown
        }
    }
}
