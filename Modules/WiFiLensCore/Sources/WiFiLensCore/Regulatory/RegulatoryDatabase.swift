import Foundation

/// Per-channel regulatory metadata. Only populated for channels with caveats;
/// channels not in this dictionary are unrestricted (aside from being
/// region-allowed).
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

// MARK: - Regulatory Database

/// Static, data-driven regulatory rules. No business logic lives here — this is
/// pure channel data sourced from public allocation tables.
enum RegulatoryDatabase {
    static func allowedChannels(for domain: RegulatoryDomain, band: String) -> Set<Int>? {
        rules[domain]?[band]?.allowedChannels
    }

    struct BandRules: Sendable {
        let allowedChannels: Set<Int>
        let channelMeta: [Int: RegulatoryChannelMeta]
    }

    /// Primary lookup: `RegulatoryDatabase.rules[.US]?["5"]`
    static let rules: [RegulatoryDomain: [String: BandRules]] = [
        .US: usRules,
        .JP: jpRules,
        .CN: cnRules,
        .EU: euRules,
    ]

    // MARK: - US (FCC)

    /// US 5 GHz: U-NII-1 (36-48), U-NII-2A (52-64, DFS), U-NII-2C (100-144, DFS), U-NII-3 (149-165).
    /// The channel numbering changes offset at U-NII-3: 36-144 are ≡0 mod 4, 149-165 are ≡1 mod 4.
    private static let us5GHzChannels: Set<Int> = {
        var ch = Set(stride(from: 36, through: 144, by: 4))  // U-NII-1, 2A, 2C
        ch.formUnion(stride(from: 149, through: 165, by: 4))  // U-NII-3
        return ch
    }()

    private static let usRules: [String: BandRules] = {
        let dfsChannels: Set<Int> = [
            52, 56, 60, 64,
            100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
        ]
        let radarSensitive: Set<Int> = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128]
        let indoorOnly5GHz: Set<Int> = [] // US has no indoor-only 5 GHz restriction after R&O

        var fiveMeta = [Int: RegulatoryChannelMeta]()
        for ch in dfsChannels {
            fiveMeta[ch] = RegulatoryChannelMeta(
                isDFS: true,
                isRadarSensitive: radarSensitive.contains(ch),
                requiresCAC: true,
                forcedSwitchRisk: true,
                isIndoorOnly: indoorOnly5GHz.contains(ch),
                maxEIRPDbm: nil,
                requiresAFC: false,
                wiFi6EAvailable: true,
                wiFi7Available: true,
                notes: ch <= 64 ? "UNII-2A DFS" : "UNII-2C DFS"
            )
        }

        // US 6 GHz: LPI (indoor) operation spans the full 5.925-7.125 GHz band
        // (U-NII-5 through U-NII-8, channels 1-233). Per 47 CFR 15.407(a)(5), LPI has
        // no sub-band exclusion; standard power is limited to U-NII-5/7 and requires
        // AFC, which is not modeled here. Channel 2 is the preferred PSC for 6 GHz.
        let sixChannels = Set(stride(from: 1, through: 233, by: 4))
        let sixMeta = [Int: RegulatoryChannelMeta]()

        return [
            "24": BandRules(allowedChannels: Set(1...11), channelMeta: [:]),
            "5":  BandRules(allowedChannels: us5GHzChannels, channelMeta: fiveMeta),
            "6":  BandRules(allowedChannels: sixChannels, channelMeta: sixMeta),
        ]
    }()

    // MARK: - JP (MIC)

    private static let jpRules: [String: BandRules] = {
        let dfsChannels: Set<Int> = [
            52, 56, 60, 64,
            100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140,
        ]
        let radarSensitive: Set<Int> = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128]

        var fiveMeta = [Int: RegulatoryChannelMeta]()
        for ch in dfsChannels {
            fiveMeta[ch] = RegulatoryChannelMeta(
                isDFS: true,
                isRadarSensitive: radarSensitive.contains(ch),
                requiresCAC: true,
                forcedSwitchRisk: true,
                isIndoorOnly: false,
                maxEIRPDbm: nil,
                requiresAFC: false,
                wiFi6EAvailable: true,
                wiFi7Available: true,
                notes: ch <= 64 ? "W53 DFS" : "W56 DFS"
            )
        }

        // JP 6 GHz: LPI channels 1-93 only
        let sixChannels = Set(stride(from: 1, through: 93, by: 4))

        return [
            "24": BandRules(allowedChannels: Set(1...14), channelMeta: [
                14: RegulatoryChannelMeta(
                    isDFS: false, isRadarSensitive: false, requiresCAC: false,
                    forcedSwitchRisk: false, isIndoorOnly: false, maxEIRPDbm: nil,
                    requiresAFC: false, wiFi6EAvailable: false, wiFi7Available: false,
                    notes: "802.11b only in Japan"
                ),
            ]),
            "5": BandRules(
                allowedChannels: Set(stride(from: 36, through: 144, by: 4)),
                channelMeta: fiveMeta
            ),
            "6": BandRules(allowedChannels: sixChannels, channelMeta: [:]),
        ]
    }()

    // MARK: - CN (SRRC)

    private static let cnRules: [String: BandRules] = {
        return [
            "24": BandRules(allowedChannels: Set(1...13), channelMeta: [:]),
            "5": BandRules(
                allowedChannels: Set(
                    Array(stride(from: 36, through: 48, by: 4)) +
                    Array(stride(from: 149, through: 165, by: 4))
                ),
                channelMeta: [:]
            ),
            // No 6 GHz allocation yet in China
            "6": BandRules(allowedChannels: [], channelMeta: [:]),
        ]
    }()

    // MARK: - EU (ETSI)

    private static let euRules: [String: BandRules] = {
        let dfsChannels: Set<Int> = [
            52, 56, 60, 64,
            100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140,
        ]
        let radarSensitive: Set<Int> = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128]

        var fiveMeta = [Int: RegulatoryChannelMeta]()
        for ch in dfsChannels {
            fiveMeta[ch] = RegulatoryChannelMeta(
                isDFS: true,
                isRadarSensitive: radarSensitive.contains(ch),
                requiresCAC: true,
                forcedSwitchRisk: true,
                isIndoorOnly: false,
                maxEIRPDbm: nil,
                requiresAFC: false,
                wiFi6EAvailable: true,
                wiFi7Available: true,
                notes: ch <= 64 ? "UNII-2A DFS" : "UNII-2C DFS"
            )
        }

        // EU 6 GHz: LPI channels 1-93 only
        let sixChannels = Set(stride(from: 1, through: 93, by: 4))

        return [
            "24": BandRules(allowedChannels: Set(1...13), channelMeta: [:]),
            "5": BandRules(
                allowedChannels: Set(stride(from: 36, through: 144, by: 4)),
                channelMeta: fiveMeta
            ),
            "6": BandRules(allowedChannels: sixChannels, channelMeta: [:]),
        ]
    }()
}
