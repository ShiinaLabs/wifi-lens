import SwiftUI

enum DiagnosticEvaluator {
    static func evaluate(
        currentStatus: WiFiCurrentStatus,
        quality: WiFiQualityResult? = nil,
        channelAnalysis: [ChannelQuality]? = nil,
        channelRecommendations: [ChannelRecommendation]? = nil
    ) -> DiagnosticResult {
        let associated = WiFiLinkEvidenceValidator.assessment(for: currentStatus)?.state == .associated
        guard associated else {
            return .unknown
        }
        let metricsVerified = currentStatus.metricsAttribution == .verified
        let rssi = metricsVerified ? currentStatus.rssi : nil
        let chScore = metricsVerified ? channelAnalysis?
            .first(where: { $0.isCurrentChannel })?
            .qualityScore : nil
        let apCount = metricsVerified ? channelAnalysis?
            .first(where: { $0.isCurrentChannel })?
            .apCount ?? 0 : 0
        let sec = metricsVerified ? currentStatus.security ?? "" : ""
        let phy = metricsVerified ? currentStatus.phyMode ?? "" : ""

        guard rssi != nil || chScore != nil else { return .unknown }

        if let rssi, let chScore, rssi >= -55 && chScore >= 70 && sec.contains("WPA3") {
            return DiagnosticResult(
                icon: "star.fill",
                title: String(localized: "observation.diagnosis.excellent.title", comment: "Excellent connection"),
                message: String(localized: "observation.diagnosis.excellent.message", comment: "Excellent connection message"),
                severity: .excellent
            )
        }

        if let rssi, rssi < -75 {
            return DiagnosticResult(
                icon: "wifi.slash",
                title: String(localized: "observation.diagnosis.weak_signal.title", comment: "Weak signal"),
                message: String(localized: "observation.diagnosis.weak_signal.message", comment: "Weak signal advice"),
                severity: .critical
            )
        }

        if let chScore, chScore < 50 {
            let channelNum = metricsVerified ? currentStatus.channel ?? 0 : 0
            let recList = channelRecommendations?.prefix(2).map { "\($0.channel)" }.joined(separator: " / ") ?? ""
            return DiagnosticResult(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "observation.diagnosis.congested.title", comment: "Congested channel"),
                message: String(format: String(localized: "observation.diagnosis.congested.message_fmt", comment: "Congested channel with details"), channelNum, apCount, recList),
                severity: .warning
            )
        }

        if let chScore, chScore < 70 {
            return DiagnosticResult(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "observation.diagnosis.mediocre.title", comment: "Mediocre channel"),
                message: String(localized: "observation.diagnosis.mediocre.message", comment: "Mediocre channel advice"),
                severity: .warning
            )
        }

        if !sec.contains("WPA3") && sec != "—" && !sec.isEmpty {
            return DiagnosticResult(
                icon: "lock.open.fill",
                title: String(localized: "observation.diagnosis.security.title", comment: "Weak security"),
                message: String(format: String(localized: "observation.diagnosis.security.message_fmt", comment: "Security advice with type"), sec),
                severity: .warning
            )
        }

        if phy == "802.11n" || phy == "802.11ac" {
            let version = phy == "802.11n" ? "4" : "5"
            return DiagnosticResult(
                icon: "speedometer",
                title: String(localized: "observation.diagnosis.old_phy.title", comment: "Older Wi-Fi generation"),
                message: String(format: String(localized: "observation.diagnosis.old_phy.message_fmt", comment: "PHY upgrade advice"), version),
                severity: .warning
            )
        }

        return DiagnosticResult(
            icon: "checkmark.circle.fill",
            title: String(localized: "observation.diagnosis.ok.title", comment: "Acceptable connection"),
            message: String(localized: "observation.diagnosis.ok.message", comment: "General advice"),
            severity: .ok
        )
    }
}
