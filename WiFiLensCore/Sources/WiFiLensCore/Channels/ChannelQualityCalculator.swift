import Foundation
import WiFiLensCoreRust

/// Per-channel congestion analysis result.
/// This model preserves the observed RF environment and carries a separate
/// counterfactual recommendation score that excludes the current target AP.
public struct ChannelQuality: Identifiable, Sendable {
    public init(
        channel: Int,
        band: String,
        bandDisplay: String,
        qualityScore: Int,
        qualityLevel: QualityLevel,
        apCount: Int,
        coChannelCount: Int,
        adjacentCount: Int,
        interferenceScore: Int,
        overlapLevel: OverlapLevel,
        strongestNeighborRSSI: Int,
        isRecommended: Bool = false,
        isCurrentChannel: Bool = false,
        showInSimpleView: Bool = true,
        recommendationScore: Int = 0,
        recommendationLevel: QualityLevel = .excellent,
        recommendationConfidence: RecommendationConfidence = .unknown,
        recommendationState: RecommendationState = .targetUnknown
    ) {
        self.channel = channel
        self.band = band
        self.bandDisplay = bandDisplay
        self.qualityScore = qualityScore
        self.qualityLevel = qualityLevel
        self.apCount = apCount
        self.coChannelCount = coChannelCount
        self.adjacentCount = adjacentCount
        self.interferenceScore = interferenceScore
        self.overlapLevel = overlapLevel
        self.strongestNeighborRSSI = strongestNeighborRSSI
        self.isRecommended = isRecommended
        self.isCurrentChannel = isCurrentChannel
        self.showInSimpleView = showInSimpleView
        self.recommendationScore = recommendationScore
        self.recommendationLevel = recommendationLevel
        self.recommendationConfidence = recommendationConfidence
        self.recommendationState = recommendationState
    }
    public let channel: Int
    public let band: String
    public let bandDisplay: String
    public let qualityScore: Int  // 0–100
    public let qualityLevel: QualityLevel
    public let apCount: Int  // APs on or overlapping this channel
    public let coChannelCount: Int  // APs on the same channel only
    public let adjacentCount: Int  // APs on overlapping adjacent channels
    public let interferenceScore: Int  // raw interference penalty (0 = clean)
    public let overlapLevel: OverlapLevel
    public let strongestNeighborRSSI: Int
    public var isRecommended: Bool = false
    public var isCurrentChannel: Bool = false
    public var showInSimpleView: Bool = true
    public var recommendationScore: Int = 0
    public var recommendationLevel: QualityLevel = .excellent
    public var recommendationConfidence: RecommendationConfidence = .unknown
    public var recommendationState: RecommendationState = .targetUnknown

    public var id: String { "\(band)-\(channel)" }

    public enum QualityLevel: String, CaseIterable, Sendable {
        case excellent
        case good
        case moderate
        case busy
        case congested

        public var displayName: String {
            switch self {
            case .excellent: String(localized: "channels.quality.excellent", comment: "Excellent channel quality tier")
            case .good: String(localized: "overview.signal.good", comment: "Good signal level label")
            case .moderate: String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
            case .busy: String(localized: "channels.quality.busy", comment: "Busy channel quality tier")
            case .congested: String(localized: "channels.quality.congested", comment: "Congested channel quality tier")
            }
        }

        public var scoreRange: ClosedRange<Int> {
            switch self {
            case .excellent: 90...100
            case .good: 70...89
            case .moderate: 50...69
            case .busy: 30...49
            case .congested: 0...29
            }
        }

        public var color: String {
            switch self {
            case .excellent: "#34C759"
            case .good: "#30B0C7"
            case .moderate: "#FF9F0A"
            case .busy: "#FF6B35"
            case .congested: "#FF3B30"
            }
        }

        public var minScore: Int { scoreRange.lowerBound }

        public static func from(score: Int) -> Self {
            switch score {
            case 90...100: .excellent
            case 70...89: .good
            case 50...69: .moderate
            case 30...49: .busy
            default: .congested
            }
        }

        fileprivate var order: Int {
            switch self {
            case .excellent: 4
            case .good: 3
            case .moderate: 2
            case .busy: 1
            case .congested: 0
            }
        }
    }

    public enum OverlapLevel: String, Sendable {
        case low
        case moderate
        case high

        public var displayName: String {
            switch self {
            case .low: String(localized: "channels.overlap.low", comment: "Low overlap level")
            case .moderate: String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
            case .high: String(localized: "channels.overlap.high", comment: "High overlap level")
            }
        }
    }

    public enum RecommendationConfidence: String, Sendable {
        case exact
        case ssidFallback
        case unknown
    }

    public enum RecommendationState: String, Sendable {
        case recommended
        case currentGoodEnough
        case insufficientImprovement
        case notCandidate
        case targetUnknown
    }

    /// Base simple-view visibility from the RF snapshot and selected recommendations.
    public var initiallyVisibleInSimpleView: Bool {
        isCurrentChannel || isRecommended || apCount > 0
    }
}

/// Hysteresis wrapper that smooths score fluctuations across level boundaries.
/// Used by the overview card to avoid visual flicker while scan results update.
public struct StableScore {
    private var current: Double
    private var level: ChannelQuality.QualityLevel

    public init(initialScore: Int = 100) {
        self.current = Double(initialScore)
        self.level = .from(score: initialScore)
    }

    public mutating func update(score: Int, downgradeMargin: Int = 10, upgradeMargin: Int = 6) -> Int {
        let rawLevel = ChannelQuality.QualityLevel.from(score: score)
        let alpha = 0.25

        if rawLevel.order > level.order {
            if score >= level.scoreRange.upperBound + upgradeMargin {
                current = Double(score)
                level = rawLevel
            }
        } else if rawLevel.order < level.order {
            if score <= level.minScore - downgradeMargin {
                current = Double(score)
                level = rawLevel
            }
        } else {
            current = alpha * Double(score) + (1 - alpha) * current
        }
        return Int(current.rounded())
    }

    public mutating func reset(score: Int = 100) {
        current = Double(score)
        level = .from(score: score)
    }
}

/// Computes channel congestion scores per band.
public enum ChannelQualityCalculator {
    public struct TargetAP {
        public let bssid: String?
        public let ssid: String?
        public let channel: Int?

        public init(bssid: String?, ssid: String?, channel: Int?) {
            self.bssid = bssid?.nilIfBlank
            self.ssid = ssid?.nilIfBlank
            self.channel = channel
        }
    }

    public struct APInfo {
        public let channel: Int
        public let rssi: Int
        public let channelWidth: String
        public let band: String
        public let bssid: String?
        public let ssid: String?

        public init(
            channel: Int, rssi: Int, channelWidth: String, band: String, bssid: String? = nil, ssid: String? = nil
        ) {
            self.channel = channel
            self.rssi = rssi
            self.channelWidth = channelWidth
            self.band = band
            self.bssid = bssid?.nilIfBlank
            self.ssid = ssid?.nilIfBlank
        }
    }

    /// Produce observed RF quality and counterfactual recommendation scores for every relevant channel.
    public static func compute(
        aps: [APInfo],
        currentChannel: Int? = nil,
        currentBand: String? = nil,
        supportedBands: Set<String> = ["24", "5", "6"],
        targetAP: TargetAP? = nil
    ) -> [ChannelQuality] {
        var stringBytes: [UInt8] = []
        var accessPointInputs: [WiFiLensAccessPointInput] = []
        for ap in aps {
            guard let band = ChannelBand(id: ap.band) else { continue }

            let bssidBytes = ap.bssid.map { Array($0.lowercased().utf8) } ?? []
            let bssidOffset = stringBytes.count
            stringBytes.append(contentsOf: bssidBytes)
            let ssidBytes = ap.ssid.map { Array($0.precomposedStringWithCanonicalMapping.utf8) } ?? []
            let ssidOffset = stringBytes.count
            stringBytes.append(contentsOf: ssidBytes)
            let widthMHz = switch ap.channelWidth {
            case "40": 40
            case "80": 80
            case "80+80": 8080
            case "160": 160
            default: 20
            }

            accessPointInputs.append(
                WiFiLensAccessPointInput(
                    channel: Int64(ap.channel),
                    rssi: Int64(ap.rssi),
                    band: Int32(band.rawValue),
                    channel_width_mhz: Int32(widthMHz),
                    bssid_offset: bssidOffset,
                    bssid_length: bssidBytes.count,
                    ssid_offset: ssidOffset,
                    ssid_length: ssidBytes.count
                )
            )
        }

        let targetBSSID = targetAP?.bssid.map { Array($0.lowercased().utf8) } ?? []
        let targetBSSIDOffset = stringBytes.count
        stringBytes.append(contentsOf: targetBSSID)
        let targetSSID = targetAP?.ssid.map { Array($0.precomposedStringWithCanonicalMapping.utf8) } ?? []
        let targetSSIDOffset = stringBytes.count
        stringBytes.append(contentsOf: targetSSID)

        let resolvedCurrentBand = currentBand.flatMap(ChannelBand.init(id:))
        let resolvedCurrentChannel = currentBand == nil || resolvedCurrentBand != nil ? currentChannel : nil
        var flags: UInt32 = 0
        if resolvedCurrentChannel != nil { flags |= WIFI_LENS_QUALITY_HAS_CURRENT_CHANNEL }
        if !targetBSSID.isEmpty { flags |= WIFI_LENS_QUALITY_HAS_TARGET_BSSID }
        if !targetSSID.isEmpty { flags |= WIFI_LENS_QUALITY_HAS_TARGET_SSID }
        if targetAP?.channel != nil { flags |= WIFI_LENS_QUALITY_HAS_TARGET_CHANNEL }

        var supportedBandMask: UInt32 = 0
        if supportedBands.contains("24") { supportedBandMask |= WIFI_LENS_BAND_24_GHZ }
        if supportedBands.contains("5") { supportedBandMask |= WIFI_LENS_BAND_5_GHZ }
        if supportedBands.contains("6") { supportedBandMask |= WIFI_LENS_BAND_6_GHZ }

        let config = WiFiLensChannelQualityConfig(
            flags: flags,
            current_channel: Int64(resolvedCurrentChannel ?? 0),
            target_channel: Int64(targetAP?.channel ?? 0),
            current_band: Int32(resolvedCurrentBand?.rawValue ?? 0),
            supported_band_mask: supportedBandMask,
            target_bssid_offset: targetBSSIDOffset,
            target_bssid_length: targetBSSID.count,
            target_ssid_offset: targetSSIDOffset,
            target_ssid_length: targetSSID.count
        )

        var output = [WiFiLensChannelQualityResult](
            repeating: WiFiLensChannelQualityResult(),
            count: Int(WIFI_LENS_MAX_CHANNEL_QUALITIES)
        )
        var outputCount = 0
        let status = accessPointInputs.withUnsafeBufferPointer { accessPointBuffer in
            stringBytes.withUnsafeBufferPointer { stringBuffer in
                output.withUnsafeMutableBufferPointer { resultBuffer in
                    withUnsafePointer(to: config) { configPointer in
                        wifi_lens_channel_quality_analyze(
                            accessPointBuffer.baseAddress,
                            accessPointBuffer.count,
                            stringBuffer.baseAddress,
                            stringBuffer.count,
                            configPointer,
                            resultBuffer.baseAddress,
                            resultBuffer.count,
                            &outputCount
                        )
                    }
                }
            }
        }

        guard status == WIFI_LENS_STATUS_OK, outputCount <= output.count else {
            assertionFailure("Rust channel quality returned status \(status) and count \(outputCount)")
            return []
        }

        return output.prefix(outputCount).map { result in
            let bandCode = Int(result.band)
            guard let band = ChannelBand(rawValue: bandCode) else {
                preconditionFailure("Rust channel quality returned unsupported band code \(bandCode)")
            }
            let qualityScore = Int(result.quality_score)
            let recommendationScore = Int(result.recommendation_score)
            let overlapLevel: ChannelQuality.OverlapLevel = switch result.ap_count {
            case 0...1: .low
            case 2...3: .moderate
            default: .high
            }
            let recommendationConfidence: ChannelQuality.RecommendationConfidence = switch result.recommendation_confidence {
            case 1: .exact
            case 2: .ssidFallback
            default: .unknown
            }
            let recommendationState: ChannelQuality.RecommendationState = switch result.recommendation_state {
            case 0: .recommended
            case 1: .currentGoodEnough
            case 2: .insufficientImprovement
            case 3: .notCandidate
            default: .targetUnknown
            }

            return ChannelQuality(
                channel: Int(result.channel),
                band: band.id,
                bandDisplay: band.displayName,
                qualityScore: qualityScore,
                qualityLevel: .from(score: qualityScore),
                apCount: Int(result.ap_count),
                coChannelCount: Int(result.co_channel_count),
                adjacentCount: Int(result.adjacent_count),
                interferenceScore: Int(result.interference_score),
                overlapLevel: overlapLevel,
                strongestNeighborRSSI: Int(result.strongest_neighbor_rssi),
                isRecommended: result.is_recommended != 0,
                isCurrentChannel: result.is_current_channel != 0,
                showInSimpleView: result.show_in_simple_view != 0,
                recommendationScore: recommendationScore,
                recommendationLevel: .from(score: recommendationScore),
                recommendationConfidence: recommendationConfidence,
                recommendationState: recommendationState
            )
        }
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
