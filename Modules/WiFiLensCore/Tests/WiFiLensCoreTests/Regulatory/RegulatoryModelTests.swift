import Testing
import Foundation
@testable import WiFiLensCore

// MARK: - RegulatoryDomain

struct RegulatoryDomainTests {

    @Test func allCasesCount() {
        #expect(RegulatoryDomain.allCases.count == 5)
    }

    @Test func displayNameNonEmpty() {
        for domain in RegulatoryDomain.allCases {
            #expect(!domain.displayName.isEmpty)
        }
    }

    @Test func fromLocaleRegion_US() {
        #expect(RegulatoryDomain.from(localeRegionCode: "US") == .US)
        #expect(RegulatoryDomain.from(localeRegionCode: "CA") == .US)
        #expect(RegulatoryDomain.from(localeRegionCode: "MX") == .US)
    }

    @Test func fromLocaleRegion_JP() {
        #expect(RegulatoryDomain.from(localeRegionCode: "JP") == .JP)
    }

    @Test func fromLocaleRegion_CN() {
        #expect(RegulatoryDomain.from(localeRegionCode: "CN") == .CN)
    }

    @Test func fromLocaleRegion_EU() {
        #expect(RegulatoryDomain.from(localeRegionCode: "GB") == .EU)
        #expect(RegulatoryDomain.from(localeRegionCode: "DE") == .EU)
        #expect(RegulatoryDomain.from(localeRegionCode: "FR") == .EU)
        #expect(RegulatoryDomain.from(localeRegionCode: "NO") == .EU)
        #expect(RegulatoryDomain.from(localeRegionCode: "CH") == .EU)
    }

    @Test func fromLocaleRegion_nilReturnsUnknown() {
        #expect(RegulatoryDomain.from(localeRegionCode: nil) == .unknown)
    }

    @Test func fromLocaleRegion_unknownReturnsUnknown() {
        #expect(RegulatoryDomain.from(localeRegionCode: "ZZ") == .unknown)
        #expect(RegulatoryDomain.from(localeRegionCode: "AU") == .unknown)
    }

    @Test func fromLocaleRegion_caseInsensitive() {
        #expect(RegulatoryDomain.from(localeRegionCode: "us") == .US)
        #expect(RegulatoryDomain.from(localeRegionCode: "jp") == .JP)
    }

    @Test func codableRoundTrip() throws {
        let original = RegulatoryDomain.JP
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RegulatoryDomain.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - InferenceConfidence

struct InferenceConfidenceTests {

    @Test func labelNonEmpty() {
        for confidence in [InferenceConfidence.high, .medium, .low] {
            #expect(!confidence.label.isEmpty)
        }
    }

    @Test func comparisonHighGreaterThanLow() {
        #expect(InferenceConfidence.high < .low)
        #expect(InferenceConfidence.high < .medium)
        #expect(InferenceConfidence.medium < .low)
        #expect(InferenceConfidence.medium > .high)
        #expect(InferenceConfidence.low > .medium)
    }

    @Test func equalConfidences() {
        #expect(InferenceConfidence.high == .high)
        #expect(InferenceConfidence.medium == .medium)
        #expect(InferenceConfidence.low == .low)
    }
}

// MARK: - RegionSource

struct RegionSourceTests {

    @Test func descriptionFormat() {
        let source = RegionSource(
            kind: .systemLocale,
            rawValue: "JP",
            inferredDomain: .JP
        )
        #expect(source.description == "[systemLocale] raw=JP → JP")
    }

    @Test func descriptionWithUnknownDomain() {
        let source = RegionSource(
            kind: .apBeaconCountry,
            rawValue: "XX",
            inferredDomain: nil
        )
        #expect(source.description == "[apBeaconCountry] raw=XX → unknown")
    }

    @Test func userOverrideKind() {
        let source = RegionSource(
            kind: .userOverride,
            rawValue: "US",
            inferredDomain: .US
        )
        #expect(source.description == "[userOverride] raw=US → US")
    }
}

// MARK: - RegionInferenceResult

struct RegionInferenceResultTests {

    @Test func summaryWithContributions() {
        let source = RegionSource(kind: .systemLocale, rawValue: "US", inferredDomain: .US)
        let result = RegionInferenceResult(
            domain: .US,
            confidence: .high,
            contributions: [source],
            conflicts: []
        )
        #expect(result.summary.contains("Region: US"))
        #expect(result.summary.contains(result.confidence.label))
        #expect(result.summary.contains("systemLocale"))
    }

    @Test func summaryWithConflicts() {
        let conflict = RegionConflict(
            sourceA: RegionSource(kind: .systemLocale, rawValue: "JP", inferredDomain: .JP),
            sourceB: RegionSource(kind: .apBeaconCountry, rawValue: "US", inferredDomain: .US),
            resolution: "Locale and AP beacon disagree"
        )
        let result = RegionInferenceResult(
            domain: .unknown,
            confidence: .low,
            contributions: [],
            conflicts: [conflict]
        )
        #expect(result.summary.contains("disagree"))
    }
}

// MARK: - DevicePHYCapabilities

struct DevicePHYCapabilitiesTests {

    @Test func defaultCapabilities() {
        let def = DevicePHYCapabilities.default
        #expect(def.supportsAC == true)
        #expect(def.supportsN == true)
        #expect(def.supportsAX == false)
        #expect(def.supportsBE == false)
        #expect(def.supports6GHz == false)
        #expect(def.supportsDFS == true)
        #expect(def.supports160MHz == false)
    }

    @Test func phySummaryAX() {
        let caps = DevicePHYCapabilities(
            supportsAX: true, supportsAC: true, supportsN: true, supportsBE: false,
            supports6GHz: false, supportsDFS: false, supports160MHz: false
        )
        #expect(caps.phySummary == "ax/ac/n")
    }

    @Test func phySummaryBE() {
        let caps = DevicePHYCapabilities(
            supportsAX: false, supportsAC: false, supportsN: false, supportsBE: true,
            supports6GHz: false, supportsDFS: false, supports160MHz: false
        )
        #expect(caps.phySummary == "be")
    }

    @Test func phySummaryAll() {
        let caps = DevicePHYCapabilities(
            supportsAX: true, supportsAC: true, supportsN: true, supportsBE: true,
            supports6GHz: false, supportsDFS: false, supports160MHz: false
        )
        #expect(caps.phySummary == "be/ax/ac/n")
    }

    @Test func phySummaryUnknown() {
        let caps = DevicePHYCapabilities(
            supportsAX: false, supportsAC: false, supportsN: false, supportsBE: false,
            supports6GHz: false, supportsDFS: false, supports160MHz: false
        )
        #expect(caps.phySummary == "unknown")
    }
}

// MARK: - ChannelRecommendation

struct ChannelRecommendationTests {

    private func makeChannelQuality(
        channel: Int = 44,
        band: String = "5",
        score: Int = 85,
        level: ChannelQuality.QualityLevel = .good,
        isRecommended: Bool = true
    ) -> ChannelQuality {
        ChannelQuality(
            channel: channel,
            band: band,
            bandDisplay: "5 GHz",
            qualityScore: score,
            qualityLevel: level,
            apCount: 1,
            coChannelCount: 1,
            adjacentCount: 0,
            interferenceScore: 15,
            overlapLevel: .low,
            strongestNeighborRSSI: -50,
            isRecommended: isRecommended,
            isCurrentChannel: false,
            showInSimpleView: true
        )
    }

    @Test func initFromChannelQuality() {
        let rf = makeChannelQuality()
        let rec = ChannelRecommendation(from: rf)
        #expect(rec.channel == 44)
        #expect(rec.band == "5")
        #expect(rec.bandDisplay == "5 GHz")
        #expect(rec.rfScore == 85)
        #expect(rec.rfLevel == .good)
        #expect(rec.scoreSelected == true)
        #expect(rec.isRecommended == true)
        #expect(rec.apCount == 1)
    }

    @Test func computedID() {
        let rf = makeChannelQuality(channel: 6, band: "24")
        let rec = ChannelRecommendation(from: rf)
        #expect(rec.id == "24-6")
    }

    @Test func defaultClassification() {
        let rf = makeChannelQuality()
        let rec = ChannelRecommendation(from: rf)
        #expect(rec.classification == .recommended)
    }

    @Test func classificationOrder() {
        #expect(ChannelRecommendation.Classification.recommended.order == 2)
        #expect(ChannelRecommendation.Classification.advanced.order == 1)
        #expect(ChannelRecommendation.Classification.restricted.order == 0)
    }

    @Test func classificationDisplayNameNonEmpty() {
        for c in ChannelRecommendation.Classification.allCases {
            #expect(!c.displayName.isEmpty)
        }
    }

    @Test func defaultDeviceCompatible() {
        let rf = makeChannelQuality()
        let rec = ChannelRecommendation(from: rf)
        #expect(rec.deviceCompatible == true)
        #expect(rec.deviceIncompatibilityReason == nil)
    }

    @Test func mutableProperties() {
        let rf = makeChannelQuality()
        var rec = ChannelRecommendation(from: rf)
        rec.classification = .restricted
        rec.scoreSelected = true
        rec.deviceCompatible = false
        rec.deviceIncompatibilityReason = "DFS required"
        rec.restrictionReasons = [ChannelRecommendation.RestrictionReason(code: "DFS", description: "DFS channel")]
        #expect(rec.classification == .restricted)
        #expect(rec.isRecommended == false)
        #expect(rec.deviceCompatible == false)
        #expect(rec.deviceIncompatibilityReason == "DFS required")
        #expect(rec.restrictionReasons.count == 1)
        #expect(rec.restrictionReasons[0].code == "DFS")
    }

    @Test func recommendationAvailabilityDetectsAvailableRecommendations() {
        let rec = ChannelRecommendation(from: makeChannelQuality(isRecommended: true))
        #expect(ChannelRecommendationAvailability.from([rec]) == .available)
    }

    @Test func recommendationAvailabilityDetectsCurrentGoodEnough() {
        var current = ChannelRecommendation(from: makeChannelQuality(isRecommended: false))
        current.isCurrentChannel = true
        current.recommendationState = .currentGoodEnough
        #expect(ChannelRecommendationAvailability.from([current]) == .currentGoodEnough)
    }

    @Test func recommendationAvailabilityDetectsTargetUnknown() {
        var current = ChannelRecommendation(from: makeChannelQuality(isRecommended: false))
        current.isCurrentChannel = true
        current.recommendationConfidence = .unknown
        current.recommendationState = .targetUnknown
        #expect(ChannelRecommendationAvailability.from([current]) == .targetUnknown)
    }

    @Test func recommendationAvailabilityDetectsRegulatoryFiltered() {
        var candidate = ChannelRecommendation(from: makeChannelQuality(isRecommended: true))
        candidate.scoreSelected = true
        candidate.classification = .advanced
        #expect(ChannelRecommendationAvailability.from([candidate]) == .regulatoryFiltered)
    }

    @Test func recommendationAvailabilityDefaultsToNoSignificantImprovement() {
        var current = ChannelRecommendation(from: makeChannelQuality(isRecommended: false))
        current.isCurrentChannel = true
        current.recommendationConfidence = .exact
        current.recommendationState = .insufficientImprovement
        #expect(ChannelRecommendationAvailability.from([current]) == .noSignificantImprovement)
    }
}

// MARK: - RecommendationReasonCalculator

struct RecommendationReasonCalculatorTests {

    /// Builds a ChannelRecommendation whose non-targeted reason families are
    /// neutral by default (apCount 3 → no congestion reason, adjacentCount 2 →
    /// no low-overlap reason, interferenceScore 20 → no interference reason,
    /// not current, no restrictions), so tests can assert exact reason arrays.
    private func recommendation(
        channel: Int = 44,
        band: String = "5",
        score: Int = 85,
        apCount: Int = 3,
        coChannelCount: Int = 3,
        adjacentCount: Int = 2,
        interferenceScore: Int = 20,
        overlapLevel: ChannelQuality.OverlapLevel = .low,
        isCurrentChannel: Bool = false,
        scoreSelected: Bool = false,
        classification: ChannelRecommendation.Classification = .recommended,
        restrictions: [ChannelRecommendation.RestrictionReason] = []
    ) -> ChannelRecommendation {
        var rec = ChannelRecommendation(from: ChannelQuality(
            channel: channel,
            band: band,
            bandDisplay: band == "24" ? "2.4 GHz" : "5 GHz",
            qualityScore: score,
            qualityLevel: .from(score: score),
            apCount: apCount,
            coChannelCount: coChannelCount,
            adjacentCount: adjacentCount,
            interferenceScore: interferenceScore,
            overlapLevel: overlapLevel,
            strongestNeighborRSSI: -60,
            isRecommended: false,
            isCurrentChannel: isCurrentChannel,
            showInSimpleView: true
        ))
        rec.scoreSelected = scoreSelected
        rec.classification = classification
        rec.restrictionReasons = restrictions
        return rec
    }

    // MARK: - Congestion family

    @Test("Congestion family: no APs selects clearSpectrum")
    func congestionClearSpectrum() throws {
        let out = RecommendationReasonCalculator.compute(for: [recommendation(apCount: 0)])
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.clearSpectrum])
    }

    @Test("Congestion family: 1-2 APs selects lowCongestion")
    func congestionLow() throws {
        let out = RecommendationReasonCalculator.compute(for: [recommendation(apCount: 2)])
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.lowCongestion])
    }

    @Test("Congestion family: 6+ APs on a non-recommended channel selects congested")
    func congestionHigh() throws {
        let out = RecommendationReasonCalculator.compute(for: [recommendation(apCount: 6)])
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.congested])
    }

    @Test("Congestion family: 6+ APs on a recommended channel emits no congestion reason")
    func congestionSuppressedWhenRecommended() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(apCount: 6, scoreSelected: true)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [])
    }

    // MARK: - Overlap family

    @Test("Overlap family: low overlap with sparse adjacency selects lowOverlap")
    func overlapLow() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(adjacentCount: 1)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.lowOverlap])
    }

    @Test("Overlap family: high overlap on a non-recommended channel selects highOverlap")
    func overlapHigh() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(overlapLevel: .high)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.highOverlap])
    }

    @Test("Overlap family: high overlap on a recommended channel emits no overlap reason")
    func overlapSuppressedWhenRecommended() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(overlapLevel: .high, scoreSelected: true)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [])
    }

    // MARK: - Interference family

    @Test("Interference family: score ≤ 15 selects lowInterference")
    func interferenceLow() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(interferenceScore: 15)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.lowInterference])
    }

    @Test("Interference family: score ≥ 40 on a non-recommended channel selects highInterference")
    func interferenceHigh() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(interferenceScore: 40)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.highInterference])
    }

    @Test("Interference family: score ≥ 40 on a recommended channel emits no interference reason")
    func interferenceSuppressedWhenRecommended() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(interferenceScore: 40, scoreSelected: true)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [])
    }

    // MARK: - Status family

    @Test("Status family: current channel selects currentChannel")
    func statusCurrent() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(isCurrentChannel: true)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.currentChannel])
    }

    @Test("Status family: current channel with rfScore ≥ 90 also selects currentlyOptimal")
    func statusCurrentlyOptimal() throws {
        let out = RecommendationReasonCalculator.compute(
            for: [recommendation(score: 95, isCurrentChannel: true)]
        )
        let rec = try #require(out.first)
        #expect(rec.recommendationReasons == [.currentChannel, .currentlyOptimal])
    }

    // MARK: - Band preference

    @Test("Band preference: less crowded band selected when 2.4 GHz has more APs")
    func bandPreferenceWhen24GHzCrowded() throws {
        let twoFour = recommendation(channel: 6, band: "24", apCount: 5)
        let five = recommendation(channel: 36, band: "5", apCount: 3)
        let out = RecommendationReasonCalculator.compute(for: [twoFour, five])

        let rec24 = try #require(out.first { $0.band == "24" })
        #expect(rec24.recommendationReasons == [])
        let rec5 = try #require(out.first { $0.band == "5" })
        #expect(rec5.recommendationReasons == [.lessCrowdedBand])
    }

    @Test("Band preference: no reason when 2.4 GHz is not more crowded")
    func bandPreferenceAbsentWhenNotCrowded() throws {
        let twoFour = recommendation(channel: 6, band: "24", apCount: 3)
        let five = recommendation(channel: 36, band: "5", apCount: 3)
        let out = RecommendationReasonCalculator.compute(for: [twoFour, five])

        let rec5 = try #require(out.first { $0.band == "5" })
        #expect(rec5.recommendationReasons == [])
    }

    // MARK: - Regulatory caveats

    @Test("Regulatory: restriction codes map to reasons in input order")
    func regulatoryCaveats() throws {
        let rec = recommendation(restrictions: [
            .init(code: "DFS", description: "DFS channel"),
            .init(code: "INDOOR_ONLY", description: "Indoor only"),
            .init(code: "CAC_REQUIRED", description: "CAC required"),
            .init(code: "RADAR_SENSITIVE", description: "Radar sensitive"),
        ])
        let out = RecommendationReasonCalculator.compute(for: [rec])
        let computed = try #require(out.first)
        #expect(computed.recommendationReasons == [
            .dfsRequired, .indoorOnly, .cacRequired, .radarSensitive,
        ])
    }

    @Test("Regulatory: unknown restriction codes are ignored")
    func regulatoryUnknownCodeIgnored() throws {
        let rec = recommendation(restrictions: [
            .init(code: "UNKNOWN_CODE", description: "Unknown"),
        ])
        let out = RecommendationReasonCalculator.compute(for: [rec])
        let computed = try #require(out.first)
        #expect(computed.recommendationReasons == [])
    }

    // MARK: - Order-preserving deduplication (SF-13)

    @Test("Deduplication preserves first-insertion order and collapses duplicates")
    func dedupPreservesInsertionOrder() throws {
        let main = recommendation(
            channel: 44,
            band: "5",
            score: 95,
            apCount: 0,
            coChannelCount: 0,
            adjacentCount: 1,
            interferenceScore: 10,
            overlapLevel: .low,
            isCurrentChannel: true,
            scoreSelected: true,
            restrictions: [
                .init(code: "DFS", description: "DFS channel"),
                .init(code: "DFS", description: "DFS duplicate"),
                .init(code: "CAC_REQUIRED", description: "CAC channel"),
            ]
        )
        // 2.4 GHz carries more APs, so the 5 GHz channel gains band preference.
        let crowdedBand = recommendation(channel: 6, band: "24", apCount: 3)

        let expected: [RecommendationReason] = [
            .currentChannel,
            .currentlyOptimal,
            .clearSpectrum,
            .lowOverlap,
            .lowInterference,
            .lessCrowdedBand,
            .dfsRequired,
            .cacRequired,
        ]

        let out = RecommendationReasonCalculator.compute(for: [main, crowdedBand])
        let rec = try #require(out.first { $0.band == "5" && $0.channel == 44 })
        #expect(rec.recommendationReasons == expected)
        // Duplicate DFS codes collapse to a single reason at its first position.
        #expect(rec.recommendationReasons.filter { $0 == .dfsRequired }.count == 1)

        // Deterministic across repeated computation.
        let rerun = RecommendationReasonCalculator.compute(for: [main, crowdedBand])
        let rerunRec = try #require(rerun.first { $0.band == "5" && $0.channel == 44 })
        #expect(rerunRec.recommendationReasons == expected)
    }
}
