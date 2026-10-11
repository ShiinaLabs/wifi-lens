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
        let scene = RoamingChartScene(
            segments: record.segments,
            transitions: record.transitions,
            duration: record.duration
        )
        #expect(scene.samples.first?.sample.rssi == -60)
        #expect(scene.duration == 5)
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
        let scene = RoamingChartScene(
            segments: decoded.segments,
            transitions: decoded.transitions,
            duration: decoded.duration
        )
        #expect(scene.signalRuns.isEmpty)
        #expect(scene.regions.first?.bssid == "AP-2")
    }

    @Test func importedSessionCollapsesConfirmedHandoffIntervalOnChartTimeline() throws {
        let t0 = Date(timeIntervalSince1970: 0)
        let t4 = t0.addingTimeInterval(4)
        let t5 = t0.addingTimeInterval(5)
        let t7 = t0.addingTimeInterval(7)
        let t10 = t0.addingTimeInterval(10)
        let record = RoamingSessionRecord(
            version: 2, savedAt: t10, ssid: "Home", bssid: "AP-B", phyMode: nil,
            channel: nil, duration: 10,
            segments: [
                RoamingSegment(bssid: "AP-A", startTime: t0, endTime: t4, samples: [
                    RoamingSample(timestamp: t0, rssi: -55, channel: 36, txRate: 100),
                    RoamingSample(timestamp: t4, rssi: -60, channel: 36, txRate: 100),
                ]),
                RoamingSegment(bssid: "AP-B", startTime: t5, endTime: t10, samples: [
                    RoamingSample(timestamp: t5, rssi: -50, channel: 44, txRate: 100),
                    RoamingSample(timestamp: t7, rssi: -51, channel: 44, txRate: 100),
                    RoamingSample(timestamp: t10, rssi: -53, channel: 44, txRate: 100),
                ]),
            ],
            transitions: [APTransitionEvent(
                timestamp: t5, fromBSSID: "AP-A", toBSSID: "AP-B",
                rssiBefore: -60, rssiAfter: -50, channelBefore: 36, channelAfter: 44
            )]
        )
        let imported = try JSONDecoder().decode(
            RoamingSessionRecord.self,
            from: JSONEncoder().encode(record)
        )

        let scene = RoamingChartScene(
            segments: imported.segments,
            transitions: imported.transitions,
            duration: imported.duration,
            origin: t0
        )

        #expect(scene.regions.map(\.start) == [0, 4])
        #expect(scene.regions.map(\.end) == [4, 9])
        #expect(scene.regions[0].end == scene.regions[1].start)
        #expect(scene.transitions.map(\.elapsedTime) == [4])
        #expect(scene.signalRuns.map { $0.points.map(\.elapsedTime) } == [[0, 4], [4, 6, 9]])
        #expect(scene.samples.count == 5)
        #expect(imported.segments[0].endTime == t4)
        #expect(imported.segments[1].startTime == t5)
        #expect(imported.segments[0].rssiRuns.flatMap { $0.map(\.timestamp) } == [t0, t4])
        #expect(imported.segments[1].rssiRuns.flatMap { $0.map(\.timestamp) } == [t5, t7, t10])
    }
}

struct RoamingChartSceneTests {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sample(_ time: TimeInterval, rssi: Int?) -> RoamingSample {
        RoamingSample(
            timestamp: date(time),
            rssi: rssi,
            channel: rssi == nil ? nil : 36,
            txRate: rssi == nil ? nil : 100
        )
    }

    private func handoffScene(
        previousSamples: [(time: TimeInterval, rssi: Int?)],
        transitionTime: TimeInterval,
        nextSamples: [(time: TimeInterval, rssi: Int?)],
        duration: TimeInterval,
        previousSegmentEnd: TimeInterval? = nil
    ) -> RoamingChartScene {
        let previousStart = previousSamples.map(\.time).min() ?? transitionTime
        let nextEnd = max(transitionTime, nextSamples.map(\.time).max() ?? transitionTime)
        let segments = [
            RoamingSegment(
                bssid: "AP-A",
                startTime: date(previousStart),
                endTime: date(previousSegmentEnd ?? transitionTime),
                samples: previousSamples.map { sample($0.time, rssi: $0.rssi) }
            ),
            RoamingSegment(
                bssid: "AP-B",
                startTime: date(transitionTime),
                endTime: date(nextEnd),
                samples: nextSamples.map { sample($0.time, rssi: $0.rssi) }
            ),
        ]
        return RoamingChartScene(
            segments: segments,
            transitions: [transition(transitionTime, from: "AP-A", to: "AP-B")],
            duration: duration,
            origin: date(0)
        )
    }

    private func transition(_ time: TimeInterval, from: String, to: String) -> APTransitionEvent {
        APTransitionEvent(
            timestamp: date(time), fromBSSID: from, toBSSID: to,
            rssiBefore: nil, rssiAfter: nil, channelBefore: nil, channelAfter: nil
        )
    }

    @Test func missingRSSIDoesNotBreakTrustedOwnershipOrConnectSignalRuns() {
        let segment = RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(4), samples: [
            RoamingSample(timestamp: date(0), rssi: -55, channel: 36, txRate: 100),
            RoamingSample(timestamp: date(2), rssi: nil, channel: nil, txRate: nil),
            RoamingSample(timestamp: date(4), rssi: -60, channel: 36, txRate: 100),
        ])

        let scene = RoamingChartScene(segments: [segment], transitions: [], duration: 4, origin: date(0))

        #expect(scene.regions.map(\.start) == [0])
        #expect(scene.regions.map(\.end) == [4])
        #expect(scene.gaps.isEmpty)
        #expect(segment.rssiRuns.map { $0.map(\.timestamp) } == [[date(0)], [date(4)]])
        #expect(scene.signalRuns.map { $0.points.map(\.elapsedTime) } == [[0], [4]])
    }

    @Test func unconfirmedAssociationGapRemainsUnfilled() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(2), samples: [
                RoamingSample(timestamp: date(0), rssi: -55, channel: 36, txRate: 100),
            ]),
            RoamingSegment(bssid: "AP-B", startTime: date(8), endTime: date(10), samples: [
                RoamingSample(timestamp: date(10), rssi: -53, channel: 44, txRate: 100),
            ]),
        ]

        let scene = RoamingChartScene(segments: segments, transitions: [], duration: 10, origin: date(0))

        #expect(scene.regions.map(\.start) == [0, 8])
        #expect(scene.regions.map(\.end) == [2, 10])
        #expect(scene.gaps == [RoamingChartGap(start: 2, end: 8, previousSegmentIndex: 0, nextSegmentIndex: 1)])
        #expect(scene.transitions.isEmpty)
    }

    @Test func repeatedBSSIDTransitionsAreConsumedOnceAndMatchAdjacentSegments() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(3)),
            RoamingSegment(bssid: "AP-B", startTime: date(5), endTime: date(7)),
            RoamingSegment(bssid: "AP-A", startTime: date(9), endTime: date(11)),
            RoamingSegment(bssid: "AP-B", startTime: date(13), endTime: date(15)),
        ]

        let scene = RoamingChartScene(
            segments: segments,
            transitions: [
                transition(4, from: "AP-A", to: "AP-B"),
                transition(8, from: "AP-B", to: "AP-A"),
                transition(12, from: "AP-A", to: "AP-B"),
            ],
            duration: 15,
            origin: date(0)
        )

        #expect(scene.regions.map(\.start) == [0, 4, 8, 12])
        #expect(scene.regions.map(\.end) == [4, 8, 12, 15])
        #expect(scene.transitions.map(\.eventIndex) == [0, 1, 2])
        #expect(scene.transitions.map(\.fromSegmentIndex) == [0, 1, 2])
        #expect(scene.transitions.map(\.toSegmentIndex) == [1, 2, 3])
        #expect(scene.gaps.isEmpty)
    }

    @Test func confirmedRoamingSharesBoundaryButKeepsRSSIRunsIndependent() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(5), samples: [
                RoamingSample(timestamp: date(0), rssi: -55, channel: 36, txRate: 100),
                RoamingSample(timestamp: date(4), rssi: -60, channel: 36, txRate: 100),
            ]),
            RoamingSegment(bssid: "AP-B", startTime: date(5), endTime: date(10), samples: [
                RoamingSample(timestamp: date(5), rssi: -50, channel: 44, txRate: 100),
                RoamingSample(timestamp: date(7), rssi: -51, channel: 44, txRate: 100),
                RoamingSample(timestamp: date(10), rssi: -53, channel: 44, txRate: 100),
            ]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [transition(5, from: "AP-A", to: "AP-B")],
            duration: 10,
            origin: date(0)
        )

        #expect(scene.regions.map(\.start) == [0, 4])
        #expect(scene.regions.map(\.end) == [4, 9])
        #expect(scene.transitions.map(\.elapsedTime) == [4])
        #expect(scene.signalRuns.map { $0.points.map(\.elapsedTime) } == [[0, 4], [4, 6, 9]])
        #expect(scene.signalRuns[0].points.last?.elapsedTime == 4)
        #expect(scene.signalRuns[1].points.first?.elapsedTime == 4)
        #expect(scene.transitions.first?.elapsedTime == 4)
        #expect(scene.regions[0].end == scene.regions[1].start)
        #expect(scene.duration == 9)
        #expect(segments[0].samples.map(\.timestamp) == [date(0), date(4)])
        #expect(segments[1].samples.map(\.timestamp) == [date(5), date(7), date(10)])
        #expect(scene.samples.map(\.elapsedTime) == [0, 4, 4, 6, 9])
        #expect(scene.samples.count == 5)
        #expect(scene.gaps.isEmpty)
    }

    @Test func handoffCollapseUsesRawTimestampSpanAndPreservesTheRealRecordBoundary() {
        for span: TimeInterval in [0.999, 1.4, 1.5] {
            let start = span < 1 ? 60.128 : 60.0
            let scene = handoffScene(
                previousSamples: [(time: start, rssi: -75)],
                transitionTime: start + span,
                nextSamples: [(time: start + span, rssi: -55)],
                duration: 80
            )
            #expect(scene.duration == 79)
            #expect(scene.transitions.count == 1)
            #expect(scene.signalRuns[0].points.last?.elapsedTime == scene.transitions[0].elapsedTime)
            #expect(scene.signalRuns[1].points.first?.elapsedTime == scene.transitions[0].elapsedTime)
        }

        let origin = date(813_340_264.007855)
        let oldTimestamp = date(813_340_324.136174)
        let handoffTimestamp = date(813_340_325.135256)
        let realRecordScene = RoamingChartScene(
            segments: [
                RoamingSegment(bssid: "AP-A", startTime: origin, endTime: handoffTimestamp, samples: [
                    RoamingSample(timestamp: oldTimestamp, rssi: -75, channel: 40, txRate: 162),
                ]),
                RoamingSegment(bssid: "AP-B", startTime: handoffTimestamp, endTime: handoffTimestamp, samples: [
                    RoamingSample(timestamp: handoffTimestamp, rssi: -55, channel: 40, txRate: 1152),
                ]),
            ],
            transitions: [transition(handoffTimestamp.timeIntervalSince1970, from: "AP-A", to: "AP-B")],
            duration: 80,
            origin: origin
        )
        #expect(realRecordScene.signalRuns.map { $0.points.map(\.elapsedTime) } == [[60], [60]])
        #expect(realRecordScene.transitions.map(\.elapsedTime) == [60])
        #expect(realRecordScene.duration == 79)
    }

    @Test func handoffCollapseRejectsSpansAboveOnePointFiveSeconds() {
        for span: TimeInterval in [1.6, 3, 10, 30] {
            let scene = handoffScene(
                previousSamples: [(time: 40, rssi: -60)],
                transitionTime: 40 + span,
                nextSamples: [(time: 40 + span, rssi: -50)],
                duration: 80
            )
            #expect(scene.duration == 80)
            #expect(scene.transitions.count == 1)
        }

        let combinedSpan = handoffScene(
            previousSamples: [(time: 60, rssi: -60)],
            transitionTime: 61.4,
            nextSamples: [(time: 61.6, rssi: -50)],
            duration: 80
        )
        #expect(combinedSpan.duration == 80)
    }

    @Test func handoffCollapseRejectsNilSamplesAndDelayedNewAPMeasurements() {
        let oldSideGap = handoffScene(
            previousSamples: [(time: 10, rssi: -60), (time: 10.5, rssi: nil)],
            transitionTime: 11,
            nextSamples: [(time: 11, rssi: -50)],
            duration: 20
        )
        #expect(oldSideGap.duration == 20)
        #expect(oldSideGap.transitions.count == 1)
        #expect(oldSideGap.samples.contains { $0.sample.rssi == nil })

        let longMissingRSSIInterval = handoffScene(
            previousSamples: [(time: 40, rssi: -60), (time: 41, rssi: nil), (time: 42, rssi: nil)],
            transitionTime: 55,
            nextSamples: [(time: 55, rssi: -50)],
            duration: 60
        )
        #expect(longMissingRSSIInterval.duration == 60)
        #expect(longMissingRSSIInterval.transitions.count == 1)
        #expect(longMissingRSSIInterval.samples.filter { $0.sample.rssi == nil }.count == 2)

        let newSideGap = handoffScene(
            previousSamples: [(time: 10, rssi: -60)],
            transitionTime: 11,
            nextSamples: [(time: 11, rssi: nil), (time: 11.5, rssi: -50)],
            duration: 20
        )
        #expect(newSideGap.duration == 20)
        #expect(newSideGap.transitions.count == 1)
        #expect(newSideGap.samples.contains { $0.sample.rssi == nil })

        let delayedNewMeasurement = handoffScene(
            previousSamples: [(time: 10, rssi: -60)],
            transitionTime: 11,
            nextSamples: [(time: 14, rssi: -50)],
            duration: 20
        )
        #expect(delayedNewMeasurement.duration == 20)
        #expect(delayedNewMeasurement.transitions.count == 1)
    }

    @Test func multipleHandoffsCollapseOnlyEligibleIntervalsInChronologicalOrder() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(1), samples: [sample(0.2, rssi: -60)]),
            RoamingSegment(bssid: "AP-B", startTime: date(1), endTime: date(8), samples: [sample(1, rssi: -55)]),
            RoamingSegment(bssid: "AP-C", startTime: date(8), endTime: date(9), samples: [sample(8, rssi: -50)]),
            RoamingSegment(bssid: "AP-D", startTime: date(9), endTime: date(10), samples: [sample(9, rssi: -45)]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [
                transition(1, from: "AP-A", to: "AP-B"),
                transition(8, from: "AP-B", to: "AP-C"),
                transition(9, from: "AP-C", to: "AP-D"),
            ],
            duration: 15,
            origin: date(0)
        )

        #expect(scene.transitions.count == 3)
        #expect(scene.transitions.map(\.elapsedTime) == [0, 7, 7])
        #expect(scene.duration == 13)
        #expect(zip(scene.transitions, scene.transitions.dropFirst()).allSatisfy { $0.elapsedTime <= $1.elapsedTime })
        #expect(segments.flatMap(\.samples).count == scene.samples.count)
    }

    @Test func repeatedBSSIDsDoNotReuseEventsOrCollapseLongCandidates() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(1), samples: [sample(0, rssi: -60)]),
            RoamingSegment(bssid: "AP-B", startTime: date(1), endTime: date(2), samples: [sample(1, rssi: -55)]),
            RoamingSegment(bssid: "AP-A", startTime: date(2), endTime: date(8), samples: [sample(2, rssi: -50)]),
            RoamingSegment(bssid: "AP-B", startTime: date(8), endTime: date(9), samples: [sample(8, rssi: -45)]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [
                transition(1, from: "AP-A", to: "AP-B"),
                transition(2, from: "AP-B", to: "AP-A"),
                transition(8, from: "AP-A", to: "AP-B"),
            ],
            duration: 20,
            origin: date(0)
        )

        #expect(scene.transitions.map(\.eventIndex) == [0, 1, 2])
        #expect(scene.transitions.map(\.elapsedTime) == [0, 0, 6])
        #expect(scene.duration == 18)
    }

    @Test func malformedSamplesAndOutOfSegmentEvidenceCannotQualifyForCollapse() {
        let duplicateTimestamps = handoffScene(
            previousSamples: [(time: 10, rssi: -60), (time: 10, rssi: -61)],
            transitionTime: 11,
            nextSamples: [(time: 11, rssi: -50)],
            duration: 30
        )
        #expect(duplicateTimestamps.duration == 30)

        let nonMonotonicTimestamps = handoffScene(
            previousSamples: [(time: 10, rssi: -60), (time: 10.8, rssi: -59), (time: 10.5, rssi: -58)],
            transitionTime: 11,
            nextSamples: [(time: 11, rssi: -50)],
            duration: 30
        )
        #expect(nonMonotonicTimestamps.duration == 30)

        let outOfSegmentMeasurement = handoffScene(
            previousSamples: [(time: 10, rssi: -60), (time: 10.5, rssi: -59)],
            transitionTime: 11,
            nextSamples: [(time: 11, rssi: -50)],
            duration: 30,
            previousSegmentEnd: 10.4
        )
        #expect(outOfSegmentMeasurement.duration == 30)
        #expect(outOfSegmentMeasurement.transitions.count == 1)
    }

    @Test func hoverAtCollapsedHandoffHighlightsBothRealRSSIPoints() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(6), samples: [
                RoamingSample(timestamp: date(5), rssi: -75, channel: 40, txRate: 204),
            ]),
            RoamingSegment(bssid: "AP-B", startTime: date(6), endTime: date(8), samples: [
                RoamingSample(timestamp: date(6), rssi: -55, channel: 40, txRate: 1441),
            ]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [transition(6, from: "AP-A", to: "AP-B")],
            duration: 8,
            origin: date(0)
        )

        let handoffSamples = scene.hoverSamples(near: scene.transitions[0].elapsedTime)

        #expect(handoffSamples.count == 2)
        #expect(handoffSamples.map(\.point.elapsedTime) == [5, 5])
        #expect(Set(handoffSamples.compactMap(\.point.sample.rssi)) == Set([-75, -55]))
        #expect(Set(handoffSamples.map(\.bssid)) == Set(["AP-A", "AP-B"]))
        #expect(handoffSamples.allSatisfy { $0.point.sample.channel == 40 })
    }

    @Test func noRSSIStillProducesOwnershipRegionWithoutSignalRuns() {
        let segment = RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(5), samples: [
            RoamingSample(timestamp: date(1), rssi: nil, channel: nil, txRate: nil),
        ])

        let scene = RoamingChartScene(segments: [segment], transitions: [], duration: 5, origin: date(0))

        #expect(scene.regions.map(\.start) == [0])
        #expect(scene.regions.map(\.end) == [5])
        #expect(segment.rssiRuns.isEmpty)
        #expect(scene.signalRuns.isEmpty)
    }

    @Test func timestampsWithTheSameDisplayedSecondShareOneHorizontalTime() {
        let sessionStart = Date(timeIntervalSince1970: 1_800_000_000.4)
        let previousAPEnd = sessionStart.addingTimeInterval(5.1)
        let nextAPStart = sessionStart.addingTimeInterval(5.9)
        let scale = RoamingChartTimeScale(origin: sessionStart)

        #expect(scale.elapsedTime(for: previousAPEnd) == 5)
        #expect(scale.elapsedTime(for: nextAPStart) == 5)
        for displayScale in [CGFloat(1), 2, 3] {
            for width in [CGFloat(137), 311.5, 640] {
                let leftX = scale.xPosition(
                    for: scale.elapsedTime(for: previousAPEnd), visibleStart: 1.25,
                    visibleDuration: 9.5, plotLeft: 40, plotWidth: width, displayScale: displayScale
                )
                let rightX = scale.xPosition(
                    for: scale.elapsedTime(for: nextAPStart), visibleStart: 1.25,
                    visibleDuration: 9.5, plotLeft: 40, plotWidth: width, displayScale: displayScale
                )
                #expect(leftX == rightX)
            }
        }
    }

    @Test func runtimeAndHistoricalProjectionUseIdenticalSceneSemantics() {
        let origin = date(100)
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(100), endTime: date(104), samples: [
                RoamingSample(timestamp: date(100), rssi: -55, channel: 36, txRate: 100),
                RoamingSample(timestamp: date(104), rssi: -60, channel: 36, txRate: 100),
            ]),
            RoamingSegment(bssid: "AP-B", startTime: date(107), endTime: date(110), samples: [
                RoamingSample(timestamp: date(108), rssi: -50, channel: 44, txRate: 100),
            ]),
        ]
        let events = [transition(106, from: "AP-A", to: "AP-B")]
        let liveScene = RoamingChartScene(segments: segments, transitions: events, duration: 10, origin: origin)
        let replayScene = RoamingChartScene(segments: segments, transitions: events, duration: 10, origin: origin)
        #expect(liveScene.regions == replayScene.regions)
        #expect(liveScene.signalRuns.map { $0.points.map(\.elapsedTime) } == replayScene.signalRuns.map { $0.points.map(\.elapsedTime) })
        #expect(liveScene.transitions.map(\.elapsedTime) == replayScene.transitions.map(\.elapsedTime))
        #expect(liveScene.gaps == replayScene.gaps)
    }

    @Test func ambiguousTransitionIsNotGuessedAndLeavesUnknownGap() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(3)),
            RoamingSegment(bssid: "AP-B", startTime: date(8), endTime: date(10)),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [transition(4, from: "AP-A", to: "AP-B"), transition(5, from: "AP-A", to: "AP-B")],
            duration: 10,
            origin: date(0)
        )
        #expect(scene.transitions.isEmpty)
        #expect(scene.regions.map(\.start) == [0, 8])
        #expect(scene.regions.map(\.end) == [3, 10])
        #expect(scene.gaps.contains(RoamingChartGap(start: 3, end: 8, previousSegmentIndex: 0, nextSegmentIndex: 1)))
    }

    @Test func confirmedTransitionWithoutBothMeasuredEndpointsDoesNotCreateSignalConnector() {
        let segments = [
            RoamingSegment(bssid: "AP-A", startTime: date(0), endTime: date(4), samples: [
                RoamingSample(timestamp: date(4), rssi: nil, channel: nil, txRate: nil),
            ]),
            RoamingSegment(bssid: "AP-B", startTime: date(6), endTime: date(8), samples: [
                RoamingSample(timestamp: date(6), rssi: -50, channel: 44, txRate: 100),
            ]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [transition(6, from: "AP-A", to: "AP-B")],
            duration: 8,
            origin: date(0)
        )

        #expect(scene.transitions.count == 1)
        #expect(scene.regions[0].end == scene.regions[1].start)
    }

    @Test func realRecordBoundaryUsesOnePixelXForTransitionAndNewAPSample() {
        let origin = date(813_340_264.007855)
        let oldLastSample = date(813_340_324.136174)
        let transitionTime = date(813_340_325.135256)
        let segments = [
            RoamingSegment(bssid: "50:88:11:ba:05:67", startTime: origin, endTime: transitionTime, samples: [
                RoamingSample(timestamp: oldLastSample, rssi: -75, channel: 40, txRate: 162),
            ]),
            RoamingSegment(bssid: "f4:87:c5:1d:03:bc", startTime: transitionTime, endTime: transitionTime, samples: [
                RoamingSample(timestamp: transitionTime, rssi: -55, channel: 40, txRate: 1152),
            ]),
        ]
        let scene = RoamingChartScene(
            segments: segments,
            transitions: [transition(transitionTime.timeIntervalSince1970, from: "50:88:11:ba:05:67", to: "f4:87:c5:1d:03:bc")],
            duration: transitionTime.timeIntervalSince(origin),
            origin: origin
        )
        let oldEndpoint = scene.signalRuns[0].points.last
        let newEndpoint = scene.signalRuns[1].points.first

        #expect(oldEndpoint?.sample.rssi == -75)
        #expect(newEndpoint?.sample.rssi == -55)
        #expect(oldEndpoint?.elapsedTime == 60)
        #expect(scene.transitions.first?.elapsedTime == 60)
        #expect(newEndpoint?.elapsedTime == 60)

        let scale = RoamingChartTimeScale(origin: origin)
        let transitionX = scale.xPosition(
            for: scene.transitions[0].elapsedTime,
            visibleStart: 0,
            visibleDuration: scene.duration,
            plotLeft: 40,
            plotWidth: 640,
            displayScale: 2
        )
        let newSampleX = scale.xPosition(
            for: scene.signalRuns[1].points[0].elapsedTime,
            visibleStart: 0,
            visibleDuration: scene.duration,
            plotLeft: 40,
            plotWidth: 640,
            displayScale: 2
        )
        #expect(transitionX == newSampleX)
        #expect(segments.flatMap(\.samples).count == 2)
        #expect(scene.samples.count == 2)
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
