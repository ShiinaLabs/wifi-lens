import Foundation

/// Per-channel congestion analysis result.
/// This model preserves the observed RF environment and carries a separate
/// counterfactual recommendation score that excludes the current target AP.
struct ChannelQuality: Identifiable {
    let channel: Int
    let band: String
    let bandDisplay: String
    let qualityScore: Int          // 0–100
    let qualityLevel: QualityLevel
    let apCount: Int               // APs on or overlapping this channel
    let coChannelCount: Int         // APs on the same channel only
    let adjacentCount: Int          // APs on overlapping adjacent channels
    let interferenceScore: Int      // raw interference penalty (0 = clean)
    let overlapLevel: OverlapLevel
    let strongestNeighborRSSI: Int
    var isRecommended: Bool = false
    var isCurrentChannel: Bool = false
    var showInSimpleView: Bool = true
    var recommendationScore: Int = 0
    var recommendationLevel: QualityLevel = .excellent
    var recommendationConfidence: RecommendationConfidence = .unknown
    var recommendationState: RecommendationState = .targetUnknown

    var id: String { "\(band)-\(channel)" }

    enum QualityLevel: String, CaseIterable {
        case excellent
        case good
        case moderate
        case busy
        case congested

        var displayName: String {
            switch self {
            case .excellent: String(localized: "channels.quality.excellent", comment: "Excellent channel quality tier")
            case .good:      String(localized: "overview.signal.good", comment: "Good signal level label")
            case .moderate:  String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
            case .busy:      String(localized: "channels.quality.busy", comment: "Busy channel quality tier")
            case .congested: String(localized: "channels.quality.congested", comment: "Congested channel quality tier")
            }
        }

        var scoreRange: ClosedRange<Int> {
            switch self {
            case .excellent: 90...100
            case .good:      70...89
            case .moderate:  50...69
            case .busy:      30...49
            case .congested: 0...29
            }
        }

        var color: String {
            switch self {
            case .excellent: "#34C759"
            case .good:      "#30B0C7"
            case .moderate:  "#FF9F0A"
            case .busy:      "#FF6B35"
            case .congested: "#FF3B30"
            }
        }

        var minScore: Int { scoreRange.lowerBound }

        static func from(score: Int) -> Self {
            switch score {
            case 90...100: .excellent
            case 70...89:  .good
            case 50...69:  .moderate
            case 30...49:  .busy
            default:       .congested
            }
        }

        fileprivate var order: Int {
            switch self {
            case .excellent: 4; case .good: 3; case .moderate: 2; case .busy: 1; case .congested: 0
            }
        }
    }

    enum OverlapLevel: String {
        case low
        case moderate
        case high

        var displayName: String {
            switch self {
            case .low:      String(localized: "channels.overlap.low", comment: "Low overlap level")
            case .moderate: String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
            case .high:     String(localized: "channels.overlap.high", comment: "High overlap level")
            }
        }
    }

    enum RecommendationConfidence: String {
        case exact
        case ssidFallback
        case unknown
    }

    enum RecommendationState: String {
        case recommended
        case currentGoodEnough
        case insufficientImprovement
        case notCandidate
        case targetUnknown
    }

    /// Base simple-view visibility from the RF snapshot and selected recommendations.
    var initiallyVisibleInSimpleView: Bool {
        isCurrentChannel || isRecommended || apCount > 0
    }
}

/// Hysteresis wrapper that smooths score fluctuations across level boundaries.
/// Used by the overview card to avoid visual flicker while scan results update.
struct StableScore {
    private var current: Double
    private var level: ChannelQuality.QualityLevel

    init(initialScore: Int = 100) {
        self.current = Double(initialScore)
        self.level = .from(score: initialScore)
    }

    mutating func update(score: Int, downgradeMargin: Int = 10, upgradeMargin: Int = 6) -> Int {
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

    mutating func reset(score: Int = 100) {
        current = Double(score)
        level = .from(score: score)
    }
}

/// Computes channel congestion scores per band.
enum ChannelQualityCalculator {
    private static let currentGoodEnoughScore = 80
    private static let minimumRecommendedScore = 70
    private static let minimumImprovement = 10
    private static let maxRecommendationsPerBand = 2

    struct TargetAP {
        let bssid: String?
        let ssid: String?
        let channel: Int?

        init(bssid: String?, ssid: String?, channel: Int?) {
            self.bssid = bssid?.nilIfBlank
            self.ssid = ssid?.nilIfBlank
            self.channel = channel
        }
    }

    struct APInfo {
        let channel: Int
        let rssi: Int
        let channelWidth: String  // "20"/"40"/"80"/"160"/"80+80"
        let band: String          // "24"/"5"/"6"
        let bssid: String?
        let ssid: String?

        init(channel: Int, rssi: Int, channelWidth: String, band: String, bssid: String? = nil, ssid: String? = nil) {
            self.channel = channel
            self.rssi = rssi
            self.channelWidth = channelWidth
            self.band = band
            self.bssid = bssid?.nilIfBlank
            self.ssid = ssid?.nilIfBlank
        }
    }

    /// Produce observed RF quality and counterfactual recommendation scores for every relevant channel.
    static func compute(
        aps: [APInfo],
        currentChannel: Int? = nil,
        currentBand: String? = nil,
        supportedBands: Set<String> = ["24", "5", "6"],
        targetAP: TargetAP? = nil
    ) -> [ChannelQuality] {
        var results: [ChannelQuality] = []

        for band in supportedBands.sorted() {
            let bandAPs = aps.filter { $0.band == band }
            let bandCurrentChannel = currentBand == nil || currentBand == band
                ? currentChannel
                : nil
            let targetResolution = resolveTargetAP(targetAP, in: bandAPs)
            let recommendationAPs = targetResolution.confidence == .unknown
                ? bandAPs
                : bandAPs.filter { !targetResolution.matches($0) }

            let channels: [Int] = {
                switch band {
                case "24": return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
                case "5":  return stride(from: 36, through: 144, by: 4).map { $0 }
                          + stride(from: 149, through: 165, by: 4).map { $0 }
                default:   return stride(from: 1, through: 233, by: 4).map { $0 }
                }
            }()

            let bandDisplay = band == "24" ? String(localized: "wifi.band.24ghz", comment: "2.4 GHz Wi-Fi band name") : band == "5" ? String(localized: "wifi.band.5ghz", comment: "5 GHz Wi-Fi band name") : String(localized: "wifi.band.6ghz", comment: "6 GHz Wi-Fi band name")

            var scored = channels.map { ch -> ChannelQuality in
                let observed = score(channel: ch, band: band, aps: bandAPs)
                let recommendation = score(channel: ch, band: band, aps: recommendationAPs)
                let level = ChannelQuality.QualityLevel.from(score: observed.score)
                let recommendationLevel = ChannelQuality.QualityLevel.from(score: recommendation.score)
                let strongest = bandAPs
                    .filter { overlaps(channel: ch, other: $0, band: band) }
                    .map(\.rssi).max() ?? -100
                let allOverlapping = bandAPs.filter { overlaps(channel: ch, other: $0, band: band) }
                let overlapCount = allOverlapping.count
                let coChanCount = bandAPs.filter { $0.channel == ch }.count
                let adjCount = allOverlapping.filter { $0.channel != ch }.count
                let overlap: ChannelQuality.OverlapLevel = switch overlapCount {
                case 0...1: .low
                case 2...3: .moderate
                default:    .high
                }

                return ChannelQuality(
                    channel: ch,
                    band: band,
                    bandDisplay: bandDisplay,
                    qualityScore: observed.score,
                    qualityLevel: level,
                    apCount: overlapCount,
                    coChannelCount: coChanCount,
                    adjacentCount: adjCount,
                    interferenceScore: observed.interference,
                    overlapLevel: overlap,
                    strongestNeighborRSSI: strongest,
                    isRecommended: false,
                    isCurrentChannel: ch == bandCurrentChannel,
                    showInSimpleView: ch == bandCurrentChannel || overlapCount > 0,
                    recommendationScore: recommendation.score,
                    recommendationLevel: recommendationLevel,
                    recommendationConfidence: targetResolution.confidence,
                    recommendationState: targetResolution.confidence == .unknown ? .targetUnknown : .notCandidate
                )
            }
            applyCounterfactualSelection(
                to: &scored,
                currentChannel: bandCurrentChannel,
                confidence: targetResolution.confidence
            )
            results += scored
        }

        // Sort the final channel view without relying on external mutation.
        return results.sorted { a, b in
            if a.isCurrentChannel != b.isCurrentChannel { return a.isCurrentChannel }
            if a.isRecommended != b.isRecommended { return a.isRecommended }
            if a.recommendationScore != b.recommendationScore { return a.recommendationScore > b.recommendationScore }
            if a.qualityScore != b.qualityScore { return a.qualityScore > b.qualityScore }
            if a.band != b.band { return a.band < b.band }
            return a.channel < b.channel
        }
    }

    // MARK: - Interference model

    private struct ScoreResult {
        let score: Int
        let interference: Int
    }

    private static func score(channel: Int, band: String, aps: [APInfo]) -> ScoreResult {
        let interference = computeInterference(channel: channel, band: band, aps: aps)
        return ScoreResult(score: max(0, min(100, 100 - interference)), interference: interference)
    }

    private struct TargetResolution {
        let confidence: ChannelQuality.RecommendationConfidence
        let matcher: (APInfo) -> Bool

        func matches(_ ap: APInfo) -> Bool {
            matcher(ap)
        }
    }

    private static func resolveTargetAP(_ target: TargetAP?, in aps: [APInfo]) -> TargetResolution {
        guard let target else {
            return TargetResolution(confidence: .unknown) { _ in false }
        }

        if let bssid = target.bssid {
            return TargetResolution(confidence: .exact) { ap in
                ap.bssid?.caseInsensitiveCompare(bssid) == .orderedSame
            }
        }

        if let ssid = target.ssid {
            let candidates = aps.filter { ap in
                ap.ssid == ssid && target.channel.map { ap.channel == $0 } ?? true
            }
            guard candidates.count == 1 else {
                return TargetResolution(confidence: .unknown) { _ in false }
            }
            return TargetResolution(confidence: .ssidFallback) { ap in
                ap.ssid == ssid && target.channel.map { ap.channel == $0 } ?? true
            }
        }

        return TargetResolution(confidence: .unknown) { _ in false }
    }

    private static func applyCounterfactualSelection(
        to scored: inout [ChannelQuality],
        currentChannel: Int?,
        confidence: ChannelQuality.RecommendationConfidence
    ) {
        guard confidence != .unknown, let currentChannel else {
            for index in scored.indices {
                scored[index].showInSimpleView = scored[index].initiallyVisibleInSimpleView
            }
            return
        }

        guard let current = scored.first(where: { $0.channel == currentChannel }) else {
            for index in scored.indices {
                scored[index].showInSimpleView = scored[index].initiallyVisibleInSimpleView
            }
            return
        }

        if current.recommendationScore >= currentGoodEnoughScore {
            for index in scored.indices {
                if scored[index].channel == currentChannel {
                    scored[index].recommendationState = .currentGoodEnough
                }
                scored[index].showInSimpleView = scored[index].initiallyVisibleInSimpleView
            }
            return
        }

        let selectedIDs = Set(scored
            .filter { candidate in
                candidate.channel != currentChannel
                    && candidate.recommendationScore >= minimumRecommendedScore
                    && candidate.recommendationScore - current.recommendationScore >= minimumImprovement
            }
            .sorted { a, b in
                if a.recommendationScore != b.recommendationScore { return a.recommendationScore > b.recommendationScore }
                if a.qualityScore != b.qualityScore { return a.qualityScore > b.qualityScore }
                return a.channel < b.channel
            }
            .prefix(maxRecommendationsPerBand)
            .map(\.id))

        for index in scored.indices {
            if selectedIDs.contains(scored[index].id) {
                scored[index].isRecommended = true
                scored[index].recommendationState = .recommended
            } else if scored[index].channel != currentChannel {
                scored[index].recommendationState = .insufficientImprovement
            }
            scored[index].showInSimpleView = scored[index].initiallyVisibleInSimpleView
        }
    }

    private static func computeInterference(channel: Int, band: String, aps: [APInfo]) -> Int {
        var penalty: Double = 0
        for ap in aps {
            let factor = overlapFactor(channel: channel, other: ap, band: band)
            guard factor > 0 else { continue }
            let rssiWeight = max(0, min(1, Double(ap.rssi + 100) / 70.0))
            let widthMul: Double = switch ap.channelWidth {
            case "160":     2.0
            case "80", "80+80": 1.5
            case "40":      1.2
            default:         1.0
            }
            let bandMul: Double = band == "24" ? 1.8 : 1.0
            penalty += factor * rssiWeight * widthMul * bandMul * 18.0
        }
        return Int(penalty.rounded())
    }

    /// 0.0 = no overlap, 1.0 = co-channel, 0.1–0.8 = partial overlap
    private static func overlapFactor(channel: Int, other: APInfo, band: String) -> Double {
        if other.channel == channel { return 1.0 }

        if band == "24" {
            // 2.4 GHz channels are 5 MHz apart, so adjacent channels overlap in
            // practice; keep the empirical distance heuristic.
            let dist = abs(channel - other.channel)
            return switch dist {
            case 1: 0.8
            case 2: 0.55
            case 3: 0.3
            case 4: 0.15
            default: 0
            }
        }

        // 5 / 6 GHz: 20 MHz channels sit on standard blocks, so non-overlapping
        // primary channels do not interfere. Compute the real frequency-band
        // overlap between the 20 MHz candidate channel and the AP's block, and
        // normalize by the AP span length: a wide AP contributes at most
        // 1.0/0.5/0.25/0.125 (20/40/80/160 MHz) to one non-co-channel 20 MHz
        // candidate (the primary channel carries beacons/control; secondary
        // channels carry data only). widthMul in computeInterference partially
        // compensates wider APs.
        guard let channelBand = ChannelBand(id: band) else { return 0 }
        // 80+80 is non-contiguous and cannot be represented by the scalar
        // channelBlock model. Use one 80 MHz segment for defensive geometry.
        let apWidth: Int = switch other.channelWidth {
        case "160": 160
        case "80", "80+80": 80
        case "40": 40
        case "20": 20
        default: 20
        }
        let candidateSpan = ChannelSpanCalculator.channelBlock(
            primaryChannel: channel, widthMHz: 20, band: channelBand, spanDirection: nil
        )
        let apSpan = ChannelSpanCalculator.channelBlock(
            primaryChannel: other.channel, widthMHz: apWidth, band: channelBand, spanDirection: nil
        )
        let overlap = max(0, min(apSpan.right, candidateSpan.right) - max(apSpan.left, candidateSpan.left))
        let apSpanLength = max(1, apSpan.right - apSpan.left)
        return min(1.0, Double(overlap) / Double(apSpanLength))
    }

    private static func overlaps(channel: Int, other: APInfo, band: String) -> Bool {
        overlapFactor(channel: channel, other: other, band: band) > 0
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
