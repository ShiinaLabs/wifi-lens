import Testing
import Foundation
@testable import WiFiLensCore

// MARK: - RoamingSample

struct RoamingSampleTests {

    @Test func basicProperties() {
        let now = Date()
        let sample = RoamingSample(timestamp: now, rssi: -60, channel: 44, txRate: 300.0, gatewayLatency: 5.2)
        #expect(sample.timestamp == now)
        #expect(sample.rssi == -60)
        #expect(sample.channel == 44)
        #expect(sample.txRate == 300.0)
        #expect(sample.gatewayLatency == 5.2)
    }

    @Test func nilGatewayLatency() {
        let sample = RoamingSample(timestamp: Date(), rssi: -50, channel: 6, txRate: 100.0)
        #expect(sample.gatewayLatency == nil)
    }

    @Test func uniqueID() {
        let now = Date()
        let s1 = RoamingSample(timestamp: now, rssi: -50, channel: 6, txRate: 100)
        let s2 = RoamingSample(timestamp: now, rssi: -60, channel: 44, txRate: 200)
        #expect(s1.id != s2.id)
    }

    @Test func codableRoundTrip() throws {
        let original = RoamingSample(timestamp: Date(), rssi: -55, channel: 36, txRate: 866.7, gatewayLatency: 3.1)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoamingSample.self, from: data)
        #expect(decoded.rssi == original.rssi)
        #expect(decoded.channel == original.channel)
        #expect(decoded.txRate == original.txRate)
        #expect(decoded.gatewayLatency == original.gatewayLatency)
        #expect(decoded.timestamp == original.timestamp)
    }

    @Test func missingMetricsRemainNilAfterCodableRoundTrip() throws {
        let original = RoamingSample(timestamp: Date(), rssi: nil, channel: nil, txRate: nil)
        let decoded = try JSONDecoder().decode(RoamingSample.self, from: JSONEncoder().encode(original))
        #expect(decoded.rssi == nil)
        #expect(decoded.channel == nil)
        #expect(decoded.txRate == nil)
    }
}

// MARK: - RoamingSegment

struct RoamingSegmentTests {

    @Test func basicProperties() {
        let now = Date()
        let segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now)
        #expect(segment.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(segment.startTime == now)
        #expect(segment.endTime == nil)
        #expect(segment.samples.isEmpty)
    }

    @Test func rssiRangeWithSamples() {
        let now = Date()
        let samples = [
            RoamingSample(timestamp: now, rssi: -50, channel: 44, txRate: 300),
            RoamingSample(timestamp: now, rssi: -80, channel: 44, txRate: 200),
            RoamingSample(timestamp: now, rssi: -65, channel: 44, txRate: 250),
        ]
        let segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now, samples: samples)
        let (min, max) = segment.rssiRange
        #expect(min == -80)
        #expect(max == -50)
    }

    @Test func rssiRangeEmptySamples() {
        let segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: Date())
        let (min, max) = segment.rssiRange
        #expect(min == -100)
        #expect(max == -30)
    }

    @Test func missingRSSISamplesSplitRunsAndDoNotAffectMeasuredRange() {
        let start = Date(timeIntervalSince1970: 100)
        let segment = RoamingSegment(bssid: "AP", startTime: start, samples: [
            RoamingSample(timestamp: start, rssi: -50, channel: 36, txRate: 100),
            RoamingSample(timestamp: start.addingTimeInterval(1), rssi: nil, channel: nil, txRate: nil),
            RoamingSample(timestamp: start.addingTimeInterval(2), rssi: -70, channel: 44, txRate: 200),
            RoamingSample(timestamp: start.addingTimeInterval(3), rssi: nil, channel: nil, txRate: nil),
        ])

        #expect(segment.rssiRuns.map { $0.compactMap(\.rssi) } == [[-50], [-70]])
        #expect(segment.rssiRange.min == -70)
        #expect(segment.rssiRange.max == -50)
    }

    @Test func allMissingRSSIRangeUsesOnlyTheChartAxisFallback() {
        let now = Date()
        let segment = RoamingSegment(bssid: "AP", startTime: now, samples: [
            RoamingSample(timestamp: now, rssi: nil, channel: nil, txRate: nil),
        ])
        #expect(segment.rssiRuns.isEmpty)
        #expect(segment.rssiRange.min == -100)
        #expect(segment.rssiRange.max == -30)
    }

    @Test func durationWithoutEndTimeUsesLastSample() {
        let now = Date()
        let samples = [
            RoamingSample(timestamp: now, rssi: -50, channel: 44, txRate: 300),
            RoamingSample(timestamp: now.addingTimeInterval(10), rssi: -60, channel: 44, txRate: 250),
        ]
        let segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now, samples: samples)
        #expect(segment.duration == 10)
    }

    @Test func durationWithExplicitEndTime() {
        let now = Date()
        var segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now)
        segment.endTime = now.addingTimeInterval(30)
        #expect(segment.duration == 30)
    }

    @Test func durationFallsBackToStartTime() {
        let now = Date()
        let segment = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now)
        #expect(segment.duration == 0)
    }

    @Test func codableRoundTrip() throws {
        let now = Date()
        let original = RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now, endTime: now.addingTimeInterval(20), samples: [
            RoamingSample(timestamp: now, rssi: -50, channel: 44, txRate: 300),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoamingSegment.self, from: data)
        #expect(decoded.bssid == original.bssid)
        #expect(decoded.startTime == original.startTime)
        #expect(decoded.endTime == original.endTime)
        #expect(decoded.samples.count == 1)
        #expect(decoded.samples[0].rssi == -50)
    }
}

// MARK: - APTransitionEvent

struct APTransitionEventTests {

    @Test func basicProperties() {
        let now = Date()
        let event = APTransitionEvent(
            timestamp: now,
            fromBSSID: "aa:bb:cc:dd:ee:01",
            toBSSID: "aa:bb:cc:dd:ee:02",
            rssiBefore: -75,
            rssiAfter: -50,
            channelBefore: 36,
            channelAfter: 44
        )
        #expect(event.fromBSSID == "aa:bb:cc:dd:ee:01")
        #expect(event.toBSSID == "aa:bb:cc:dd:ee:02")
        #expect(event.rssiBefore == -75)
        #expect(event.rssiAfter == -50)
        #expect(event.channelBefore == 36)
        #expect(event.channelAfter == 44)
    }

    @Test func codableRoundTrip() throws {
        let original = APTransitionEvent(
            timestamp: Date(),
            fromBSSID: "aa:bb:01",
            toBSSID: "aa:bb:02",
            rssiBefore: -80,
            rssiAfter: -45,
            channelBefore: 1,
            channelAfter: 44
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(APTransitionEvent.self, from: data)
        #expect(decoded.fromBSSID == original.fromBSSID)
        #expect(decoded.toBSSID == original.toBSSID)
        #expect(decoded.rssiBefore == original.rssiBefore)
        #expect(decoded.rssiAfter == original.rssiAfter)
        #expect(decoded.channelBefore == original.channelBefore)
    }
}

// MARK: - RoamingSessionRecord

struct RoamingSessionRecordTests {

    @Test func basicProperties() {
        let now = Date()
        let record = RoamingSessionRecord(
            version: 1,
            savedAt: now,
            ssid: "TestNet",
            bssid: "aa:bb:cc:dd:ee:ff",
            phyMode: "ax",
            channel: 44,
            duration: 120.5,
            segments: [],
            transitions: []
        )
        #expect(record.version == 1)
        #expect(record.ssid == "TestNet")
        #expect(record.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(record.phyMode == "ax")
        #expect(record.channel == 44)
        #expect(record.duration == 120.5)
        #expect(record.segments.isEmpty)
        #expect(record.transitions.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let now = Date()
        let original = RoamingSessionRecord(
            version: RoamingSessionRecord.currentVersion,
            savedAt: now,
            ssid: "CorpWiFi",
            bssid: "aa:bb:cc:dd:ee:ff",
            phyMode: "ac",
            channel: 36,
            duration: 300,
            segments: [
                RoamingSegment(bssid: "aa:bb:cc:dd:ee:ff", startTime: now, samples: [
                    RoamingSample(timestamp: now, rssi: -50, channel: 36, txRate: 433),
                ]),
            ],
            transitions: [
                APTransitionEvent(timestamp: now, fromBSSID: "aa:bb:01", toBSSID: "aa:bb:02", rssiBefore: -70, rssiAfter: -45, channelBefore: 36, channelAfter: 44),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RoamingSessionRecord.self, from: data)
        #expect(decoded.ssid == original.ssid)
        #expect(decoded.segments.count == 1)
        #expect(decoded.transitions.count == 1)
        #expect(decoded.version == 2)
    }

    @Test func versionOneJSONWithRequiredNumericMetricsStillDecodes() throws {
        let json = #"{"version":1,"savedAt":0,"ssid":"Legacy","bssid":"AP-1","phyMode":"ax","channel":36,"duration":5,"segments":[{"bssid":"AP-1","startTime":0,"samples":[{"timestamp":0,"rssi":-60,"channel":36,"txRate":400}]}],"transitions":[{"timestamp":1,"fromBSSID":"AP-1","toBSSID":"AP-2","rssiBefore":-60,"rssiAfter":-50,"channelBefore":36,"channelAfter":44}]}"#
        let record = try JSONDecoder().decode(RoamingSessionRecord.self, from: Data(json.utf8))
        #expect(record.version == 1)
        #expect(record.channel == 36)
        #expect(record.segments[0].samples[0].rssi == -60)
        #expect(record.transitions[0].channelAfter == 44)
    }

    @Test func versionTwoJSONPreservesMissingMetrics() throws {
        let now = Date(timeIntervalSince1970: 100)
        let record = RoamingSessionRecord(
            version: 2, savedAt: now, ssid: "Current", bssid: "AP-2", phyMode: nil,
            channel: nil, duration: 2,
            segments: [RoamingSegment(bssid: "AP-2", startTime: now, samples: [
                RoamingSample(timestamp: now, rssi: nil, channel: nil, txRate: nil),
            ])],
            transitions: [APTransitionEvent(
                timestamp: now, fromBSSID: "AP-1", toBSSID: "AP-2",
                rssiBefore: -60, rssiAfter: nil, channelBefore: 36, channelAfter: nil
            )]
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RoamingSessionRecord.self, from: data)
        #expect(decoded.version == 2)
        #expect(decoded.channel == nil)
        #expect(decoded.segments[0].samples[0].rssi == nil)
        #expect(decoded.segments[0].samples[0].channel == nil)
        #expect(decoded.segments[0].samples[0].txRate == nil)
        #expect(decoded.transitions[0].rssiBefore == -60)
        #expect(decoded.transitions[0].rssiAfter == nil)
        #expect(decoded.transitions[0].channelAfter == nil)
    }
}

struct CurrentWiFiViewDataResolverTests {
    @Test func interfaceDetailsRequireCurrentAssociationAndUseOnlyVerifiedMetrics() {
        let status = resolverStatus(metricsAttribution: .verified)
        let observation = resolverObservation(status: status)
        let wifi = NetworkInterfaceInfo(interfaceName: "en0", interfaceIndex: 4, isWiFiInterface: true, channel: 36, rssi: -55)

        let resolved = InterfaceWiFiStatusResolver.resolve(
            interface: wifi, observation: observation, currentStatusValidity: .current
        )
        #expect(resolved?.rssi == -55)
        #expect(InterfaceWiFiStatusResolver.verifiedMetrics(for: resolved)?.channel == 36)
    }

    @Test func unverifiedOrInconsistentMetricsNeverFallBackToRawInterfaceValues() {
        for attribution in [WiFiMetricsAttribution.unverified, .inconsistent] {
            let status = resolverStatus(metricsAttribution: attribution, rssi: nil, channel: nil)
            let observation = resolverObservation(status: status)
            let wifi = NetworkInterfaceInfo(interfaceName: "en0", interfaceIndex: 4, isWiFiInterface: true, channel: 36, rssi: -55)
            let resolved = InterfaceWiFiStatusResolver.resolve(
                interface: wifi, observation: observation, currentStatusValidity: .current
            )
            #expect(resolved?.linkAssessment?.state == VerifiedWiFiLinkState.associated)
            #expect(InterfaceWiFiStatusResolver.verifiedMetrics(for: resolved) == nil)
        }
    }

    @Test func expiredObservationAndNonWiFiInterfaceAreRejected() {
        let status = resolverStatus(metricsAttribution: .verified)
        let observation = resolverObservation(status: status)
        let wifi = NetworkInterfaceInfo(interfaceName: "en0", interfaceIndex: 4, isWiFiInterface: true)
        let mismatchedIndex = NetworkInterfaceInfo(interfaceName: "en0", interfaceIndex: 5, isWiFiInterface: true)
        let ethernet = NetworkInterfaceInfo(interfaceName: "en1", isWiFiInterface: false)
        let mismatchedCycle = WiFiObservation(timestamp: status.timestamp, sourceCycleID: UUID(), currentStatus: status)

        #expect(InterfaceWiFiStatusResolver.resolve(interface: wifi, observation: observation, currentStatusValidity: .expired) == nil)
        #expect(InterfaceWiFiStatusResolver.resolve(interface: ethernet, observation: observation, currentStatusValidity: .current) == nil)
        #expect(InterfaceWiFiStatusResolver.resolve(interface: mismatchedIndex, observation: observation, currentStatusValidity: .current) == nil)
        #expect(InterfaceWiFiStatusResolver.resolve(interface: wifi, observation: mismatchedCycle, currentStatusValidity: .current) == nil)
    }

    @Test func overviewUsesOnlyTheObservationStatusAndItsRecommendations() {
        let status = resolverStatus(metricsAttribution: .verified)
        let recommendation = ChannelRecommendation(from: ChannelQuality(
            channel: 36, band: "5GHz", bandDisplay: "5 GHz", qualityScore: 80,
            qualityLevel: .good, apCount: 1, coChannelCount: 0, adjacentCount: 0,
            interferenceScore: 0, overlapLevel: .low, strongestNeighborRSSI: -80,
            isCurrentChannel: true
        ))
        let observation = resolverObservation(status: status, recommendations: [recommendation])
        let valid = resolverValidity(status: .current, recommendations: .current)

        #expect(OverviewWiFiDataResolver.currentStatus(observation: observation, validity: valid)?.ssid == "TestNet")
        #expect(OverviewWiFiDataResolver.currentChannelRecommendations(observation: observation, validity: valid).map(\.channel) == [36])
        #expect(OverviewWiFiDataResolver.currentStatus(observation: observation, validity: resolverValidity(status: .expired, recommendations: .current)) == nil)
        #expect(OverviewWiFiDataResolver.currentChannelRecommendations(observation: observation, validity: resolverValidity(status: .current, recommendations: .expired)).isEmpty)
    }

    @Test func overviewKeepsVerifiedAssociationWhenMetricsAreUnknown() {
        let status = resolverStatus(metricsAttribution: .unverified, rssi: nil, channel: nil)
        let observation = resolverObservation(status: status)
        let validity = resolverValidity(status: .current, recommendations: .current)

        #expect(OverviewWiFiDataResolver.currentStatus(observation: observation, validity: validity)?.ssid == "TestNet")
        #expect(OverviewWiFiDataResolver.currentChannelRecommendations(observation: observation, validity: validity).isEmpty)
    }

    @Test func overviewKeepsAssociationWhenSSIDIsUnavailable() {
        let status = resolverStatus(metricsAttribution: .unverified, rssi: nil, channel: nil, ssid: nil)
        let observation = resolverObservation(status: status)
        let validity = resolverValidity(status: .current, recommendations: .notTested)
        #expect(OverviewWiFiDataResolver.currentStatus(observation: observation, validity: validity) != nil)
    }
}

private func resolverStatus(
    metricsAttribution: WiFiMetricsAttribution,
    rssi: Int? = -55,
    channel: Int? = 36,
    ssid: String? = "TestNet"
) -> WiFiCurrentStatus {
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    let cycleID = UUID()
    let evidence = WiFiLinkRawEvidence(
        snapshotCycleID: cycleID, capturedAt: timestamp, interfaceName: "en0",
        mode: .station, radio: .reportedOn, linkActive: true,
        ssid: ssid, bssid: "AP-1", interfaceIndex: 4
    )
    let assessment = WiFiLinkInterpreter.evaluate(evidence, expectedCycleID: cycleID, expectedCapturedAt: timestamp)
    return WiFiCurrentStatus(
        timestamp: timestamp, interfaceSnapshotCycleID: cycleID, interfaceName: "en0", interfaceIndex: 4,
        ssid: ssid, bssid: "AP-1", channel: channel, rssi: rssi,
        isConnected: true, isWiFiPowerOn: true, linkEvidence: evidence,
        linkAssessment: assessment, metricsAttribution: metricsAttribution
    )
}

private func resolverObservation(
    status: WiFiCurrentStatus,
    recommendations: [ChannelRecommendation]? = nil
) -> WiFiObservation {
    WiFiObservation(
        timestamp: status.timestamp,
        sourceCycleID: status.interfaceSnapshotCycleID,
        currentStatus: status,
        channelRecommendation: recommendations
    )
}

private func resolverValidity(
    status: WiFiObservationFieldValidity,
    recommendations: WiFiObservationFieldValidity
) -> WiFiObservationValidity {
    WiFiObservationValidity(
        currentStatus: status, gatewayLatency: .notTested, environment: .notTested,
        channelAnalysis: .notTested, channelRecommendation: recommendations,
        quality: .notTested, diagnosis: .notTested
    )
}
