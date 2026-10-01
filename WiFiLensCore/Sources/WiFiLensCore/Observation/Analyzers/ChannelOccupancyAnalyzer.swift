import Foundation

enum ChannelOccupancyAnalyzer {
    static func analyze(
        snapshot: WiFiEnvironmentSnapshot,
        currentChannel: Int?,
        currentBand: ChannelBand? = nil,
        supportedBands: Set<String>,
        targetAP: ChannelQualityCalculator.TargetAP?
    ) -> [ChannelQuality] {
        var seen = [String: ChannelQualityCalculator.APInfo]()
        for obs in snapshot.networks {
            let key = "\(obs.bssid)-\(obs.channel.band.rawValue)"
            // Use the operating width reported by CWChannel for occupancy
            // geometry. IE-derived width labels are exposed separately on the
            // observation capabilities and do not replace this channel model.
            let widthLabel = channelWidthLabel(obs.channel.channelWidthMHz)
            let info = ChannelQualityCalculator.APInfo(
                channel: obs.channel.channelNumber,
                rssi: obs.rssi,
                channelWidth: widthLabel,
                band: obs.channel.band.id,
                bssid: obs.bssid,
                ssid: obs.ssid
            )
            if let existing = seen[key] {
                if info.rssi > existing.rssi { seen[key] = info }
            } else {
                seen[key] = info
            }
        }
        return ChannelQualityCalculator.compute(
            aps: Array(seen.values),
            currentChannel: currentChannel,
            currentBand: currentBand?.id,
            supportedBands: supportedBands,
            targetAP: targetAP
        )
    }

    private static func channelWidthLabel(_ width: Int) -> String {
        switch width {
        case 160: return "160"
        case 80:  return "80"
        case 40:  return "40"
        default:  return "20"
        }
    }
}
