import Foundation
import Testing
import SwiftUI
@testable import WiFi_Lens

@Suite @MainActor struct SpectrumHeatmapPanelTests {
    private func makeNetwork(
        bssid: String,
        rssi: Int = -50,
        band: ChannelBand = .band24GHz,
        channel: Int = 6,
        widthMHz: Int = 20,
        ssid: String? = "TestNet"
    ) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(
                band: band,
                channelNumber: channel,
                channelWidthMHz: widthMHz
            )
        )
    }

    private func applyCurrentScan(_ networks: [WiFiNetwork], to viewModel: ScannerViewModel) {
        viewModel.debugApplyNetworksForTesting(
            networks,
            supportedBands: Set(ChannelBand.allCases),
            timestamp: Date(timeIntervalSince1970: 100)
        )
    }

    @Test func panelConstructsForEveryBandAndKeepsToolbarLegend() {
        let viewModel = ScannerViewModel()

        for band in ChannelBand.allCases {
            let panel = SpectrumHeatmapPanel(viewModel: viewModel, band: band)
            _ = panel.body
            _ = panel.heatmapToolbarContent
        }
    }

    @Test func emptyCurrentScanUsesTheNormalEmptyState() {
        let model = SpectrumHeatmapModel(band: .band5GHz, channels: [36], envelopes: [])

        #expect(SpectrumHeatmapPanel.shouldShowEmptyState(for: model))
        #expect(!SpectrumHeatmapPanel.shouldShowEmptyState(for: SpectrumHeatmapModel(
            band: .band5GHz,
            channels: [36],
            envelopes: [SpectrumHeatmapEnvelope(
                leftX: 34,
                rightX: 38,
                peakRSSI: -50,
                baselineRSSI: -100
            )]
        )))
    }

    @Test func currentBandAggregateAccessibilityLabelUsesRSSIContext() {
        let label = SpectrumHeatmapPanel.aggregateAccessibilityLabel(for: .band5GHz)
        let normalized = label
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "дБм", with: "dBm")

        #expect(normalized.contains(ChannelBand.band5GHz.displayName))
        #expect(normalized.contains("RSSI"))
        #expect(normalized.contains("-100"))
        #expect(normalized.contains("-30 dBm"))
    }

    @Test func axesUseSpectrumRSSIRangeAndNoTimeLabels() {
        let range = SpectrumHeatmapLayout.rssiRange(for: [-45])
        #expect(SpectrumHeatmapPanel.rssiAxisLabels(for: range) == ["-100", "-90", "-80", "-70", "-60", "-50", "-40 dBm"])
        #expect(SpectrumHeatmapPanel.timeAxisLabels.isEmpty)
    }

    @Test func panelUsesStandardRasterStorageIndependentOfDisplaySize() {
        #expect(SpectrumHeatmapPanel.rasterResolution(for: CGSize(width: 80, height: 40)) == .standard)
        #expect(SpectrumHeatmapPanel.rasterResolution(for: CGSize(width: 2_000, height: 1_000)) == .standard)
    }

    @Test func maximumHeatmapColorIsWarmAndNotWhite() {
        let maximum = SpectrumHeatmapColor.components(forIntensity: 1)

        #expect(maximum.red == 1)
        #expect(maximum.green < 1)
        #expect(maximum.blue < 0.5)
    }

    @Test func currentScanProducesOneAnonymousEnvelopePerValidNetwork() {
        let viewModel = ScannerViewModel()
        applyCurrentScan([
            makeNetwork(bssid: "aa:bb:cc:dd:ee:01", rssi: -45, channel: 1),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:02", rssi: -90, channel: 11)
        ], to: viewModel)

        let model = viewModel.heatmapModel(for: .band24GHz)

        #expect(model.envelopes.count == 2)
        #expect(model.envelopes.allSatisfy { $0.leftX < $0.rightX })
        #expect(model.envelopes.allSatisfy { $0.peakRSSI == -45 || $0.peakRSSI == -90 })
    }

    @Test func currentScanEnvelopesRemainIsolatedByRequestedBand() {
        let viewModel = ScannerViewModel()
        applyCurrentScan([
            makeNetwork(bssid: "aa:bb:cc:dd:ee:01", band: .band24GHz, channel: 6),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:02", band: .band5GHz, channel: 36),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:03", band: .band6GHz, channel: 5)
        ], to: viewModel)

        #expect(viewModel.heatmapModel(for: .band24GHz).envelopes.map(\.leftX) == [4])
        #expect(viewModel.heatmapModel(for: .band5GHz).envelopes.map(\.leftX) == [34])
        #expect(viewModel.heatmapModel(for: .band6GHz).envelopes.map(\.leftX) == [3])
    }

    @Test func emptyCurrentScanProducesNoEnvelopes() {
        let viewModel = ScannerViewModel()
        applyCurrentScan([], to: viewModel)

        #expect(viewModel.heatmapModel(for: .band5GHz).envelopes.isEmpty)
    }

    @Test func filtersVisibilityAndSelectionDoNotChangeCurrentScanHeatmapInput() {
        let viewModel = ScannerViewModel()
        let network = makeNetwork(bssid: "aa:bb:cc:dd:ee:01", ssid: nil)
        applyCurrentScan([network], to: viewModel)
        let expected = viewModel.heatmapModel(for: .band24GHz)

        viewModel.globalFilterQuery = "does-not-match"
        viewModel.setFilterQuery("also-does-not-match", for: .primary)
        viewModel.hiddenBSSIDs.insert(network.bssid)
        viewModel.hiddenBands.insert(network.channel.band.id)
        viewModel.hideHiddenSSIDs = true
        viewModel.selectedNetworkID = network.id

        #expect(viewModel.heatmapModel(for: .band24GHz) == expected)
    }

    @Test func malformedAndOtherBandNetworksAreSkipped() {
        let viewModel = ScannerViewModel()
        applyCurrentScan([
            makeNetwork(bssid: "aa:bb:cc:dd:ee:01", channel: 6, widthMHz: 0),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:02", channel: 999),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:03", band: .band5GHz, channel: 36),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:04", channel: 11)
        ], to: viewModel)

        let envelopes = viewModel.heatmapModel(for: .band24GHz).envelopes

        #expect(envelopes.count == 1)
        #expect(envelopes[0].leftX == 9)
        #expect(envelopes[0].rightX == 13)
    }

    @Test func rejectsRSSIOutsideFixedRangeBeforeEnvelopeCreation() {
        let belowRange = makeNetwork(bssid: "aa:bb:cc:dd:ee:05", rssi: -101)
        let aboveRange = makeNetwork(bssid: "aa:bb:cc:dd:ee:06", rssi: -29)

        #expect(SpectrumHeatmapActivity.envelope(for: belowRange, band: .band24GHz) == nil)
        #expect(SpectrumHeatmapActivity.envelope(for: aboveRange, band: .band24GHz) == nil)
    }

    @Test func rejectsNonFiniteRSSIBeforeEnvelopeCreation() {
        let network = makeNetwork(bssid: "aa:bb:cc:dd:ee:07")

        #expect(SpectrumHeatmapActivity.envelope(for: network, rssi: Double.nan, band: .band24GHz) == nil)
        #expect(SpectrumHeatmapActivity.envelope(for: network, rssi: Double.infinity, band: .band24GHz) == nil)
        #expect(SpectrumHeatmapActivity.envelope(for: network, rssi: -Double.infinity, band: .band24GHz) == nil)
    }

    @Test func acceptsRSSIBoundariesForEnvelopeCreation() {
        let lowerBoundary = makeNetwork(bssid: "aa:bb:cc:dd:ee:08", rssi: -100)
        let upperBoundary = makeNetwork(bssid: "aa:bb:cc:dd:ee:09", rssi: -30)

        #expect(SpectrumHeatmapActivity.envelope(for: lowerBoundary, band: .band24GHz) != nil)
        #expect(SpectrumHeatmapActivity.envelope(for: upperBoundary, band: .band24GHz) != nil)
    }

    @Test func heatmapModelAndEnvelopesExposeNoAccessPointIdentityOrTimeline() {
        let modelFields = Set(Mirror(reflecting: SpectrumHeatmapModel(
            band: .band24GHz,
            channels: [1],
            envelopes: []
        )).children.compactMap(\.label))
        let envelopeFields = Set(Mirror(reflecting: SpectrumHeatmapEnvelope(
            leftX: 4,
            rightX: 8,
            peakRSSI: -50,
            baselineRSSI: -100
        )).children.compactMap(\.label))

        #expect(modelFields == ["band", "channels", "envelopes"])
        #expect(envelopeFields == ["leftX", "rightX", "peakRSSI", "baselineRSSI"])
    }
}
