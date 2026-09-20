import Testing
@testable import WiFi_Lens

struct ChannelQualityCalculatorTests {

    private enum TestChannelWidth: String {
        case mhz20 = "20"
        case mhz40 = "40"
        case mhz80 = "80"
        case mhz160 = "160"
    }

    private func ap(
        _ channel: Int,
        _ rssi: Int,
        width: TestChannelWidth = .mhz20,
        band: ChannelBand = .band5GHz,
        bssid: String? = nil,
        ssid: String? = nil
    ) -> ChannelQualityCalculator.APInfo {
        ChannelQualityCalculator.APInfo(
            channel: channel,
            rssi: rssi,
            channelWidth: width.rawValue,
            band: band.id,
            bssid: bssid,
            ssid: ssid
        )
    }

    // MARK: - Scoring formula

    @Test func singleAP20MHz5GHz() async throws {
        // ch 44, rssi -50, 20 MHz, 5 GHz
        // rssiWeight = (50)/70 = 0.714..., widthMul=1.0, bandMul=1.0, overlap=1.0
        // penalty = 1.0 * 0.714 * 1.0 * 1.0 * 18.0 ≈ 12.9 → 13, score = 87
        let result = ChannelQualityCalculator.compute(aps: [ap(44, -50)], currentChannel: nil)
        #expect(result.first(where: { $0.channel == 44 })?.qualityScore == 87)
        #expect(result.first(where: { $0.channel == 44 })?.qualityLevel == .good)
    }

    @Test func multipleCoChannelAPsAdditivePenalty() async throws {
        // Two identical 20 MHz APs on ch 44 → double penalty
        let result = ChannelQualityCalculator.compute(aps: [ap(44, -50), ap(44, -50)], currentChannel: nil)
        // Each: 13 penalty, total 26, score 74
        #expect(result.first(where: { $0.channel == 44 })?.qualityScore == 74)
        #expect(result.first(where: { $0.channel == 44 })?.qualityLevel == .good)
    }

    @Test func wideChannelMultiplier() async throws {
        // 80 MHz AP: widthMul=1.5, co-channel
        // rssiWeight = 1.0 (rssi=-30), penalty = 1.0*1.0*1.5*1.0*18.0 = 27
        let r80 = ChannelQualityCalculator.compute(aps: [ap(44, -30, width: .mhz80)], currentChannel: nil)
        #expect(r80.first(where: { $0.channel == 44 })?.qualityScore == 73)

        // 160 MHz AP: widthMul=2.0
        // penalty = 1.0*1.0*2.0*1.0*18.0 = 36
        let r160 = ChannelQualityCalculator.compute(aps: [ap(44, -30, width: .mhz160)], currentChannel: nil)
        #expect(r160.first(where: { $0.channel == 44 })?.qualityScore == 64)
    }

    @Test func nonContiguous80Plus80Uses80MHzScalarFallback() async throws {
        let width80 = ChannelQualityCalculator.compute(
            aps: [ChannelQualityCalculator.APInfo(
                channel: 44, rssi: -30, channelWidth: "80", band: "5"
            )],
            currentChannel: nil,
            supportedBands: ["5"]
        )
        let width80Plus80 = ChannelQualityCalculator.compute(
            aps: [ChannelQualityCalculator.APInfo(
                channel: 44, rssi: -30, channelWidth: "80+80", band: "5"
            )],
            currentChannel: nil,
            supportedBands: ["5"]
        )

        #expect(width80.first(where: { $0.channel == 44 })?.qualityScore ==
            width80Plus80.first(where: { $0.channel == 44 })?.qualityScore)
        #expect(width80.first(where: { $0.channel == 40 })?.qualityScore ==
            width80Plus80.first(where: { $0.channel == 40 })?.qualityScore)
    }

    @Test func band24Multiplier() async throws {
        // 2.4 GHz band: bandMul=1.8
        // rssiWeight = (50)/70 = 0.714, penalty = 1.0*0.714*1.0*1.8*18.0 ≈ 23.1 → 23, score = 77
        let r24 = ChannelQualityCalculator.compute(aps: [ap(6, -50, band: .band24GHz)], currentChannel: nil)
        #expect(r24.first(where: { $0.channel == 6 })?.qualityScore == 77)

        // Same AP on 5 GHz: bandMul=1.0, score should be higher
        let r5 = ChannelQualityCalculator.compute(aps: [ap(44, -50, band: .band5GHz)], currentChannel: nil)
        let score24 = r24.first(where: { $0.channel == 6 })!.qualityScore
        let score5 = r5.first(where: { $0.channel == 44 })!.qualityScore
        #expect(score5 > score24)
    }

    @Test func rssiEdgeCases() async throws {
        // rssi=-100: rssiWeight=0 → no penalty → score=100
        let floor = ChannelQualityCalculator.compute(aps: [ap(44, -100)], currentChannel: nil)
        #expect(floor.first(where: { $0.channel == 44 })?.qualityScore == 100)

        // rssi=-30: rssiWeight=1.0 → max penalty
        // penalty = 1.0*1.0*1.0*1.0*18.0 = 18, score = 82
        let maxRssi = ChannelQualityCalculator.compute(aps: [ap(44, -30)], currentChannel: nil)
        #expect(maxRssi.first(where: { $0.channel == 44 })?.qualityScore == 82)

        // rssi=-120 (below floor): rssiWeight clamped to 0
        let belowFloor = ChannelQualityCalculator.compute(aps: [ap(44, -120)], currentChannel: nil)
        #expect(belowFloor.first(where: { $0.channel == 44 })?.qualityScore == 100)

        // rssi=-20 (above -30): rssiWeight clamped to 1.0, same as -30
        let aboveMax = ChannelQualityCalculator.compute(aps: [ap(44, -20)], currentChannel: nil)
        #expect(aboveMax.first(where: { $0.channel == 44 })?.qualityScore == 82)
    }

    @Test func zeroAPsAllChannelsExcellent() async throws {
        let result = ChannelQualityCalculator.compute(aps: [], currentChannel: nil)
        for ch in result {
            #expect(ch.qualityScore == 100)
            #expect(ch.qualityLevel == .excellent)
        }
    }

    // MARK: - 2.4 GHz overlap factors (distance-based)

    @Test func overlap24GHz() async throws {
        // AP on ch 6 (2.4 GHz, 20 MHz, rssi=-50)
        let aps = [ap(6, -50, band: .band24GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)

        // ch 6: co-channel → score = 77
        #expect(result.first(where: { $0.channel == 6 })!.qualityScore == 77)
        // ch 1 (dist 5): overlap=0 → score=100
        #expect(result.first(where: { $0.channel == 1 })!.qualityScore == 100)
    }

    // MARK: - 5/6 GHz overlap factors (width-based)

    @Test func overlap5GHz80MHz() async throws {
        // AP on ch 44, 80 MHz → halfSpan = 80/20/2 = 2
        let aps = [ap(44, -50, width: .mhz80, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)

        // ch 44: co-channel (dist=0) → overlap=1.0
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch44.qualityScore < 100)

        // ch 40: the 80 MHz AP on ch 44 really spans (34,50); the 20 MHz
        // candidate ch 40 (38,42) overlaps 4/16 → factor 0.25 → penalty ≈5
        let ch40 = result.first(where: { $0.channel == 40 })!
        #expect(ch40.qualityScore == 95)
    }

    // MARK: - Quality level thresholds

    @Test(arguments: [
        (95, ChannelQuality.QualityLevel.excellent),
        (90, ChannelQuality.QualityLevel.excellent),
        (89, ChannelQuality.QualityLevel.good),
        (75, ChannelQuality.QualityLevel.good),
        (70, ChannelQuality.QualityLevel.good),
        (69, ChannelQuality.QualityLevel.moderate),
        (55, ChannelQuality.QualityLevel.moderate),
        (50, ChannelQuality.QualityLevel.moderate),
        (49, ChannelQuality.QualityLevel.busy),
        (35, ChannelQuality.QualityLevel.busy),
        (30, ChannelQuality.QualityLevel.busy),
        (29, ChannelQuality.QualityLevel.congested),
        (10, ChannelQuality.QualityLevel.congested),
        (0, ChannelQuality.QualityLevel.congested),
    ])
    func qualityLevelThresholds(score: Int, expected: ChannelQuality.QualityLevel) async throws {
        #expect(expected.scoreRange.contains(score))
    }

    // MARK: - Overlap level

    @Test func overlapLevel() async throws {
        // 0 APs → low
        let r0 = ChannelQualityCalculator.compute(aps: [], currentChannel: nil)
        #expect(r0.first(where: { $0.channel == 44 })!.overlapLevel == .low)
        #expect(r0.first(where: { $0.channel == 44 })!.apCount == 0)

        // 1 AP → low
        let r1 = ChannelQualityCalculator.compute(aps: [ap(44, -50)], currentChannel: nil)
        #expect(r1.first(where: { $0.channel == 44 })!.overlapLevel == .low)

        // 2 APs → moderate
        let r2 = ChannelQualityCalculator.compute(aps: [ap(44, -50), ap(44, -60)], currentChannel: nil)
        #expect(r2.first(where: { $0.channel == 44 })!.overlapLevel == .moderate)

        // 4 APs → high
        let r4 = ChannelQualityCalculator.compute(aps: [ap(44, -50), ap(44, -60), ap(44, -70), ap(44, -80)], currentChannel: nil)
        #expect(r4.first(where: { $0.channel == 44 })!.overlapLevel == .high)
    }

    // MARK: - AP count breakdown

    @Test func apCountBreakdown() async throws {
        let aps = [
            ap(44, -50, band: .band5GHz),  // co-channel
            ap(44, -60, band: .band5GHz),  // co-channel
            ap(40, -70, width: .mhz80, band: .band5GHz),  // adjacent (overlaps ch 44 via 80 MHz)
        ]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch44.coChannelCount == 2)
        #expect(ch44.apCount == 3)  // 2 co-channel + the 80 MHz AP on ch 40 (real span overlaps)
        #expect(ch44.adjacentCount == 1)
    }

    // MARK: - Current channel

    @Test func currentChannelMarking() async throws {
        let result = ChannelQualityCalculator.compute(aps: [ap(44, -50)], currentChannel: 44)
        #expect(result.first(where: { $0.channel == 44 })!.isCurrentChannel == true)
        #expect(result.first(where: { $0.channel == 40 })!.isCurrentChannel == false)
    }

    @Test func currentChannelNil() async throws {
        let result = ChannelQualityCalculator.compute(aps: [ap(44, -50)], currentChannel: nil)
        for ch in result {
            #expect(ch.isCurrentChannel == false)
        }
    }

    // MARK: - Counterfactual recommendation

    @Test func calculatorDoesNotSelectRecommendations() async throws {
        // 3 APs on different 5 GHz channels with moderate signal
        let aps = [
            ap(36, -30, band: .band5GHz),
            ap(40, -35, band: .band5GHz),
            ap(44, -40, band: .band5GHz),
        ]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        #expect(result.allSatisfy { $0.isRecommended == false })
    }

    @Test func recommendationScoreStartsAsObservedScoreWithoutTarget() async throws {
        // Six 160 MHz co-channel APs at strong RSSI → score well below 70
        let aps = (0..<6).map { _ in ap(36, -30, width: .mhz160, band: .band5GHz) }
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch36 = result.first(where: { $0.channel == 36 })!
        #expect(ch36.recommendationScore == ch36.qualityScore)
        #expect(ch36.recommendationConfidence == .unknown)
    }

    @Test func targetAPIsExcludedFromRecommendationScore() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ChannelQualityCalculator.APInfo(
                    channel: 36,
                    rssi: -30,
                    channelWidth: "20",
                    band: "5",
                    bssid: "aa:bb:cc:dd:ee:01",
                    ssid: "Home"
                )
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )
        let current = try #require(result.first { $0.channel == 36 })
        #expect(current.qualityScore < 100)
        #expect(current.recommendationScore == 100)
        #expect(current.recommendationConfidence == .exact)
    }

    @Test func externalAPStillReducesRecommendationScore() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ChannelQualityCalculator.APInfo(
                    channel: 36,
                    rssi: -30,
                    channelWidth: "20",
                    band: "5",
                    bssid: "aa:bb:cc:dd:ee:01",
                    ssid: "Home"
                ),
                ChannelQualityCalculator.APInfo(
                    channel: 36,
                    rssi: -30,
                    channelWidth: "20",
                    band: "5",
                    bssid: "aa:bb:cc:dd:ee:02",
                    ssid: "Neighbor"
                )
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )
        let current = try #require(result.first { $0.channel == 36 })
        #expect(current.qualityScore < current.recommendationScore)
        #expect(current.recommendationScore < 100)
    }

    @Test func ssidFallbackDoesNotExcludeSameSSIDAPsOnOtherChannels() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: nil,
            ssid: "Mesh",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:01", ssid: "Mesh"),
                ap(40, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:02", ssid: "Mesh"),
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )

        let current = try #require(result.first { $0.channel == 36 })
        let otherMeshAPChannel = try #require(result.first { $0.channel == 40 })
        #expect(current.recommendationConfidence == .ssidFallback)
        #expect(current.recommendationScore == 100)
        #expect(otherMeshAPChannel.recommendationScore < 100)
    }

    @Test func currentGoodEnoughSuppressesRecommendations() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:01", ssid: "Home"),
                ap(149, -80, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:02", ssid: "Neighbor"),
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )

        let current = try #require(result.first { $0.channel == 36 })
        #expect(current.recommendationState == .currentGoodEnough)
        #expect(result.allSatisfy { $0.isRecommended == false })
    }

    @Test func insufficientImprovementSuppressesRecommendations() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:01", ssid: "Home"),
                ap(36, -50, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:02", ssid: "Neighbor"),
                ap(36, -50, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:03", ssid: "Neighbor2"),
                ap(40, -35, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:04", ssid: "Neighbor3"),
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )

        let current = try #require(result.first { $0.channel == 36 })
        let candidate = try #require(result.first { $0.channel == 40 })
        #expect(current.recommendationScore < 80)
        #expect(candidate.recommendationScore - current.recommendationScore < 10)
        #expect(candidate.isRecommended == false)
        #expect(candidate.recommendationState == .insufficientImprovement)
    }

    @Test func recommendationSelectionIsCappedAtTwoPerBand() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 36
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:01", ssid: "Home"),
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:02", ssid: "Neighbor"),
                ap(36, -30, band: .band5GHz, bssid: "aa:bb:cc:dd:ee:03", ssid: "Neighbor2"),
            ],
            currentChannel: 36,
            supportedBands: ["5"],
            targetAP: target
        )

        #expect(result.filter(\.isRecommended).count == 2)
    }

    @Test func recommendationsAreSelectedIndependentlyPerBand() async throws {
        let target = ChannelQualityCalculator.TargetAP(
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "Home",
            channel: 1
        )
        let result = ChannelQualityCalculator.compute(
            aps: [
                ap(1, -30, band: .band24GHz, bssid: "aa:bb:cc:dd:ee:01", ssid: "Home"),
                ap(1, -30, band: .band24GHz, bssid: "aa:bb:cc:dd:ee:02", ssid: "Neighbor24A"),
                ap(1, -30, band: .band24GHz, bssid: "aa:bb:cc:dd:ee:03", ssid: "Neighbor24B"),
                ap(1, -30, band: .band6GHz, bssid: "aa:bb:cc:dd:ee:04", ssid: "Neighbor6A"),
                ap(1, -30, band: .band6GHz, bssid: "aa:bb:cc:dd:ee:05", ssid: "Neighbor6B"),
            ],
            currentChannel: 1,
            supportedBands: ["24", "6"],
            targetAP: target
        )

        #expect(result.filter { $0.band == "24" && $0.isRecommended }.count == 2)
        #expect(result.filter { $0.band == "6" && $0.isRecommended }.count == 2)
    }

    // MARK: - Simple view filtering

    @Test func simpleViewShowsCurrentRecommendedAndOccupied() async throws {
        let aps = [
            ap(36, -50, band: .band5GHz),
            ap(40, -50, band: .band5GHz),
            ap(44, -50, band: .band5GHz),
        ]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: 48)
        // ch 48: current → shown
        #expect(result.first(where: { $0.channel == 48 })!.showInSimpleView == true)
        // ch 36: has AP → shown
        #expect(result.first(where: { $0.channel == 36 })!.showInSimpleView == true)
        // ch 56: no AP and not current → hidden unless counterfactual scoring selects it
        let ch56 = result.first(where: { $0.channel == 56 })!
        #expect(ch56.showInSimpleView == false)
    }

    // MARK: - Sort order

    @Test func currentChannelSortedFirst() async throws {
        let result = ChannelQualityCalculator.compute(aps: [ap(40, -50)], currentChannel: 44)
        #expect(result.first!.channel == 44)  // current channel first
        #expect(result.first!.isCurrentChannel == true)
    }

    // MARK: - Interference score field

    @Test func interferenceScoreField() async throws {
        let result = ChannelQualityCalculator.compute(aps: [ap(44, -50)], currentChannel: nil)
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch44.interferenceScore > 0)
        #expect(ch44.qualityScore == 100 - ch44.interferenceScore)
    }

    // MARK: - Strongest neighbor RSSI

    @Test func strongestNeighborRSSI() async throws {
        let aps = [ap(44, -50), ap(44, -70)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch44.strongestNeighborRSSI == -50)  // strongest among overlapping
        // Non-overlapping channel gets default -100
        let ch40 = result.first(where: { $0.channel == 40 })!
        #expect(ch40.strongestNeighborRSSI == -100)
    }

    // MARK: - NH-14: real wide-channel overlap (5/6 GHz)

    @Test func overlap5GHz40MHzDirectional() async throws {
        // 40 MHz AP on ch 44 spans (42,50): ch 48 overlaps (4/8 = 0.5), ch 40 does not.
        let aps = [ap(44, -50, width: .mhz40, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch48 = result.first(where: { $0.channel == 48 })!
        let ch40 = result.first(where: { $0.channel == 40 })!
        #expect(ch48.qualityScore == 92)  // 0.5 * 0.714 * 1.2 * 18 ≈ 7.7 → 8
        #expect(ch40.qualityScore == 100) // block is offset upward, no overlap
    }

    @Test func overlap5GHz160MHzAdjacent() async throws {
        // 160 MHz AP on ch 36 spans (34,66): ch 40/44/48 each overlap 4/32 = 0.125.
        let aps = [ap(36, -50, width: .mhz160, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        for ch in [40, 44, 48] {
            let c = result.first(where: { $0.channel == ch })!
            #expect(c.qualityScore == 97) // 0.125 * 0.714 * 2.0 * 18 ≈ 3.2 → 3
        }
    }

    @Test func overlap5GHz80MHzBlockSeam() async throws {
        // 80 MHz AP on ch 48 spans (34,50); ch 52 is a half-open seam (no overlap),
        // ch 44 overlaps 4/16 = 0.25.
        let aps = [ap(48, -50, width: .mhz80, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch52 = result.first(where: { $0.channel == 52 })!
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch52.qualityScore == 100)
        #expect(ch44.qualityScore == 95)
    }

    @Test func overlap6GHzWideBlock() async throws {
        // 6 GHz uses IEEE 802.11ax containing blocks: an 80 MHz AP whose
        // primary is ch 41 (a non-lowest primary) still spans (31,47).
        let aps = [ap(41, -50, width: .mhz80, band: .band6GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch37 = result.first(where: { $0.channel == 37 && $0.band == "6" })!
        let ch45 = result.first(where: { $0.channel == 45 && $0.band == "6" })!
        let ch29 = result.first(where: { $0.channel == 29 && $0.band == "6" })!
        #expect(ch37.qualityScore == 95)  // 4/16 = 0.25
        #expect(ch45.qualityScore == 95)  // 4/16 = 0.25
        #expect(ch29.qualityScore == 100) // outside the block
    }

    @Test func overlap6GHzEdgeChannel() async throws {
        // 80 MHz on ch 1 spans (-1,15), crossing the band edge; the adjacent
        // ch 5 still overlaps 4/16 = 0.25. (ch 1 itself is co-channel → 1.0.)
        let aps = [ap(1, -50, width: .mhz80, band: .band6GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch5 = result.first(where: { $0.channel == 5 && $0.band == "6" })!
        #expect(ch5.qualityScore == 95)
    }

    @Test func overlap24GHzDistanceTable() async throws {
        // 2.4 GHz must keep the empirical distance heuristic (5 MHz spacing).
        let aps = [ap(6, -50, width: .mhz20, band: .band24GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let expected: [Int: Int] = [5: 81, 4: 87, 3: 93, 2: 97, 1: 100]
        for (ch, score) in expected {
            #expect(result.first(where: { $0.channel == ch && $0.band == "24" })!.qualityScore == score)
        }
    }

    @Test func overlap20MHzAdjacentIsZero() async throws {
        // 20 MHz AP on ch 36: adjacent 20 MHz ch 40 / ch 44 do not overlap.
        let aps = [ap(36, -50, width: .mhz20, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch40 = result.first(where: { $0.channel == 40 })!
        let ch44 = result.first(where: { $0.channel == 44 })!
        #expect(ch40.qualityScore == 100)
        #expect(ch44.qualityScore == 100)
    }

    @Test func wideOverlapConsistency() async throws {
        // One 80 MHz AP on ch 44: ch 40 must be penalized, counted, and reported
        // as the strongest neighbor (overlapFactor and overlaps stay in sync).
        let aps = [ap(44, -50, width: .mhz80, band: .band5GHz)]
        let result = ChannelQualityCalculator.compute(aps: aps, currentChannel: nil)
        let ch40 = result.first(where: { $0.channel == 40 })!
        #expect(ch40.qualityScore < 100)
        #expect(ch40.apCount == 1)
        #expect(ch40.strongestNeighborRSSI == -50)
    }
}
