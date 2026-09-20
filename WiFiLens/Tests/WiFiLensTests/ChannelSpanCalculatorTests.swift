import Foundation
import Testing
@testable import WiFi_Lens

struct ChannelSpanCalculatorTests {

    private func htOperationIE(
        primaryChannel: UInt8,
        offset: UInt8,
        staChannelWidthAny: Bool = false
    ) -> Data {
        var payload = [UInt8](repeating: 0, count: 22)
        payload[0] = primaryChannel
        payload[1] = (offset & 0x03) | (staChannelWidthAny ? 0x04 : 0)
        return Data([61, UInt8(payload.count)] + payload)
    }

    // MARK: - channelHalfSpan

    @Test func channelHalfSpanFor20MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 20) == 2)
    }

    @Test func channelHalfSpanFor40MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 40) == 4)
    }

    @Test func channelHalfSpanFor80MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 80) == 8)
    }

    @Test func channelHalfSpanFor160MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 160) == 16)
    }

    // MARK: - 20 MHz (any band)

    @Test func channelBlock20MHz24GHz() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 20, band: .band24GHz, spanDirection: nil)
        #expect(left == 4)
        #expect(right == 8)
    }

    @Test func channelBlock20MHz5GHz() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 20, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 102)
    }

    // MARK: - 2.4 GHz 40 MHz

    @Test func channelBlock24GHz40MHzHT40Plus() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 40, band: .band24GHz, spanDirection: .upper)
        #expect(left == 4)
        #expect(right == 12)
    }

    @Test func channelBlock24GHz40MHzHT40Minus() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 11, widthMHz: 40, band: .band24GHz, spanDirection: .lower)
        #expect(left == 5)
        #expect(right == 13)
    }

    @Test func channelBlock24GHz40MHzFallbackLowChannel() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 40, band: .band24GHz, spanDirection: nil)
        // primary <= 7 defaults to upper
        #expect(left == 4)
        #expect(right == 12)
    }

    @Test func channelBlock24GHz40MHzFallbackHighChannel() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 11, widthMHz: 40, band: .band24GHz, spanDirection: nil)
        // primary > 7 defaults to lower
        #expect(left == 5)
        #expect(right == 13)
    }

    // MARK: - 5 GHz 40 MHz blocks

    @Test func channelBlock5GHz40MHzCh36to40() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 42)
    }

    @Test func channelBlock5GHz40MHzCh44to48() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 44, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 42)
        #expect(right == 50)
    }

    @Test func channelBlock5GHz40MHzCh149to153() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 149, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 147)
        #expect(right == 155)
    }

    // MARK: - 5 GHz 80 MHz blocks

    @Test func channelBlock5GHz80MHzCh36to48() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 80, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 50)
    }

    @Test func channelBlock5GHz80MHzCh100to112() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 80, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 114)
    }

    // MARK: - 5 GHz 160 MHz blocks

    @Test func channelBlock5GHz160MHzCh36to64() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 66)
    }

    @Test func channelBlock5GHz160MHzCh100to128() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 130)
    }

    // Channel 144 has no 160 MHz block — falls back to simple spanning
    @Test func channelBlock5GHz160MHzCh144NoBlock() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 144, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        let half = ChannelSpanCalculator.channelHalfSpan(for: 160)
        #expect(left == 144 - half)
        #expect(right == 144 + half)
    }

    // MARK: - 6 GHz (IEEE 802.11ax containing blocks)

    @Test func channelBlock6GHz80MHzBlock() {
        // The scanned primary may be any 20 MHz primary inside the 80 MHz
        // block: 33/37/41/45 all resolve to the same block (31, 47).
        for ch in [33, 37, 41, 45] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 80, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 47)
        }
        let (l49, r49) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 49, widthMHz: 80, band: .band6GHz, spanDirection: nil)
        #expect(l49 == 47)
        #expect(r49 == 63)
    }

    @Test func channelBlock6GHz40MHzNonLowestPrimary() {
        // 37 and 33 share the 40 MHz block (31, 39).
        for ch in [33, 37] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 40, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 39)
        }
    }

    @Test func channelBlock6GHz160MHzNonLowestPrimary() {
        // 37 and 33 share the 160 MHz block (31, 63).
        for ch in [33, 37] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 160, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 63)
        }
    }

    @Test func channelBlock6GHz20MHzBlock() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 5, widthMHz: 20, band: .band6GHz, spanDirection: nil)
        #expect(left == 3)
        #expect(right == 7)
    }

    @Test func seriesWidthLabelDistinguishesKnown20FromUnknown() {
        let known20 = WiFiNetwork(
            ssid: "Known20",
            bssid: "AA:BB:CC:DD:EE:20",
            rssi: -50,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 20),
            ieData: htOperationIE(primaryChannel: 6, offset: 0)
        )
        let unknown = WiFiNetwork(
            ssid: "Unknown",
            bssid: "AA:BB:CC:DD:EE:21",
            rssi: -55,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 11, channelWidthMHz: 20),
            ieData: Data([61, 1, 11])
        )

        let series = ChannelSpanCalculator.toSeriesData(
            [known20, unknown],
            colorHasher: SSIDColorHasher()
        )

        #expect(series.first(where: { $0.bssid == known20.bssid })?.channelWidth == "20")
        #expect(series.first(where: { $0.bssid == unknown.bssid })?.channelWidth == "")
    }

    @Test func seriesUsesHTOperationDirectionFor24GHz40MHzGeometry() {
        let above = WiFiNetwork(
            ssid: "Above",
            bssid: "AA:BB:CC:DD:EE:22",
            rssi: -50,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 40),
            ieData: htOperationIE(primaryChannel: 6, offset: 1, staChannelWidthAny: true)
        )
        let below = WiFiNetwork(
            ssid: "Below",
            bssid: "AA:BB:CC:DD:EE:23",
            rssi: -55,
            // Deliberately disagree with the IE to verify the explicit BSS
            // operation direction takes precedence over CoreWLAN metadata.
            channel: WiFiChannel(
                band: .band24GHz,
                channelNumber: 11,
                channelWidthMHz: 40,
                spanDirection: .upper
            ),
            ieData: htOperationIE(primaryChannel: 11, offset: 3, staChannelWidthAny: true)
        )

        let series = ChannelSpanCalculator.toSeriesData(
            [above, below],
            colorHasher: SSIDColorHasher()
        )

        let aboveSeries = series.first(where: { $0.bssid == above.bssid })
        let belowSeries = series.first(where: { $0.bssid == below.bssid })
        #expect(aboveSeries?.left == 4)
        #expect(aboveSeries?.right == 12)
        #expect(belowSeries?.left == 5)
        #expect(belowSeries?.right == 13)
    }

    @Test func seriesLabelsVHT80Plus80WithoutInventingContiguousGeometry() {
        let network = WiFiNetwork(
            ssid: "VHT80Plus80",
            bssid: "AA:BB:CC:DD:EE:88",
            rssi: -50,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80),
            ieData: Data([192, 5, 3, 42, 106, 0, 0])
        )

        let series = ChannelSpanCalculator.toSeriesData(
            [network],
            colorHasher: SSIDColorHasher()
        )

        let item = series.first
        #expect(item?.channelWidth == "80+80")
        // Geometry stays on the existing CoreWLAN scalar width until segment
        // centers are modeled; it must not be widened to a contiguous 160.
        #expect(item?.left == 34)
        #expect(item?.right == 50)
    }
}
