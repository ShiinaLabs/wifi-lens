import Testing
@testable import WiFiLensCore

@Suite struct SpectrumPanelViewTypeTests {
    @Test func rawValues() {
        #expect(SpectrumPanelViewType.spectrum.rawValue == "spectrum")
        #expect(SpectrumPanelViewType.trend.rawValue == "trend")
        #expect(SpectrumPanelViewType.table.rawValue == "table")
        #expect(SpectrumPanelViewType.heatmap.rawValue == "heatmap")
    }

    @Test func displayNames() {
        for selection in SpectrumPanelViewType.allCases {
            #expect(!selection.displayName.isEmpty)
            #expect(selection.displayName != selection.rawValue)
        }
    }

    @Test func allCasesCount() {
        #expect(SpectrumPanelViewType.allCases.count == 4)
    }

    @Test func icons() {
        #expect(SpectrumPanelViewType.spectrum.icon == "wave.3.left")
        #expect(SpectrumPanelViewType.trend.icon == "chart.line.uptrend.xyaxis")
        #expect(SpectrumPanelViewType.table.icon == "tablecells")
        #expect(SpectrumPanelViewType.heatmap.icon == "square.grid.3x3.fill")
    }
}
