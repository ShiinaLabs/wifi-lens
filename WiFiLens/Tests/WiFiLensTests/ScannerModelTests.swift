import Foundation
import Testing
@testable import WiFi_Lens

// MARK: - ChannelBand

struct ChannelBandTests {

    @Test func allCasesCount() {
        #expect(ChannelBand.allCases.count == 3)
    }

    @Test func band24GHzProperties() {
        #expect(ChannelBand.band24GHz.rawValue == 1)
        #expect(ChannelBand.band24GHz.id == "24")
        #expect(ChannelBand.band24GHz.maxChannel == 16)
    }

    @Test func band5GHzProperties() {
        #expect(ChannelBand.band5GHz.rawValue == 2)
        #expect(ChannelBand.band5GHz.id == "5")
        #expect(ChannelBand.band5GHz.maxChannel == 170)
    }

    @Test func band6GHzProperties() {
        #expect(ChannelBand.band6GHz.rawValue == 3)
        #expect(ChannelBand.band6GHz.id == "6")
        #expect(ChannelBand.band6GHz.maxChannel == 233)
    }

    @Test func displayNameNonEmpty() {
        for band in ChannelBand.allCases {
            #expect(!band.displayName.isEmpty)
        }
    }

    @Test func initWithValidID() {
        #expect(ChannelBand(id: "24") == .band24GHz)
        #expect(ChannelBand(id: "5") == .band5GHz)
        #expect(ChannelBand(id: "6") == .band6GHz)
    }

    @Test func initWithInvalidIDReturnsNil() {
        #expect(ChannelBand(id: "invalid") == nil)
        #expect(ChannelBand(id: "") == nil)
        #expect(ChannelBand(id: "2.4") == nil)
    }
}

// MARK: - SpanDirection

struct SpanDirectionTests {

    @Test func rawValues() {
        #expect(SpanDirection.upper.rawValue == "upper")
        #expect(SpanDirection.lower.rawValue == "lower")
    }
}

// MARK: - WiFiChannel (DEBUG init)

struct WiFiChannelTests {

    @Test func basicProperties() {
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 44, channelWidthMHz: 80, spanDirection: .upper)
        #expect(ch.band == .band5GHz)
        #expect(ch.channelNumber == 44)
        #expect(ch.channelWidthMHz == 80)
        #expect(ch.spanDirection == .upper)
    }

    @Test func defaultChannelWidth() {
        let ch = WiFiChannel(band: .band24GHz, channelNumber: 6)
        #expect(ch.channelWidthMHz == 20)
        #expect(ch.spanDirection == nil)
    }

    @Test func nilSpanDirection() {
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, spanDirection: nil)
        #expect(ch.spanDirection == nil)
    }

    @Test func differentBands() {
        let ch24 = WiFiChannel(band: .band24GHz, channelNumber: 1)
        let ch5 = WiFiChannel(band: .band5GHz, channelNumber: 36)
        let ch6 = WiFiChannel(band: .band6GHz, channelNumber: 1)
        #expect(ch24.band == .band24GHz)
        #expect(ch5.band == .band5GHz)
        #expect(ch6.band == .band6GHz)
    }
}

// MARK: - WiFiNetwork (DEBUG init)

struct WiFiNetworkTests {

    private func makeChannel(band: ChannelBand = .band5GHz, channel: Int = 44) -> WiFiChannel {
        WiFiChannel(band: band, channelNumber: channel, channelWidthMHz: 20)
    }

    @Test func basicProperties() {
        let channel = makeChannel()
        let network = WiFiNetwork(ssid: "TestNet", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: channel)
        #expect(network.ssid == "TestNet")
        #expect(network.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(network.rssi == -50)
        #expect(network.isIBSS == false)
        #expect(network.ieData == nil)
    }

    @Test func computedID() {
        let channel = makeChannel(band: .band5GHz, channel: 44)
        let network = WiFiNetwork(ssid: "Test", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: channel)
        #expect(network.id == "aa:bb:cc:dd:ee:ff-44-2")
    }

    @Test func nilSSID() {
        let channel = makeChannel()
        let network = WiFiNetwork(ssid: nil, bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: channel)
        #expect(network.ssid == nil)
    }

    @Test func ieDataPreserved() {
        let channel = makeChannel()
        let data = Data([0x01, 0x02, 0x03])
        let network = WiFiNetwork(ssid: "Test", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: channel, ieData: data)
        #expect(network.ieData == data)
    }

    @Test func uniqueIDForDifferentChannels() {
        let ch1 = WiFiChannel(band: .band5GHz, channelNumber: 44)
        let ch2 = WiFiChannel(band: .band5GHz, channelNumber: 48)
        let n1 = WiFiNetwork(ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: ch1)
        let n2 = WiFiNetwork(ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: ch2)
        #expect(n1.id != n2.id)
    }

    @Test func uniqueIDForDifferentBands() {
        let ch5 = WiFiChannel(band: .band5GHz, channelNumber: 6)
        let ch24 = WiFiChannel(band: .band24GHz, channelNumber: 6)
        let n1 = WiFiNetwork(ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: ch5)
        let n2 = WiFiNetwork(ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, channel: ch24)
        #expect(n1.id != n2.id)
    }
}

// MARK: - ScannerViewModel behavior

@Suite("ScannerViewModel behavior") @MainActor struct ScannerViewModelBehaviorTests {
    private func makeNetwork(ssid: String?, bssid: String, band: ChannelBand, channel: Int, rssi: Int = -50) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(band: band, channelNumber: channel, channelWidthMHz: 20)
        )
    }

    @Test("cached totals and table rows reflect the latest scan")
    func cachedDerivedDataReflectsScan() {
        let vm = ScannerViewModel()
        vm.debugApplyNetworksForTesting(
            [
                makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1),
                makeNetwork(ssid: "B", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6),
                makeNetwork(ssid: "C", bssid: "00:11:22:33:44:03", band: .band5GHz, channel: 36),
            ],
            supportedBands: Set([.band24GHz, .band5GHz])
        )

        #expect(vm.cachedTotalNetworks == 3)
        #expect(vm.cachedCombinedTableRows.count == 3)
        #expect(vm.cachedBandSummary.contains(": 2"))
        #expect(vm.cachedBandSummary.contains(": 1"))
    }

    @Test("table width labels distinguish known 20 MHz from unknown")
    func tableWidthLabelsDistinguishKnown20FromUnknown() {
        var ht20 = [UInt8](repeating: 0, count: 22)
        ht20[0] = 6
        ht20[1] = 0
        let known20 = WiFiNetwork(
            ssid: "Known20",
            bssid: "00:11:22:33:44:20",
            rssi: -50,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 6),
            ieData: Data([61, UInt8(ht20.count)] + ht20)
        )
        let unknown = WiFiNetwork(
            ssid: "Unknown",
            bssid: "00:11:22:33:44:21",
            rssi: -55,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 11),
            ieData: Data([61, 1, 11])
        )
        let vht80 = WiFiNetwork(
            ssid: "VHT80",
            bssid: "00:11:22:33:44:80",
            rssi: -52,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 36),
            ieData: Data([192, 5, 1, 42, 0, 0, 0])
        )
        let vm = ScannerViewModel()

        vm.debugApplyNetworksForTesting([known20, unknown, vht80], supportedBands: [.band24GHz, .band5GHz])

        let rowsByID = Dictionary(uniqueKeysWithValues: vm.cachedCombinedTableRows.map { ($0.id, $0) })
        #expect(rowsByID[known20.id]?.channelWidth == "20")
        #expect(rowsByID[unknown.id]?.channelWidth == "")
        #expect(rowsByID[vht80.id]?.channelWidth == "80")
    }

    @Test("caches update when a new scan arrives")
    func cachesUpdateOnNewScan() {
        let vm = ScannerViewModel()
        let a = makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let b = makeNetwork(ssid: "B", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)
        let c = makeNetwork(ssid: "C", bssid: "00:11:22:33:44:03", band: .band24GHz, channel: 11)

        vm.debugApplyNetworksForTesting([a, b], supportedBands: Set([.band24GHz]))
        #expect(vm.cachedTotalNetworks == 2)

        vm.debugApplyNetworksForTesting([a, b, c], supportedBands: Set([.band24GHz]))
        #expect(vm.cachedTotalNetworks == 3)
        #expect(vm.cachedCombinedTableRows.count == 3)
    }

    @Test("hiding a band invalidates cached row visibility")
    func hiddenBandsInvalidateCachedRows() {
        let vm = ScannerViewModel()
        let a = makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let c = makeNetwork(ssid: "C", bssid: "00:11:22:33:44:03", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([a, c], supportedBands: Set([.band24GHz, .band5GHz]))
        #expect(vm.cachedTotalNetworks == 2)
        #expect(vm.cachedCombinedTableRows.allSatisfy { $0.isVisible })

        vm.hiddenBands = ["24"]
        vm.applyGlobalFilterToBands()

        #expect(vm.cachedTotalNetworks == 2) // Counts unchanged; visibility is per-row.
        let rowsByID = Dictionary(uniqueKeysWithValues: vm.cachedCombinedTableRows.map { ($0.id, $0) })
        #expect(rowsByID[a.id]?.isVisible == false) // 2.4 GHz band hidden.
        #expect(rowsByID[c.id]?.isVisible == true)  // 5 GHz band still visible.
    }

    @Test("visibility and lock toggles invalidate cached rows")
    func togglesInvalidateCachedRows() {
        let vm = ScannerViewModel()
        let a = makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        vm.debugApplyNetworksForTesting([a], supportedBands: Set([.band24GHz]))

        #expect(vm.cachedCombinedTableRows.first?.isVisible == true)

        vm.toggleVisibility(seriesID: a.id)
        #expect(vm.cachedCombinedTableRows.first?.isVisible == false)
        #expect(vm.cachedCombinedTableRows.first?.visibilityLocked == false)

        vm.toggleVisibilityLocked(seriesID: a.id)
        #expect(vm.cachedCombinedTableRows.first?.visibilityLocked == true)
    }

    @Test("panel filter does not mutate cached rows")
    func panelFilterKeepsCachedRowsStable() {
        let vm = ScannerViewModel()
        let a = makeNetwork(ssid: "Alpha", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        vm.debugApplyNetworksForTesting([a], supportedBands: Set([.band24GHz]))

        vm.setFilterQuery("Alpha", for: .primary)

        #expect(vm.cachedCombinedTableRows.map(\.id) == [a.id])
        #expect(vm.cachedCombinedTableRows.first?.isVisible == true)
        #expect(vm.cachedTotalNetworks == 1)
    }

    @Test("same BSSID on different bands keeps separate rows")
    func crossBandSameBSSIDKeepsBothRows() {
        let vm = ScannerViewModel()
        let n24 = makeNetwork(ssid: "Home", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let n5 = makeNetwork(ssid: "Home", bssid: "00:11:22:33:44:01", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([n24, n5], supportedBands: Set([.band24GHz, .band5GHz]))

        #expect(vm.cachedCombinedTableRows.count == 2)
        #expect(vm.cachedTotalNetworks == 2)
    }

    @Test("duplicate BSSID/channel/band keeps the strongest RSSI")
    func duplicateKeepsStrongestRSSI() {
        let vm = ScannerViewModel()
        let weak = makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1, rssi: -70)
        let strong = makeNetwork(ssid: "A", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1, rssi: -45)

        vm.debugApplyNetworksForTesting([weak, strong], supportedBands: Set([.band24GHz]))

        #expect(vm.cachedCombinedTableRows.count == 1)
        #expect(vm.cachedCombinedTableRows.first?.rssi == -45)
        #expect(vm.cachedTotalNetworks == 1)
    }

    @Test("BSSID visibility rebuild does not duplicate signal history")
    func bssidVisibilityRebuildKeepsSignalHistoryStable() {
        let vm = ScannerViewModel()
        let firstScan = Date(timeIntervalSince1970: 100)
        let secondScan = Date(timeIntervalSince1970: 110)
        let thirdScan = Date(timeIntervalSince1970: 120)
        let network = makeNetwork(
            ssid: "History",
            bssid: "00:11:22:33:44:01",
            band: .band24GHz,
            channel: 1
        )
        let weakerNetwork = makeNetwork(
            ssid: "History",
            bssid: "00:11:22:33:44:01",
            band: .band24GHz,
            channel: 1,
            rssi: -58
        )

        vm.debugApplyNetworksForTesting(
            [network],
            supportedBands: [.band24GHz],
            timestamp: firstScan
        )
        vm.debugApplyNetworksForTesting(
            [weakerNetwork],
            supportedBands: [.band24GHz],
            timestamp: secondScan
        )

        vm.toggleVisibility(bssid: network.bssid)

        #expect(vm.hiddenBSSIDs == [network.bssid])
        #expect(vm.signalHistory.allHistory[network.bssid] == [-50, -58])
        #expect(
            vm.signalHistory.allSnapshots[network.bssid]?.map(\.timestamp) == [firstScan, secondScan]
        )
        #expect(vm.cachedCombinedTableRows.first?.isVisible == false)

        vm.debugApplyNetworksForTesting(
            [weakerNetwork],
            supportedBands: [.band24GHz],
            timestamp: thirdScan
        )

        #expect(vm.signalHistory.allHistory[network.bssid] == [-50, -58, -58])
        #expect(
            vm.signalHistory.allSnapshots[network.bssid]?.map(\.timestamp)
                == [firstScan, secondScan, thirdScan]
        )
    }
}
