import Foundation
import WiFiLensCoreRust

/// Per-channel metadata exposed to the Swift recommendation and display models.
struct RegulatoryChannelMeta: Hashable, Sendable {
    let isDFS: Bool
    let isRadarSensitive: Bool
    let requiresCAC: Bool
    let forcedSwitchRisk: Bool
    let isIndoorOnly: Bool
    let maxEIRPDbm: Int?
    let requiresAFC: Bool
    let wiFi6EAvailable: Bool
    let wiFi7Available: Bool
    let notes: String?

    static let unrestricted = RegulatoryChannelMeta(
        isDFS: false,
        isRadarSensitive: false,
        requiresCAC: false,
        forcedSwitchRisk: false,
        isIndoorOnly: false,
        maxEIRPDbm: nil,
        requiresAFC: false,
        wiFi6EAvailable: true,
        wiFi7Available: true,
        notes: nil
    )
}

/// Swift lookup adapter over the portable Rust regulatory rule table.
enum RegulatoryDatabase {
    struct BandRules: Sendable {
        let allowedChannels: Set<Int>
        let channelMeta: [Int: RegulatoryChannelMeta]
    }

    /// Compatibility view used by existing Swift consumers and tests.
    static let rules: [RegulatoryDomain: [String: BandRules]] = [
        .US: rules(for: .US),
        .JP: rules(for: .JP),
        .CN: rules(for: .CN),
        .EU: rules(for: .EU),
    ]

    static func allowedChannels(for domain: RegulatoryDomain, band: String) -> Set<Int>? {
        rules[domain]?[band]?.allowedChannels
    }

    private static func rules(for domain: RegulatoryDomain) -> [String: BandRules] {
        [
            "24": bandRules(domain: domain, bandCode: WIFI_LENS_REGULATORY_BAND_24_GHZ),
            "5": bandRules(domain: domain, bandCode: WIFI_LENS_REGULATORY_BAND_5_GHZ),
            "6": bandRules(domain: domain, bandCode: WIFI_LENS_REGULATORY_BAND_6_GHZ),
        ]
    }

    private static func bandRules(domain: RegulatoryDomain, bandCode: Int32) -> BandRules {
        var records = [WiFiLensRegulatoryChannelRule](repeating: .init(), count: 256)
        var recordCount = 0
        let status = records.withUnsafeMutableBufferPointer { buffer in
            wifi_lens_regulatory_channel_rules(
                domain.rustCode,
                bandCode,
                buffer.baseAddress,
                buffer.count,
                &recordCount
            )
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust regulatory rule lookup returned status \(status)")
            return BandRules(allowedChannels: [], channelMeta: [:])
        }

        let populated = records.prefix(recordCount)
        var channelMeta: [Int: RegulatoryChannelMeta] = [:]
        for record in populated where record.has_metadata != 0 {
            let flags = record.metadata_flags
            channelMeta[Int(record.channel)] = RegulatoryChannelMeta(
                isDFS: flags & WIFI_LENS_REGULATORY_META_IS_DFS != 0,
                isRadarSensitive: flags & WIFI_LENS_REGULATORY_META_IS_RADAR_SENSITIVE != 0,
                requiresCAC: flags & WIFI_LENS_REGULATORY_META_REQUIRES_CAC != 0,
                forcedSwitchRisk: flags & WIFI_LENS_REGULATORY_META_FORCED_SWITCH_RISK != 0,
                isIndoorOnly: flags & WIFI_LENS_REGULATORY_META_IS_INDOOR_ONLY != 0,
                maxEIRPDbm: record.has_max_eirp == 0 ? nil : Int(record.max_eirp_dbm),
                requiresAFC: flags & WIFI_LENS_REGULATORY_META_REQUIRES_AFC != 0,
                wiFi6EAvailable: flags & WIFI_LENS_REGULATORY_META_WIFI_6E_AVAILABLE != 0,
                wiFi7Available: flags & WIFI_LENS_REGULATORY_META_WIFI_7_AVAILABLE != 0,
                notes: note(for: record.note_code)
            )
        }
        return BandRules(
            allowedChannels: Set(populated.map { Int($0.channel) }),
            channelMeta: channelMeta
        )
    }

    private static func note(for code: Int32) -> String? {
        switch code {
        case 1: "UNII-2A DFS"
        case 2: "UNII-2C DFS"
        case 3: "W53 DFS"
        case 4: "W56 DFS"
        case 5: "802.11b only in Japan"
        default: nil
        }
    }
}
