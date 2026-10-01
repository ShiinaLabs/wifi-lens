import Foundation
import Testing
@testable import WiFiLensCore

@Suite struct RegulatoryFilterTests {

    // Helper: build a standard US filter input with no device restrictions
    private func usFilterInput(
        rfResults: [ChannelQuality],
        deviceSupportedChannels: Set<String>? = nil
    ) -> RegulatoryFilter.FilterInput {
        // Build a generous device channel set
        var devChannels = Set<String>()
        for ch in 1...13 { devChannels.insert("1-\(ch)") }
        for ch in stride(from: 36, through: 144, by: 4) { devChannels.insert("2-\(ch)") }
        for ch in stride(from: 149, through: 165, by: 4) { devChannels.insert("2-\(ch)") }

        let inference = RegionInferenceResult(
            domain: .US,
            confidence: .high,
            contributions: [
                RegionSource(kind: .systemLocale, rawValue: "US", inferredDomain: .US),
                RegionSource(kind: .supportedChannels, rawValue: "test", inferredDomain: .US),
            ],
            conflicts: []
        )

        return RegulatoryFilter.FilterInput(
            rfResults: rfResults,
            inferredRegion: inference,
            deviceSupportedChannels: deviceSupportedChannels ?? devChannels,
            deviceCapabilities: .default,
            userClassificationOverrides: nil
        )
    }

    // Helper: create a ChannelQuality with given score
    private func makeQuality(channel: Int, band: String, score: Int, apCount: Int = 0) -> ChannelQuality {
        var q = ChannelQuality(
            channel: channel,
            band: band,
            bandDisplay: band == "24" ? "2.4 GHz" : band == "5" ? "5 GHz" : "6 GHz",
            qualityScore: score,
            qualityLevel: .from(score: score),
            apCount: apCount,
            coChannelCount: 0,
            adjacentCount: 0,
            interferenceScore: max(0, 100 - score),
            overlapLevel: apCount <= 1 ? .low : apCount <= 3 ? .moderate : .high,
            strongestNeighborRSSI: -80
        )
        q.isRecommended = score >= 70
        q.recommendationScore = score
        q.recommendationLevel = .from(score: score)
        q.recommendationConfidence = .exact
        q.recommendationState = q.isRecommended ? .recommended : .insufficientImprovement
        q.isCurrentChannel = false
        q.showInSimpleView = true
        return q
    }

    // MARK: - Basic classification

    @Test("US-legal non-DFS channels are classified as recommended")
    func usLegalChannelsRecommended() {
        let rf = [
            makeQuality(channel: 36, band: "5", score: 95),
            makeQuality(channel: 149, band: "5", score: 88),
            makeQuality(channel: 6, band: "24", score: 72),
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        for rec in result {
            #expect(rec.classification == .recommended,
                     "Channel \(rec.channel) (\(rec.band)) should be recommended, got \(rec.classification.rawValue)")
        }
    }

    @Test("DFS channels are classified as advanced")
    func dfsChannelsAdvanced() {
        let rf = [
            makeQuality(channel: 52, band: "5", score: 100),
            makeQuality(channel: 100, band: "5", score: 95),
            makeQuality(channel: 36, band: "5", score: 80),
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        let ch52 = result.first(where: { $0.channel == 52 })!
        let ch100 = result.first(where: { $0.channel == 100 })!
        let ch36 = result.first(where: { $0.channel == 36 })!

        #expect(ch52.classification == .advanced)
        #expect(ch100.classification == .advanced)
        #expect(ch36.classification == .recommended)

        #expect(ch52.restrictionReasons.contains(where: { $0.code == "DFS" }))
        #expect(ch100.restrictionReasons.contains(where: { $0.code == "DFS" }))
    }

    @Test("DFS score-selected channels are not final recommendations")
    func dfsScoreSelectedChannelsAreNotFinalRecommendations() {
        let rf = [
            makeQuality(channel: 52, band: "5", score: 100),
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)
        let ch52 = result.first(where: { $0.channel == 52 })!

        #expect(ch52.scoreSelected == true)
        #expect(ch52.classification == .advanced)
        #expect(ch52.isRecommended == false)
    }

    @Test("Channels not in region are classified as restricted")
    func channelNotInRegionBlocked() {
        let rf = [
            makeQuality(channel: 14, band: "24", score: 100),  // JP-only
            makeQuality(channel: 120, band: "5", score: 95),   // DFS but still US-legal
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        let ch14 = result.first(where: { $0.channel == 14 })!
        #expect(ch14.classification == .restricted)
        #expect(ch14.restrictionReasons.contains(where: { $0.code == "REGION_BLOCKED" }))
    }

    // MARK: - RF score preservation

    @Test("RF scores are preserved regardless of classification")
    func rfScorePreserved() {
        let rf = [
            makeQuality(channel: 52, band: "5", score: 100, apCount: 0),   // DFS → advanced
            makeQuality(channel: 14, band: "24", score: 95, apCount: 0),   // blocked → restricted
            makeQuality(channel: 36, band: "5", score: 80, apCount: 2),    // recommended
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        #expect(result.first(where: { $0.channel == 52 })!.rfScore == 100)
        #expect(result.first(where: { $0.channel == 14 })!.rfScore == 95)
        #expect(result.first(where: { $0.channel == 36 })!.rfScore == 80)
    }

    // MARK: - Sort order

    @Test("Results sorted: recommended → advanced → restricted, then by recommendation score descending")
    func sortOrderRespectsClassificationThenRecommendationScore() {
        let rf = [
            makeQuality(channel: 36, band: "5", score: 50),   // recommended
            makeQuality(channel: 40, band: "5", score: 90),   // recommended (higher score)
            makeQuality(channel: 52, band: "5", score: 100),  // advanced (DFS)
            makeQuality(channel: 60, band: "5", score: 30),   // advanced (DFS, lower score)
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        // Order should be: 40 (rec, 90) → 36 (rec, 50) → 52 (adv, 100) → 60 (adv, 30)
        #expect(result[0].channel == 40, "First should be channel 40 (rec, score 90), got \(result[0].channel)")
        #expect(result[1].channel == 36, "Second should be channel 36 (rec, score 50), got \(result[1].channel)")
        #expect(result[2].channel == 52, "Third should be channel 52 (adv, score 100), got \(result[2].channel)")
        #expect(result[3].channel == 60, "Fourth should be channel 60 (adv, score 30), got \(result[3].channel)")
    }

    // MARK: - Low confidence region

    @Test("Low confidence region inference downgrades recommended to advanced")
    func lowConfidenceDowngradesRecommended() {
        let rf = [makeQuality(channel: 36, band: "5", score: 95)]
        var input = usFilterInput(rfResults: rf)
        // Override inference to low confidence
        input = RegulatoryFilter.FilterInput(
            rfResults: input.rfResults,
            inferredRegion: RegionInferenceResult(
                domain: .US,
                confidence: .low,
                contributions: [
                    RegionSource(kind: .systemLocale, rawValue: "US", inferredDomain: .US),
                ],
                conflicts: []
            ),
            deviceSupportedChannels: input.deviceSupportedChannels,
            deviceCapabilities: input.deviceCapabilities,
            userClassificationOverrides: nil
        )
        let result = RegulatoryFilter.apply(to: input)
        #expect(result[0].classification == .advanced)
        #expect(result[0].restrictionReasons.contains(where: { $0.code == "REGION_LOW_CONFIDENCE" }))
    }

    // MARK: - Device compatibility

    @Test("Channel not in device supported set is restricted")
    func deviceIncompatibleChannel() {
        let rf = [makeQuality(channel: 36, band: "5", score: 95)]
        // Provide device channels that do NOT include channel 36 on band 5
        let limitedChannels: Set<String> = ["1-6", "1-11", "2-40", "2-44"]
        let input = usFilterInput(rfResults: rf, deviceSupportedChannels: limitedChannels)
        let result = RegulatoryFilter.apply(to: input)
        #expect(result[0].classification == .restricted)
        #expect(result[0].deviceCompatible == false)
    }

    // MARK: - Restriction reasons

    @Test("Restriction reasons accumulate correctly")
    func multipleRestrictionReasons() {
        let rf = [makeQuality(channel: 52, band: "5", score: 95)]
        var input = usFilterInput(rfResults: rf)
        input = RegulatoryFilter.FilterInput(
            rfResults: input.rfResults,
            inferredRegion: RegionInferenceResult(
                domain: .US,
                confidence: .low,
                contributions: [],
                conflicts: []
            ),
            deviceSupportedChannels: input.deviceSupportedChannels,
            deviceCapabilities: input.deviceCapabilities,
            userClassificationOverrides: nil
        )
        let result = RegulatoryFilter.apply(to: input)
        let ch52 = result[0]
        // Should have at least DFS and REGION_LOW_CONFIDENCE
        #expect(ch52.restrictionReasons.contains(where: { $0.code == "DFS" }))
        #expect(ch52.restrictionReasons.contains(where: { $0.code == "REGION_LOW_CONFIDENCE" }))
        // DFS channels also get RADAR_SENSITIVE and CAC_REQUIRED
        #expect(ch52.restrictionReasons.contains(where: { $0.code == "RADAR_SENSITIVE" }))
        #expect(ch52.restrictionReasons.contains(where: { $0.code == "CAC_REQUIRED" }))
    }

    // MARK: - User classification overrides

    @Test("User override classification is applied")
    func userOverrideClassification() {
        let rf = [makeQuality(channel: 36, band: "5", score: 95)]
        var input = usFilterInput(rfResults: rf)
        input = RegulatoryFilter.FilterInput(
            rfResults: input.rfResults,
            inferredRegion: input.inferredRegion,
            deviceSupportedChannels: input.deviceSupportedChannels,
            deviceCapabilities: input.deviceCapabilities,
            userClassificationOverrides: ["5-36": .restricted]
        )
        let result = RegulatoryFilter.apply(to: input)
        #expect(result[0].classification == .restricted)
        #expect(result[0].restrictionReasons.contains(where: { $0.code == "USER_OVERRIDE" }))
    }

    // MARK: - Unknown region

    @Test("Unknown region marks all channels as restricted")
    func unknownRegionRestrictsAll() {
        let rf = [
            makeQuality(channel: 36, band: "5", score: 95),
            makeQuality(channel: 6, band: "24", score: 90),
        ]
        var input = usFilterInput(rfResults: rf)
        input = RegulatoryFilter.FilterInput(
            rfResults: input.rfResults,
            inferredRegion: RegionInferenceResult(
                domain: .unknown,
                confidence: .low,
                contributions: [],
                conflicts: []
            ),
            deviceSupportedChannels: input.deviceSupportedChannels,
            deviceCapabilities: input.deviceCapabilities,
            userClassificationOverrides: nil
        )
        let result = RegulatoryFilter.apply(to: input)
        for rec in result {
            #expect(rec.classification == .restricted,
                     "Channel \(rec.channel) should be restricted in unknown region")
        }
    }

    // MARK: - showInSimpleView

    @Test("Restricted channels are hidden from simple view")
    func restrictedChannelsHiddenFromSimpleView() {
        let rf = [
            makeQuality(channel: 36, band: "5", score: 95),
            makeQuality(channel: 14, band: "24", score: 100),
        ]
        let input = usFilterInput(rfResults: rf)
        let result = RegulatoryFilter.apply(to: input)

        #expect(result.first(where: { $0.channel == 36 })!.showInSimpleView == true)
        #expect(result.first(where: { $0.channel == 14 })!.showInSimpleView == false)
    }
}
