import Foundation
import Testing
@testable import WiFiLensCore

@Suite("Observation Analyzers")
struct AnalyzerTests {
    @Test("WiFiQualityEvaluator: strong signal + low latency = good")
    func strongGood() {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Test", bssid: "AA:BB", channel: 36,
            rssi: -45, isConnected: true, isWiFiPowerOn: true
        )
        let latency = GatewayLatencyResult(timestamp: Date(), latencyMs: 20)
        let result = WiFiQualityEvaluator.evaluate(currentStatus: status, gatewayLatency: latency)
        #expect(result.level == .good)
    }

    @Test("WiFiQualityEvaluator: weak signal = poor")
    func weakPoor() {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Test", bssid: "AA:BB", channel: 6,
            rssi: -80, isConnected: true, isWiFiPowerOn: true
        )
        let result = WiFiQualityEvaluator.evaluate(currentStatus: status)
        #expect(result.level == .poor)
    }

    @Test("DiagnosticEvaluator: excellent when strong + WPA3 + good channel")
    func excellentDiagnostic() {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Net", bssid: "AA:BB", channel: 36,
            rssi: -45, security: "WPA3", isConnected: true, isWiFiPowerOn: true
        )
        let ch = ChannelQuality(
            channel: 36, band: "5", bandDisplay: "5 GHz",
            qualityScore: 85, qualityLevel: .good,
            apCount: 1, coChannelCount: 0, adjacentCount: 1,
            interferenceScore: 15, overlapLevel: .low,
            strongestNeighborRSSI: -70, isCurrentChannel: true
        )
        let result = DiagnosticEvaluator.evaluate(
            currentStatus: status, channelAnalysis: [ch]
        )
        #expect(result.severity == .excellent)
    }

    @Test("DiagnosticEvaluator: congested message formats integer inputs")
    func congestedDiagnosticFormatsIntegers() {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Net", bssid: "AA:BB", channel: 6,
            rssi: -60, security: "WPA3", isConnected: true, isWiFiPowerOn: true
        )
        let ch = ChannelQuality(
            channel: 6, band: "24", bandDisplay: "2.4 GHz",
            qualityScore: 35, qualityLevel: .congested,
            apCount: 8, coChannelCount: 5, adjacentCount: 3,
            interferenceScore: 65, overlapLevel: .high,
            strongestNeighborRSSI: -50, isCurrentChannel: true
        )
        let result = DiagnosticEvaluator.evaluate(
            currentStatus: status, channelAnalysis: [ch], channelRecommendations: []
        )
        #expect(result.severity == .warning)
        #expect(result.message.contains("6"))
        #expect(result.message.contains("8"))
        #expect(!result.message.contains("%1$"))
        #expect(!result.message.contains("observation.diagnosis"))
    }

    @Test("DiagnosticEvaluator: congested message includes recommended channels")
    func congestedDiagnosticIncludesRecommendations() {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Net", bssid: "AA:BB", channel: 6,
            rssi: -60, security: "WPA3", isConnected: true, isWiFiPowerOn: true
        )
        let ch = ChannelQuality(
            channel: 6, band: "24", bandDisplay: "2.4 GHz",
            qualityScore: 35, qualityLevel: .congested,
            apCount: 8, coChannelCount: 5, adjacentCount: 3,
            interferenceScore: 65, overlapLevel: .high,
            strongestNeighborRSSI: -50, isCurrentChannel: true
        )
        let recommendationAQuality = ChannelQuality(
            channel: 1, band: "24", bandDisplay: "2.4 GHz",
            qualityScore: 82, qualityLevel: .good,
            apCount: 1, coChannelCount: 1, adjacentCount: 0,
            interferenceScore: 12, overlapLevel: .low,
            strongestNeighborRSSI: -72
        )
        let recommendationBQuality = ChannelQuality(
            channel: 11, band: "24", bandDisplay: "2.4 GHz",
            qualityScore: 79, qualityLevel: .good,
            apCount: 2, coChannelCount: 1, adjacentCount: 1,
            interferenceScore: 18, overlapLevel: .low,
            strongestNeighborRSSI: -68
        )
        var recommendationA = ChannelRecommendation(from: recommendationAQuality)
        recommendationA.scoreSelected = true
        recommendationA.classification = .recommended
        var recommendationB = ChannelRecommendation(from: recommendationBQuality)
        recommendationB.scoreSelected = true
        recommendationB.classification = .recommended

        let result = DiagnosticEvaluator.evaluate(
            currentStatus: status,
            channelAnalysis: [ch],
            channelRecommendations: [recommendationA, recommendationB]
        )

        #expect(result.severity == .warning)
        #expect(result.message.contains("1 / 11"))
    }
}

@Suite("ChannelOccupancyAnalyzer")
struct ChannelOccupancyAnalyzerTests {

    // MARK: - Fixtures

    private func observation(
        ssid: String = "TestNet",
        bssid: String,
        rssi: Int,
        channel: Int,
        band: ChannelBand = .band5GHz,
        widthMHz: Int = 20,
        spanDirection: SpanDirection? = nil,
        capabilitiesWidth: Int? = nil
    ) -> WiFiNetworkObservation {
        let ch = WiFiChannel(
            band: band,
            channelNumber: channel,
            channelWidthMHz: widthMHz,
            spanDirection: spanDirection
        )
        return WiFiNetworkObservation(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: ch,
            capabilities: WiFiNetworkCapabilities.emptyWithWidth(capabilitiesWidth ?? widthMHz)
        )
    }

    private func snapshot(_ networks: [WiFiNetworkObservation]) -> WiFiEnvironmentSnapshot {
        WiFiEnvironmentSnapshot(
            timestamp: Date(),
            interfaceName: nil,
            networks: networks,
            scanDurationMs: nil,
            error: nil
        )
    }

    // MARK: - BSSID + band deduplication

    @Test("ChannelOccupancyAnalyzer: duplicate BSSID on the same band keeps the strongest RSSI")
    func sameBSSIDSameBandKeepsStrongestRSSI() throws {
        // Weaker scan entry first, stronger second — dedup must keep the stronger one.
        let aps = [
            observation(bssid: "AA:BB:CC:DD:EE:01", rssi: -70, channel: 36),
            observation(bssid: "AA:BB:CC:DD:EE:01", rssi: -45, channel: 36),
        ]
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot(aps),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch36 = try #require(result.first { $0.channel == 36 && $0.band == "5" })
        #expect(ch36.apCount == 1)                    // deduplicated, not double-counted
        #expect(ch36.coChannelCount == 1)
        #expect(ch36.strongestNeighborRSSI == -45)    // strongest RSSI survives
    }

    @Test("ChannelOccupancyAnalyzer: duplicate BSSID order does not change the kept entry")
    func sameBSSIDSameBandDedupIsOrderIndependent() throws {
        // Stronger entry first, weaker second — the weaker one must not replace it.
        let aps = [
            observation(bssid: "AA:BB:CC:DD:EE:02", rssi: -50, channel: 40),
            observation(bssid: "AA:BB:CC:DD:EE:02", rssi: -80, channel: 40),
        ]
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot(aps),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch40 = try #require(result.first { $0.channel == 40 && $0.band == "5" })
        #expect(ch40.apCount == 1)
        #expect(ch40.strongestNeighborRSSI == -50)
    }

    @Test("ChannelOccupancyAnalyzer: same BSSID on different bands is not deduplicated")
    func sameBSSIDDifferentBandKeepsBoth() throws {
        let aps = [
            observation(bssid: "AA:BB:CC:DD:EE:03", rssi: -60, channel: 6, band: .band24GHz),
            observation(bssid: "AA:BB:CC:DD:EE:03", rssi: -50, channel: 36, band: .band5GHz),
        ]
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot(aps),
            currentChannel: nil,
            supportedBands: ["24", "5"],
            targetAP: nil
        )
        // Each band keeps its own copy of the AP.
        #expect(result.first { $0.channel == 6 && $0.band == "24" }?.apCount == 1)
        #expect(result.first { $0.channel == 36 && $0.band == "5" }?.apCount == 1)
    }

    // MARK: - Wide channel span / apex (40 / 80 MHz)

    @Test("ChannelOccupancyAnalyzer: 40 MHz AP applies the 40 MHz width multiplier")
    func fortyMHzWidthMultiplier() throws {
        // rssi -30 → weight 1.0; penalty = 1.0 * 1.0 * 1.2 * 1.0 * 18 = 21.6 → 22 → score 78
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot([observation(bssid: "AA:BB:CC:DD:EE:04", rssi: -30, channel: 44, widthMHz: 40)]),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch44 = try #require(result.first { $0.channel == 44 && $0.band == "5" })
        #expect(ch44.qualityScore == 78)
        #expect(ch44.interferenceScore == 22)
    }

    @Test("ChannelOccupancyAnalyzer: 80 MHz AP applies the 80 MHz width multiplier")
    func eightyMHzWidthMultiplier() throws {
        // rssi -30 → weight 1.0; penalty = 1.0 * 1.0 * 1.5 * 1.0 * 18 = 27 → score 73
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot([observation(bssid: "AA:BB:CC:DD:EE:05", rssi: -30, channel: 36, widthMHz: 80)]),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch36 = try #require(result.first { $0.channel == 36 && $0.band == "5" })
        #expect(ch36.qualityScore == 73)
        #expect(ch36.interferenceScore == 27)
    }

    @Test("ChannelOccupancyAnalyzer: uses operating width, not capability width")
    func operatingWidthNotCapabilityWidth() throws {
        // AP advertises 160 MHz capability but is operating at 40 MHz on ch 44.
        // The analyzer must model the 40 MHz block (42,50): ch 48 gets factor
        // 0.5 (score 92 at -50). Using the 160 MHz capability block (34,66)
        // would yield 0.125 (score 97), so 92 distinguishes operating width.
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot([observation(bssid: "AA:BB:CC:DD:EE:07", rssi: -50, channel: 44, widthMHz: 40, capabilitiesWidth: 160)]),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch48 = try #require(result.first { $0.channel == 48 && $0.band == "5" })
        #expect(ch48.qualityScore == 92)
    }

    @Test("ChannelSpanCalculator: 40/80 MHz span blocks (used by real overlap model)")
    func wideChannelSpanBlocks() {
        // These blocks feed ChannelQualityCalculator's real-band overlap (NH-14).
        // 40 MHz on ch 44 → block (42, 50)
        let span40 = ChannelSpanCalculator.channelBlock(
            primaryChannel: 44, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(span40.left == 42)
        #expect(span40.right == 50)

        // 80 MHz on ch 36 → block (34, 50)
        let span80 = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 80, band: .band5GHz, spanDirection: nil)
        #expect(span80.left == 34)
        #expect(span80.right == 50)
    }

    @Test("ChannelOccupancyAnalyzer: 80 MHz AP on ch 44 penalizes adjacent ch 40")
    func eightyMHzAdjacentPenalty() throws {
        // Real span of the 80 MHz AP on ch 44 is (34,50); the 20 MHz candidate
        // ch 40 (38,42) overlaps 4/16 → factor 0.25 → rssi -50 penalty ≈5 → 95.
        let result = ChannelOccupancyAnalyzer.analyze(
            snapshot: snapshot([observation(bssid: "AA:BB:CC:DD:EE:06", rssi: -50, channel: 44, widthMHz: 80)]),
            currentChannel: nil,
            supportedBands: ["5"],
            targetAP: nil
        )
        let ch40 = try #require(result.first { $0.channel == 40 && $0.band == "5" })
        #expect(ch40.qualityScore == 95)
        #expect(ch40.apCount == 1)
        #expect(ch40.strongestNeighborRSSI == -50)
    }
}
