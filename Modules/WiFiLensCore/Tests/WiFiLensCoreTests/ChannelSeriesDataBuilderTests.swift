import Foundation
import Testing
@testable import WiFiLensCore
struct ChannelSeriesDataBuilderTests {
    private func htOperationIE(primaryChannel: UInt8, offset: UInt8, staChannelWidthAny: Bool = false) -> Data {
        var payload = [UInt8](repeating: 0, count: 22)
        payload[0] = primaryChannel
        payload[1] = (offset & 0x03) | (staChannelWidthAny ? 0x04 : 0)
        return Data([61, UInt8(payload.count)] + payload)
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

        let series = ChannelSeriesDataBuilder.toSeriesData(
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

        let series = ChannelSeriesDataBuilder.toSeriesData(
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

        let series = ChannelSeriesDataBuilder.toSeriesData(
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
