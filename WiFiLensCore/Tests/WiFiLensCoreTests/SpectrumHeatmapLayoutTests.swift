import CoreGraphics
import Testing
@testable import WiFiLensCore
@Suite struct SpectrumHeatmapLayoutTests {
    private let rect = CGRect(x: 0, y: 0, width: 500, height: 200)

    @Test func channelDomainMatchesSpectrumChartCoordinateSpace() {
        let domain = SpectrumHeatmapLayout.channelDomain(
            channels: [36, 40, 44, 48, 149, 153, 157, 161, 165],
            band: .band5GHz
        )!
        #expect(domain.minChannelCoordinate == 1)
        #expect(domain.maxChannelCoordinate == 170)

        let ch36 = SpectrumHeatmapLayout.xPosition(
            forChannelCoordinate: 36,
            domain: domain,
            in: rect
        )!
        let ch48 = SpectrumHeatmapLayout.xPosition(
            forChannelCoordinate: 48,
            domain: domain,
            in: rect
        )!
        let ch149 = SpectrumHeatmapLayout.xPosition(
            forChannelCoordinate: 149,
            domain: domain,
            in: rect
        )!

        #expect(ch48 < ch149)
        #expect(abs(Double(ch48 - ch36) / 12.0 - Double(ch149 - ch48) / 101.0) < 0.01)
        #expect(SpectrumHeatmapLayout.channelCoordinate(forX: ch149, domain: domain, in: rect) == 149)
    }

    @Test func channelDomainHandlesSingletonAndEmptyInput() {
        let singleton = SpectrumHeatmapLayout.channelDomain(channels: [36], band: .band5GHz)!
        #expect(singleton.minChannelCoordinate == 1)
        #expect(singleton.maxChannelCoordinate == 170)
        #expect(SpectrumHeatmapLayout.xPosition(forChannelCoordinate: 36, domain: singleton, in: rect) != nil)

        let empty = SpectrumHeatmapLayout.channelDomain(channels: [], band: .band5GHz)
        #expect(empty == nil)
    }

    @Test func channelDomainContainsWideEnvelopeSupportWithoutRegulatoryClipping() {
        let domain = SpectrumHeatmapLayout.channelDomain(channels: [36, 40, 44, 48], band: .band5GHz)!
        let envelope = SpectrumHeatmapActivity.envelope(
            for: WiFiNetwork(
                ssid: "wide",
                bssid: "aa:bb:cc:dd:ee:01",
                rssi: -50,
                channel: WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 160)
            ),
            band: .band5GHz
        )!

        #expect(envelope.leftX == 34)
        #expect(envelope.rightX == 66)
        #expect(SpectrumHeatmapLayout.xPosition(forChannelCoordinate: envelope.leftX, domain: domain, in: rect) != nil)
        #expect(SpectrumHeatmapLayout.xPosition(forChannelCoordinate: envelope.rightX, domain: domain, in: rect) != nil)
    }

    @Test func legalJapaneseChannel14EnvelopeUsesCanonicalChannelCoordinates() {
        let legalJapaneseChannels = RegulatoryDomain.JP.allowedChannels(forBand: "24") ?? []
        #expect(legalJapaneseChannels.contains(14))

        let network = WiFiNetwork(
            ssid: "JP",
            bssid: "aa:bb:cc:dd:ee:14",
            rssi: -50,
            channel: WiFiChannel(band: .band24GHz, channelNumber: 14, channelWidthMHz: 20)
        )
        let envelope = SpectrumHeatmapActivity.envelope(for: network, band: .band24GHz)

        #expect(envelope?.leftX == 12)
        #expect(envelope?.rightX == 16)
        #expect(envelope.map { ($0.leftX + $0.rightX) / 2 } == 14)
    }

    @Test func frequencyMappingHasAnInverse() {
        let domain = SpectrumHeatmapLayout.channelDomain(channels: [1, 6, 11], band: .band24GHz)!
        let channel = 6.0
        let x = SpectrumHeatmapLayout.xPosition(forChannelCoordinate: channel, domain: domain, in: rect)!
        let roundTrip = SpectrumHeatmapLayout.channelCoordinate(forX: x, domain: domain, in: rect)!

        #expect(abs(roundTrip - channel) < 0.0001)
    }

    @Test func channelTicksUseOnlyProvidedLegalChannels() {
        let ticks = SpectrumHeatmapLayout.channelTicks(
            channels: [36, 40, 44, 48, 149, 153, 157, 161, 165],
            band: .band5GHz,
            in: rect,
            maximumCount: 4
        )

        #expect(!ticks.isEmpty)
        #expect(ticks.map(\.channel) == [1, 56, 111, 166])
    }

    @Test func channelTicksAreCappedAndUseSpectrumAxisValues() {
        let channels = [36, 40, 44, 48, 149, 153, 157, 161, 165, 169, 173, 177]
        let ticks = SpectrumHeatmapLayout.channelTicks(
            channels: channels,
            band: .band5GHz,
            in: rect,
            maximumCount: 20
        )
        #expect(ticks.count <= 10)
        #expect(ticks.first?.channel == 1)
        #expect(ticks.last?.channel == 166)
    }

    @Test func fixedRSSIProjectionHasExactRoundTrips() {
        let rssiRange = -100.0...(-30.0)
        for rssi in [-100.0, -70.0, -30.0] {
            let y = SpectrumHeatmapLayout.yPosition(forRSSI: rssi, in: rect, rssiRange: rssiRange)!
            let roundTrip = SpectrumHeatmapLayout.rssi(forY: y, in: rect, rssiRange: rssiRange)!
            #expect(abs(roundTrip - rssi) < 0.0001)
        }
        let bottomY = SpectrumHeatmapLayout.yPosition(forRSSI: -100, in: rect, rssiRange: rssiRange)!
        #expect(bottomY == rect.maxY)
        #expect(SpectrumHeatmapLayout.rssi(forY: bottomY, in: rect, rssiRange: rssiRange) == -100)
        #expect(SpectrumHeatmapLayout.yPosition(forRSSI: -120, in: rect, rssiRange: rssiRange) == rect.maxY)
        #expect(SpectrumHeatmapLayout.yPosition(forRSSI: -10, in: rect, rssiRange: rssiRange) == rect.minY)
    }

    @Test func inverseRSSIProjectionRejectsOutsidePlot() {
        let rssiRange = -100.0...(-30.0)
        #expect(SpectrumHeatmapLayout.rssi(forY: rect.minY - 1, in: rect, rssiRange: rssiRange) == nil)
        #expect(SpectrumHeatmapLayout.rssi(forY: rect.maxY + 1, in: rect, rssiRange: rssiRange) == nil)
    }

    @Test func invalidGeometryReturnsNoMapping() {
        let domain = SpectrumHeatmapLayout.channelDomain(channels: [], band: .band5GHz)
        #expect(domain == nil)
        #expect(SpectrumHeatmapLayout.channelCoordinate(forX: -1, domain: SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 170), in: rect) == nil)
    }
}
