import SwiftUI

struct SpectrumBandPanel: View {
    let viewModel: ScannerViewModel
    let panelID: SpectrumPanelID
    let band: ChannelBand
    @Binding var selectedNetworkID: String?

    var bandVM: BandChartViewModel {
        viewModel.bandViewModel(for: panelID, band: band)
    }

    var filterQueryBinding: Binding<String> {
        Binding(
            get: { viewModel.filterQuery(for: panelID) },
            set: { viewModel.setFilterQuery($0, for: panelID) }
        )
    }

    var totalCount: Int {
        bandVM.networkCount
    }

    var displayedCount: Int {
        bandVM.visibleSeriesData().count
    }

    var hiddenCount: Int {
        totalCount - displayedCount
    }

    var body: some View {
        chart
    }

    var toolbarContent: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "spectrum.panel.filter_placeholder", comment: "Filter input placeholder"), text: filterQueryBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            if hiddenCount > 0 {
                Text("\(displayedCount)/\(totalCount)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            if !filterQueryBinding.wrappedValue.isEmpty {
                Button {
                    filterQueryBinding.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "spectrum.filter.clear", comment: "Clear filter button"))
                .help(String(localized: "spectrum.filter.clear", comment: "Clear filter button"))
            }

            Spacer()
        }
    }

    private var chart: some View {
        WiFiBandChart(
            model: bandVM.renderModel,
            selectedNetworkID: $selectedNetworkID,
            onResetZoom: { bandVM.resetZoom() },
            onToggleExpand: { bandVM.toggleExpand() },
            onApplyZoom: { lo, hi in bandVM.applyZoom(lo: lo, hi: hi) }
        )
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        bandVM.chartSize = geometry.size
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        bandVM.chartSize = newSize
                    }
            }
        }
    }
}
