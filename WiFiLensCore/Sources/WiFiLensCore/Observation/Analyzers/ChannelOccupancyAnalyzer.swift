import Foundation
import WiFiLensCoreRust

enum ChannelOccupancyAnalyzer {
    static func analyze(
        snapshot: WiFiEnvironmentSnapshot,
        currentChannel: Int?,
        currentBand: ChannelBand? = nil,
        supportedBands: Set<String>,
        targetAP: ChannelQualityCalculator.TargetAP?
    ) -> [ChannelQuality] {
        var strings: [UInt8] = []
        var accessPoints: [WiFiLensChannelOccupancyInput] = []
        for obs in snapshot.networks {
            let bssidBytes = Array(obs.bssid.utf8)
            let bssidOffset = strings.count
            strings.append(contentsOf: bssidBytes)
            accessPoints.append(
                WiFiLensChannelOccupancyInput(
                    band: Int32(obs.channel.band.rawValue),
                    rssi: Int64(obs.rssi),
                    operating_width_mhz: Int32(clamping: obs.channel.channelWidthMHz),
                    bssid_offset: bssidOffset,
                    bssid_length: bssidBytes.count
                )
            )
        }

        var normalized = [WiFiLensChannelOccupancyResult](
            repeating: WiFiLensChannelOccupancyResult(),
            count: accessPoints.count
        )
        var normalizedCount = 0
        let status = accessPoints.withUnsafeBufferPointer { accessPointBuffer in
            strings.withUnsafeBufferPointer { stringBuffer in
                normalized.withUnsafeMutableBufferPointer { outputBuffer in
                    wifi_lens_channel_occupancy_normalize(
                        accessPointBuffer.baseAddress,
                        accessPointBuffer.count,
                        stringBuffer.baseAddress,
                        stringBuffer.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count,
                        &normalizedCount
                    )
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK, normalizedCount <= normalized.count else {
            assertionFailure("Rust channel normalization failed: \(status), \(normalizedCount)")
            return []
        }

        var scoringInputs: [ChannelQualityCalculator.APInfo] = []
        scoringInputs.reserveCapacity(normalizedCount)
        for selection in normalized.prefix(normalizedCount) {
            let sourceIndex = Int(selection.source_index)
            guard snapshot.networks.indices.contains(sourceIndex) else {
                assertionFailure("Rust channel occupancy selected out-of-range source index \(sourceIndex)")
                return []
            }
            guard [20, 40, 80, 160].contains(Int(selection.channel_width_mhz)) else {
                assertionFailure("Rust channel occupancy returned unsupported width \(selection.channel_width_mhz)")
                return []
            }
            let observation = snapshot.networks[sourceIndex]
            scoringInputs.append(
                ChannelQualityCalculator.APInfo(
                    channel: observation.channel.channelNumber,
                    rssi: observation.rssi,
                    channelWidth: String(selection.channel_width_mhz),
                    band: observation.channel.band.id,
                    bssid: observation.bssid,
                    ssid: observation.ssid
                )
            )
        }

        return ChannelQualityCalculator.compute(
            aps: scoringInputs,
            currentChannel: currentChannel,
            currentBand: currentBand?.id,
            supportedBands: supportedBands,
            targetAP: targetAP
        )
    }

}
