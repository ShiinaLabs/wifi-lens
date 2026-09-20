import Testing
import Foundation
import SwiftUI
import ChartLens
@testable import WiFi_Lens

// MARK: - NetworkSnapshot

struct NetworkSnapshotTests {

    private func makeSnapshot(
        bssid: String = "aa:bb:cc:dd:ee:ff",
        ssid: String = "TestNet",
        rssi: Int = -50,
        channel: Int = 44,
        band: String = "5",
        isHidden: Bool = false
    ) -> NetworkSnapshot {
        NetworkSnapshot(
            timestamp: Date(),
            bssid: bssid,
            ssid: ssid,
            rssi: rssi,
            channel: channel,
            band: band,
            phyMode: "ax",
            channelWidth: "80",
            mcs: "11",
            nss: "2",
            security: "WPA2",
            country: "US",
            supportsK: true,
            supportsR: false,
            supportsV: true,
            supportsWPA3: false,
            isHiddenSSID: isHidden
        )
    }

    @Test func basicProperties() {
        let snap = makeSnapshot()
        #expect(snap.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(snap.ssid == "TestNet")
        #expect(snap.rssi == -50)
        #expect(snap.channel == 44)
        #expect(snap.band == "5")
        #expect(snap.channelWidthMHz == 80)
        #expect(snap.supportsK == true)
        #expect(snap.supportsR == false)
        #expect(snap.supportsWPA3 == false)
    }

    @Test func codableRoundTrip() throws {
        let original = makeSnapshot()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: data)
        #expect(decoded.bssid == original.bssid)
        #expect(decoded.ssid == original.ssid)
        #expect(decoded.rssi == original.rssi)
        #expect(decoded.channel == original.channel)
        #expect(decoded.band == original.band)
        #expect(decoded.channelWidthMHz == original.channelWidthMHz)
        #expect(decoded.supportsK == original.supportsK)
        #expect(decoded.isHiddenSSID == original.isHiddenSSID)
        #expect(decoded.timestamp == original.timestamp)
    }

    @Test func decoderFallback_missingBSSID() throws {
        var json = """
        {"timestamp":100,"ssid":"Net","rssi":-50,"channel":44,"band":"5","phyMode":"ax",
        "channelWidth":"80","mcs":"11","nss":"2","security":"WPA2","country":"US",
        "supportsK":true,"supportsR":false,"supportsV":true,"supportsWPA3":false}
        """
        json = json.replacingOccurrences(of: "\n", with: "")
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: data)
        #expect(decoded.bssid == "")
    }

    @Test func decoderFallback_missingSSID() throws {
        var json = """
        {"timestamp":100,"bssid":"aa:bb:cc","rssi":-50,"channel":44,"band":"5","phyMode":"ax",
        "channelWidth":"80","mcs":"11","nss":"2","security":"WPA2","country":"US",
        "supportsK":true,"supportsR":false,"supportsV":true,"supportsWPA3":false}
        """
        json = json.replacingOccurrences(of: "\n", with: "")
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: data)
        #expect(decoded.ssid == "")
    }

    @Test func decoderFallback_missingIsHiddenSSID() throws {
        var json = """
        {"timestamp":100,"bssid":"aa:bb:cc","ssid":"Net","rssi":-50,"channel":44,"band":"5","phyMode":"ax",
        "channelWidth":"80","mcs":"11","nss":"2","security":"WPA2","country":"US",
        "supportsK":true,"supportsR":false,"supportsV":true,"supportsWPA3":false}
        """
        json = json.replacingOccurrences(of: "\n", with: "")
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: data)
        #expect(decoded.isHiddenSSID == false)
    }

    @Test func decoderFallback_missingChannelWidthMHzUsesLabel() throws {
        let json = """
        {"timestamp":100,"bssid":"aa:bb:cc","ssid":"Net","rssi":-50,"channel":44,"band":"5","phyMode":"ac",
        "channelWidth":"80+80","mcs":"11","nss":"2","security":"WPA2","country":"US",
        "supportsK":false,"supportsR":false,"supportsV":false,"supportsWPA3":false}
        """
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: Data(json.utf8))
        #expect(decoded.channelWidthMHz == 80)
    }

    @Test func decoderFallback_missingChannelWidthMHzUsesConservativeDefault() throws {
        let json = """
        {"timestamp":100,"bssid":"aa:bb:cc","ssid":"Net","rssi":-50,"channel":44,"band":"5","phyMode":"ac",
        "channelWidth":"","mcs":"11","nss":"2","security":"WPA2","country":"US",
        "supportsK":false,"supportsR":false,"supportsV":false,"supportsWPA3":false}
        """
        let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: Data(json.utf8))
        #expect(decoded.channelWidthMHz == 20)
    }

    @Test func explicitScalarWidthPreservesGeometryWhenOperationLabelIsUnknown() {
        let snapshot = NetworkSnapshot(
            timestamp: Date(), bssid: "aa:bb:cc:dd:ee:80", ssid: "Unknown IE width",
            rssi: -50, channel: 36, band: "5", phyMode: "ac",
            channelWidth: "", channelWidthMHz: 80, mcs: "", nss: "", security: "",
            country: "", supportsK: false, supportsR: false,
            supportsV: false, supportsWPA3: false, isHiddenSSID: false
        )

        let series = SnapshotToChartAdapter.toSeriesData(
            snapshotsByBSSID: [snapshot.bssid: snapshot],
            band: .band5GHz,
            colorHasher: SSIDColorHasher()
        )

        #expect(series.first?.left == 34)
        #expect(series.first?.right == 50)
        #expect(series.first?.channelWidth == "")
    }
}

// MARK: - ChartSeriesData

struct ChartSeriesDataTests {

    @Test func displaySSID() {
        let d1 = ChartSeriesData(id: "1", ssid: "MyNet", bssid: "aa:bb:cc", channel: 1, left: 0, apex: 0.5, right: 1, rssi: -50)
        #expect(d1.displaySSID == "MyNet")

        let d2 = ChartSeriesData(id: "2", ssid: "", bssid: "aa:bb:dd", channel: 1, left: 0, apex: 0.5, right: 1, rssi: -50)
        #expect(d2.displaySSID == "n/a")
    }

    @Test func computedID() {
        let d = ChartSeriesData(id: "test-id", ssid: "Net", bssid: "aa:bb:cc", channel: 1, left: 0, apex: 0.5, right: 1, rssi: -50)
        #expect(d.id == "test-id")
        #expect(d.id == d.domain.id)
    }

    @Test func convenienceAccessors() {
        let d = ChartSeriesData(
            id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6,
            left: 0, apex: 1.5, right: 3, rssi: -70,
            phyMode: "ax", channelWidth: "80",
            supportsK: true, supportsR: true, supportsV: false,
            security: "WPA3", mcs: "11", nss: "2", country: "US"
        )
        #expect(d.channel == 6)
        #expect(d.apex == 1.5)
        #expect(d.phyMode == "ax")
        #expect(d.channelWidth == "80")
        #expect(d.supportsK == true)
        #expect(d.supportsR == true)
        #expect(d.supportsV == false)
        #expect(d.security == "WPA3")
        #expect(d.mcs == "11")
        #expect(d.nss == "2")
        #expect(d.country == "US")
    }

    @Test func renderStateMutability() {
        var d = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 1, left: 0, apex: 0.5, right: 1, rssi: -50)
        d.displayRSSI = -45.0
        d.qualityScore = 80
        d.trendArrow = "↑"
        d.trendDelta = 5
        d.isFilteredOut = true
        d.isVisible = false
        #expect(d.displayRSSI == -45.0)
        #expect(d.qualityScore == 80)
        #expect(d.trendArrow == "↑")
        #expect(d.trendDelta == 5)
        #expect(d.isFilteredOut == true)
        #expect(d.isVisible == false)
    }

    @Test func curvePointsCount() {
        let d = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6, left: 0, apex: 1.5, right: 3, rssi: -50)
        #expect(d.curvePoints.count == 81)
    }

    @Test func curvePointsAgreeWithSharedGaussianEnvelope() {
        let data = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6, left: 0, apex: 2, right: 4, rssi: -50)
        let envelope = GaussianEnvelope(
            leftX: Double(data.left),
            rightX: Double(data.right),
            peakY: Double(data.rssi),
            baselineY: Double(Constants.rssiNoiseFloor),
            sigma: Double(data.right - data.left) / 8.0
        )
        let points = data.curvePoints

        #expect(points.first?.x == envelope.leftX)
        #expect(points.first?.y == envelope.value(atX: envelope.leftX))
        #expect(points[points.count / 2].y == envelope.value(atX: (envelope.leftX + envelope.rightX) / 2.0))
        #expect(points.last?.x == envelope.rightX)
        #expect(points.last?.y == envelope.value(atX: envelope.rightX))
    }

    @Test func spectrumEnvelopeGeometryUsesTheSameGaussianDescriptorForAllViews() {
        let geometry = SpectrumEnvelopeGeometry(
            leftX: 5170,
            rightX: 5250,
            peakRSSI: -50,
            baselineRSSI: Double(Constants.rssiNoiseFloor)
        )
        let chartEnvelope = GaussianEnvelope(
            leftX: 5170,
            rightX: 5250,
            peakY: -50,
            baselineY: Double(Constants.rssiNoiseFloor),
            sigma: 10
        )

        #expect(geometry.gaussian == chartEnvelope)
    }

    @Test func curvePointsCentered() {
        let d = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6, left: 0, apex: 1.5, right: 4, rssi: -50)
        let points = d.curvePoints
        let midIndex = points.count / 2
        // Center should be near (left+right)/2 = 2
        let midX = points[midIndex].x
        #expect(abs(midX - 2.0) < 0.1)
        // Peak should be highest near center
        let peakY = points.map(\.y).max()!
        #expect(peakY > -100)
    }

    @Test func curvePointsRange() {
        let d = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6, left: 2, apex: 4, right: 6, rssi: -50, displayRSSI: -60)
        let curve = d.curvePoints
        let display = d.displayCurvePoints
        // X range should cover [left, right]
        #expect(curve.first!.x >= 2)
        #expect(curve.last!.x <= 6)
        #expect(display.first!.x >= 2)
        #expect(display.last!.x <= 6)
    }

    @Test func displayCurvePointsUsesDisplayRSSI() {
        var d = ChartSeriesData(id: "1", ssid: "Net", bssid: "aa:bb:cc", channel: 6, left: 0, apex: 1.5, right: 3, rssi: -50)
        d.displayRSSI = -40
        let points = d.displayCurvePoints
        let peakY = points.map(\.y).max()!
        // With displayRSSI=-40, amplitude = -40 - (-100) = 60, peak = -100 + 60 = -40
        #expect(abs(peakY - (-40)) < 1)
    }
}

// MARK: - SignalHistoryStore

@Suite @MainActor struct SignalHistoryStoreBehaviorTests {

    @Test func recordAndTrend() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        store.record(bssid: "aa:bb:cc", rssi: -60)
        let trend = store.trend(for: "aa:bb:cc")
        #expect(trend != nil)
        #expect(trend!.direction == .down)
        #expect(trend!.delta == -10)
    }

    @Test func trendUp() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -70)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        let trend = store.trend(for: "aa:bb:cc")
        #expect(trend!.direction == .up)
        #expect(trend!.delta == 20)
    }

    @Test func trendStable() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        store.record(bssid: "aa:bb:cc", rssi: -51)
        let trend = store.trend(for: "aa:bb:cc")
        #expect(trend!.direction == .stable)
        #expect(trend!.delta == -1)
    }

    @Test func trendNilWithSingleEntry() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        #expect(store.trend(for: "aa:bb:cc") == nil)
    }

    @Test func trendNilForUnknownBSSID() {
        let store = SignalHistoryStore(maxCount: 10)
        #expect(store.trend(for: "unknown") == nil)
    }

    @Test func rssiHistory() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        store.record(bssid: "aa:bb:cc", rssi: -60)
        store.record(bssid: "aa:bb:cc", rssi: -70)
        let history = store.rssiHistory(for: "aa:bb:cc")
        #expect(history == [-50, -60, -70])
    }

    @Test func rssiHistoryNilWithSingleEntry() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        #expect(store.rssiHistory(for: "aa:bb:cc") == nil)
    }

    @Test func snapshotHistory() {
        let store = SignalHistoryStore(maxCount: 10)
        let snap1 = NetworkSnapshot(timestamp: Date(), bssid: "aa:bb:cc", ssid: "Net", rssi: -50, channel: 6, band: "24", phyMode: "n", channelWidth: "20", mcs: "7", nss: "1", security: "WPA2", country: "US", supportsK: false, supportsR: false, supportsV: false, supportsWPA3: false, isHiddenSSID: false)
        let snap2 = NetworkSnapshot(timestamp: Date(), bssid: "aa:bb:cc", ssid: "Net", rssi: -60, channel: 6, band: "24", phyMode: "n", channelWidth: "20", mcs: "7", nss: "1", security: "WPA2", country: "US", supportsK: false, supportsR: false, supportsV: false, supportsWPA3: false, isHiddenSSID: false)
        store.record(bssid: "aa:bb:cc", rssi: -50, snapshot: snap1)
        store.record(bssid: "aa:bb:cc", rssi: -60, snapshot: snap2)
        let history = store.snapshotHistory(for: "aa:bb:cc")
        #expect(history != nil)
        #expect(history!.count == 2)
        #expect(history![0].rssi == -50)
        #expect(history![1].rssi == -60)
    }

    @Test func snapshotHistoryNilWithSingleEntry() {
        let store = SignalHistoryStore(maxCount: 10)
        let snap = NetworkSnapshot(timestamp: Date(), bssid: "aa:bb:cc", ssid: "Net", rssi: -50, channel: 6, band: "24", phyMode: "n", channelWidth: "20", mcs: "7", nss: "1", security: "WPA2", country: "US", supportsK: false, supportsR: false, supportsV: false, supportsWPA3: false, isHiddenSSID: false)
        store.record(bssid: "aa:bb:cc", rssi: -50, snapshot: snap)
        #expect(store.snapshotHistory(for: "aa:bb:cc") == nil)
    }

    @Test func snapshotRecordingOptional() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        store.record(bssid: "aa:bb:cc", rssi: -60)
        #expect(store.snapshotHistory(for: "aa:bb:cc") == nil)
        #expect(store.rssiHistory(for: "aa:bb:cc") != nil)
    }

    @Test func maxCountEviction() {
        let store = SignalHistoryStore(maxCount: 3)
        for i in 0..<5 {
            store.record(bssid: "aa:bb:cc", rssi: -50 - i)
        }
        let history = store.rssiHistory(for: "aa:bb:cc")
        #expect(history!.count == 3)
        #expect(history == [-52, -53, -54])
    }

    @Test func allHistory() {
        let store = SignalHistoryStore(maxCount: 10)
        store.record(bssid: "aa:bb:cc", rssi: -50)
        store.record(bssid: "dd:ee:ff", rssi: -60)
        #expect(store.allHistory.keys.count == 2)
    }

    @Test func allSnapshots() {
        let store = SignalHistoryStore(maxCount: 10)
        let snap = NetworkSnapshot(timestamp: Date(), bssid: "aa:bb:cc", ssid: "Net", rssi: -50, channel: 6, band: "24", phyMode: "n", channelWidth: "20", mcs: "7", nss: "1", security: "WPA2", country: "US", supportsK: false, supportsR: false, supportsV: false, supportsWPA3: false, isHiddenSSID: false)
        store.record(bssid: "aa:bb:cc", rssi: -50, snapshot: snap)
        #expect(store.allSnapshots.keys.count == 1)
    }
}
