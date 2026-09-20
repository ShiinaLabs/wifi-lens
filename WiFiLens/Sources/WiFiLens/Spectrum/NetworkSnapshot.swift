import Foundation

/// A lightweight snapshot of a single network from one scan moment.
/// Stored per BSSID for trend charts and future data export.
struct NetworkSnapshot: Codable {
    let timestamp: Date
    let bssid: String
    let ssid: String
    let rssi: Int
    let channel: Int
    let band: String
    let phyMode: String
    let channelWidth: String
    /// Scalar width used for historical chart geometry. Unknown IE labels use
    /// the CoreWLAN fallback; non-contiguous 80+80 uses one 80 MHz segment.
    let channelWidthMHz: Int
    let mcs: String
    let nss: String
    let security: String
    let country: String
    let supportsK: Bool
    let supportsR: Bool
    let supportsV: Bool
    let supportsWPA3: Bool
    let isHiddenSSID: Bool

    init(
        timestamp: Date,
        bssid: String,
        ssid: String,
        rssi: Int,
        channel: Int,
        band: String,
        phyMode: String,
        channelWidth: String,
        channelWidthMHz: Int? = nil,
        mcs: String,
        nss: String,
        security: String,
        country: String,
        supportsK: Bool,
        supportsR: Bool,
        supportsV: Bool,
        supportsWPA3: Bool,
        isHiddenSSID: Bool
    ) {
        self.timestamp = timestamp
        self.bssid = bssid
        self.ssid = ssid
        self.rssi = rssi
        self.channel = channel
        self.band = band
        self.phyMode = phyMode
        self.channelWidth = channelWidth
        self.channelWidthMHz = channelWidthMHz ?? Self.scalarWidth(for: channelWidth)
        self.mcs = mcs
        self.nss = nss
        self.security = security
        self.country = country
        self.supportsK = supportsK
        self.supportsR = supportsR
        self.supportsV = supportsV
        self.supportsWPA3 = supportsWPA3
        self.isHiddenSSID = isHiddenSSID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        bssid = try container.decodeIfPresent(String.self, forKey: .bssid) ?? ""
        ssid = try container.decodeIfPresent(String.self, forKey: .ssid) ?? ""
        rssi = try container.decode(Int.self, forKey: .rssi)
        channel = try container.decode(Int.self, forKey: .channel)
        band = try container.decode(String.self, forKey: .band)
        phyMode = try container.decode(String.self, forKey: .phyMode)
        channelWidth = try container.decode(String.self, forKey: .channelWidth)
        channelWidthMHz = try container.decodeIfPresent(Int.self, forKey: .channelWidthMHz)
            ?? Self.scalarWidth(for: channelWidth)
        mcs = try container.decode(String.self, forKey: .mcs)
        nss = try container.decode(String.self, forKey: .nss)
        security = try container.decode(String.self, forKey: .security)
        country = try container.decode(String.self, forKey: .country)
        supportsK = try container.decode(Bool.self, forKey: .supportsK)
        supportsR = try container.decode(Bool.self, forKey: .supportsR)
        supportsV = try container.decode(Bool.self, forKey: .supportsV)
        supportsWPA3 = try container.decode(Bool.self, forKey: .supportsWPA3)
        isHiddenSSID = try container.decodeIfPresent(Bool.self, forKey: .isHiddenSSID) ?? false
    }

    static func scalarWidth(for label: String) -> Int {
        switch label {
        case "160": return 160
        case "80", "80+80": return 80
        case "40": return 40
        case "20": return 20
        default: return 20
        }
    }
}
