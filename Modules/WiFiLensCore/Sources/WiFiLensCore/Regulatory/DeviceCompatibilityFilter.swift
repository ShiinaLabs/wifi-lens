import Foundation

/// Checks whether the current device can use a given channel based on its
/// PHY capabilities, band support, and DFS/6 GHz hardware support.
enum DeviceCompatibilityFilter {

    struct Result: Sendable {
        let isCompatible: Bool
        let reason: String?
    }

    /// Determine whether `channel` on `band` is usable by this device.
    static func check(
        channel: Int,
        band: String,
        capabilities: DevicePHYCapabilities,
        supportedChannels: Set<String>,    // "bandRaw-channelNumber" keys
        channelMeta: RegulatoryChannelMeta?
    ) -> Result {
        let key = "\(bandToRaw(band))-\(channel)"

        // 1. Is the channel in the hardware's supported set at all?
        if !supportedChannels.isEmpty && !supportedChannels.contains(key) {
            return Result(isCompatible: false, reason: "Channel not supported by hardware")
        }

        // 2. Band-specific checks
        switch band {
        case "6":
            if !capabilities.supports6GHz {
                return Result(isCompatible: false, reason: "Device does not support 6 GHz")
            }
            // AFC-required channels need special handling (future)
            if let meta = channelMeta, meta.requiresAFC {
                return Result(isCompatible: false, reason: "AFC required (not supported)")
            }

        case "5":
            if let meta = channelMeta, meta.isDFS {
                if !capabilities.supportsDFS {
                    return Result(isCompatible: false, reason: "Device does not support DFS channels")
                }
            }

        default:
            break
        }

        // 3. PHY generation check (future: Wi-Fi 7 320 MHz channels, etc.)
        _ = capabilities

        return Result(isCompatible: true, reason: nil)
    }

    private static func bandToRaw(_ id: String) -> Int {
        switch id {
        case "24": return 1
        case "5":  return 2
        case "6":  return 3
        default:   return 0
        }
    }
}
