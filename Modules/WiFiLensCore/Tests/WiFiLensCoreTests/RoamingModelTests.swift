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
            version: 1,
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
        #expect(decoded.version == RoamingSessionRecord.currentVersion)
    }
}
