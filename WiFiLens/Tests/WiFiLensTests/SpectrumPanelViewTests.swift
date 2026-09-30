import Testing
import SwiftUI
import AppKit
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite @MainActor struct SpectrumPanelViewTests {
    @Test func spectrumPanelSelection() {
        let selection = SpectrumPanelViewType.spectrum
        #expect(selection.rawValue == "spectrum")
        #expect(!selection.displayName.isEmpty)
        #expect(selection.displayName != selection.rawValue)
    }

    @Test func bandPanelSelectionTrend() {
        let selection = SpectrumPanelViewType.trend
        #expect(selection.rawValue == "trend")
        #expect(!selection.displayName.isEmpty)
        #expect(selection.displayName != selection.rawValue)
    }

    @Test func bandPanelSelectionIconNames() {
        #expect(SpectrumPanelViewType.spectrum.icon == "wave.3.left")
        #expect(SpectrumPanelViewType.trend.icon == "chart.line.uptrend.xyaxis")
        #expect(SpectrumPanelViewType.table.icon == "tablecells")
        #expect(SpectrumPanelViewType.heatmap.icon == "square.grid.3x3.fill")
    }

    @Test func bandPanelSelectionHeatmap() {
        let selection = SpectrumPanelViewType.heatmap
        #expect(selection.rawValue == "heatmap")
        #expect(!selection.displayName.isEmpty)
        #expect(selection.displayName != selection.rawValue)
    }

    @Test func spectrumPanelIDHasTertiary() {
        #expect(SpectrumPanelID.tertiary.rawValue == "tertiary")
    }

    @Test func supportedViewTypesIncludeTable() {
        let vm = ScannerViewModel()
        vm.debugApplyNetworksForTesting([], supportedBands: [.band24GHz, .band5GHz, .band6GHz])
        let panel = SpectrumPanelView(
            viewModel: vm,
            panelID: .tertiary,
            isVendorColumnAvailable: true,
            band: .constant(.band24GHz),
            chartType: .constant(.table),
            selectedNetworkID: .constant(nil),
            sortOrder: .constant([]),
            hiddenColumns: .constant([])
        )
        #expect(panel.supportedViewTypes.contains(.table))
        #expect(panel.supportedViewTypes.contains(.trend))
        #expect(panel.supportedViewTypes.contains(.heatmap))
        #expect(panel.supportedViewTypes.contains(.spectrum))
    }

    @Test func bandPickerOptionsFollowSupportedBandsInDisplayOrder() {
        let options = SpectrumPanelView.bandOptions(
            supportedBands: [.band6GHz, .band24GHz]
        )

        #expect(options == [.band24GHz, .band6GHz])
    }
}
