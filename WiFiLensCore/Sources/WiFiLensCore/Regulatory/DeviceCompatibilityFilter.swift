import Foundation
import WiFiLensCoreRust

/// Swift adapter for the portable device compatibility rule.
enum DeviceCompatibilityFilter {
    struct Result: Sendable {
        let isCompatible: Bool
        let reason: String?
    }

    static func supportedChannelInputs(from supportedChannels: Set<String>) -> [WiFiLensRegulatorySupportedChannel] {
        supportedChannels.compactMap { value -> WiFiLensRegulatorySupportedChannel? in
            guard let separator = value.firstIndex(of: "-"),
                let band = Int32(String(value[..<separator])),
                let channel = Int32(String(value[value.index(after: separator)...])),
                "\(band)-\(channel)" == value
            else {
                return nil
            }
            return WiFiLensRegulatorySupportedChannel(band: band, channel: channel)
        }
    }

    static func check(
        channel: Int,
        band: String,
        capabilities: DevicePHYCapabilities,
        supportedChannels: Set<String>,
        channelMeta: RegulatoryChannelMeta?
    ) -> Result {
        let supported = supportedChannelInputs(from: supportedChannels)
        var metadataFlags: UInt32 = 0
        if channelMeta?.isDFS == true { metadataFlags |= WIFI_LENS_REGULATORY_META_IS_DFS }
        if channelMeta?.isRadarSensitive == true { metadataFlags |= WIFI_LENS_REGULATORY_META_IS_RADAR_SENSITIVE }
        if channelMeta?.requiresCAC == true { metadataFlags |= WIFI_LENS_REGULATORY_META_REQUIRES_CAC }
        if channelMeta?.forcedSwitchRisk == true { metadataFlags |= WIFI_LENS_REGULATORY_META_FORCED_SWITCH_RISK }
        if channelMeta?.isIndoorOnly == true { metadataFlags |= WIFI_LENS_REGULATORY_META_IS_INDOOR_ONLY }
        if channelMeta?.requiresAFC == true { metadataFlags |= WIFI_LENS_REGULATORY_META_REQUIRES_AFC }
        if channelMeta?.wiFi6EAvailable == true { metadataFlags |= WIFI_LENS_REGULATORY_META_WIFI_6E_AVAILABLE }
        if channelMeta?.wiFi7Available == true { metadataFlags |= WIFI_LENS_REGULATORY_META_WIFI_7_AVAILABLE }

        let capabilityFlags = capabilities.rustCapabilityFlags

        let input = WiFiLensDeviceCompatibilityInput(
            band_code: RegulatoryBandCode.from(band),
            channel: Int32(channel),
            has_supported_channels: supportedChannels.isEmpty ? 0 : 1,
            capability_flags: capabilityFlags,
            has_metadata: channelMeta == nil ? 0 : 1,
            metadata_flags: metadataFlags,
            max_eirp_dbm: Int32(channelMeta?.maxEIRPDbm ?? 0),
            has_max_eirp: channelMeta?.maxEIRPDbm == nil ? 0 : 1,
            note_code: 0
        )
        var output = WiFiLensDeviceCompatibilityResult()
        let status = supported.withUnsafeBufferPointer { buffer in
            withUnsafePointer(to: input) { inputPointer in
                withUnsafeMutablePointer(to: &output) { outputPointer in
                    wifi_lens_regulatory_device_compatibility(
                        inputPointer,
                        buffer.baseAddress,
                        buffer.count,
                        outputPointer
                    )
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust device compatibility returned status \(status)")
            return Result(isCompatible: false, reason: "Device incompatible")
        }

        let reason: String? =
            switch output.reason {
            case WIFI_LENS_DEVICE_REASON_CHANNEL_UNSUPPORTED: "Channel not supported by hardware"
            case WIFI_LENS_DEVICE_REASON_6_GHZ_UNSUPPORTED: "Device does not support 6 GHz"
            case WIFI_LENS_DEVICE_REASON_AFC_UNSUPPORTED: "AFC required (not supported)"
            case WIFI_LENS_DEVICE_REASON_DFS_UNSUPPORTED: "Device does not support DFS channels"
            default: nil
            }
        return Result(isCompatible: output.is_compatible != 0, reason: reason)
    }
}

extension DevicePHYCapabilities {
    var rustCapabilityFlags: UInt32 {
        var flags: UInt32 = 0
        if supportsN { flags |= WIFI_LENS_DEVICE_SUPPORTS_N }
        if supportsAC { flags |= WIFI_LENS_DEVICE_SUPPORTS_AC }
        if supportsAX { flags |= WIFI_LENS_DEVICE_SUPPORTS_AX }
        if supportsBE { flags |= WIFI_LENS_DEVICE_SUPPORTS_BE }
        if supports6GHz { flags |= WIFI_LENS_DEVICE_SUPPORTS_6_GHZ }
        if supportsDFS { flags |= WIFI_LENS_DEVICE_SUPPORTS_DFS }
        if supports160MHz { flags |= WIFI_LENS_DEVICE_SUPPORTS_160_MHZ }
        return flags
    }
}

enum RegulatoryBandCode {
    static func from(_ identifier: String) -> Int32 {
        switch identifier {
        case "24": WIFI_LENS_REGULATORY_BAND_24_GHZ
        case "5": WIFI_LENS_REGULATORY_BAND_5_GHZ
        case "6": WIFI_LENS_REGULATORY_BAND_6_GHZ
        default: 0
        }
    }
}
