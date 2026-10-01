import SwiftUI

enum DiagnosticEvaluator {
    static func evaluate(
        currentStatus: WiFiCurrentStatus,
        quality: WiFiQualityResult? = nil,
        channelAnalysis: [ChannelQuality]? = nil,
        channelRecommendations: [ChannelRecommendation]? = nil
    ) -> DiagnosticResult {
        let rssi = currentStatus.rssi ?? -100
        let chScore = channelAnalysis?
            .first(where: { $0.isCurrentChannel })?
            .qualityScore ?? 50
        let apCount = channelAnalysis?
            .first(where: { $0.isCurrentChannel })?
            .apCount ?? 0
        let sec = currentStatus.security ?? ""
        let phy = currentStatus.phyMode ?? ""

        if rssi >= -55 && chScore >= 70 && sec.contains("WPA3") {
            return DiagnosticResult(
                icon: "star.fill",
                title: String(localized: "observation.diagnosis.excellent.title", comment: "Excellent connection"),
                message: String(localized: "observation.diagnosis.excellent.message", comment: "Excellent connection message"),
                severity: .excellent
            )
        }

        if rssi < -75 {
            return DiagnosticResult(
                icon: "wifi.slash",
                title: String(localized: "observation.diagnosis.weak_signal.title", comment: "Weak signal"),
                message: String(localized: "observation.diagnosis.weak_signal.message", comment: "Weak signal advice"),
                severity: .critical
            )
        }

        if chScore < 50 {
            let channelNum = currentStatus.channel ?? 0
            let recList = channelRecommendations?.prefix(2).map { "\($0.channel)" }.joined(separator: " / ") ?? ""
            return DiagnosticResult(
                icon: "antenna.radiowaves.left.and.right",
                title: String(localized: "observation.diagnosis.congested.title", comment: "Congested channel"),
                message: String(format: String(localized: "observation.diagnosis.congested.message_fmt", comment: "Congested channel with details"), channelNum, apCount, recList),
                severity: .warning
            )
        }

        if chScore < 70 {
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
