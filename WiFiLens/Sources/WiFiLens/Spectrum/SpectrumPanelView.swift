import SwiftUI
import WiFiLensCore

struct SpectrumPanelView: View {
    @Bindable var viewModel: ScannerViewModel
    let panelID: SpectrumPanelID
    let isVendorColumnAvailable: Bool
    @Binding var band: ChannelBand
    @Binding var chartType: SpectrumPanelViewType
    @Binding var selectedNetworkID: String?
    @Binding var sortOrder: [NSSortDescriptor]
    @Binding var hiddenColumns: Set<String>
    let canRemove: Bool
    let onRemove: (() -> Void)?

    init(
        viewModel: ScannerViewModel,
        panelID: SpectrumPanelID,
        isVendorColumnAvailable: Bool,
        band: Binding<ChannelBand>,
        chartType: Binding<SpectrumPanelViewType>,
        selectedNetworkID: Binding<String?>,
        sortOrder: Binding<[NSSortDescriptor]>,
        hiddenColumns: Binding<Set<String>>,
        canRemove: Bool = true,
        onRemove: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.panelID = panelID
        self.isVendorColumnAvailable = isVendorColumnAvailable
        self._band = band
        self._chartType = chartType
        self._selectedNetworkID = selectedNetworkID
        self._sortOrder = sortOrder
        self._hiddenColumns = hiddenColumns
        self.canRemove = canRemove
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            chartContent
        }
        .padding(.trailing, 8)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker(String(localized: "spectrum.panel.chart_type", comment: "Chart type picker label"), selection: $chartType) {
                ForEach(supportedViewTypes) { type in
                    Text(type.displayName)
                        .lineLimit(1)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .accessibilityIdentifier("spectrum.\(panelID.rawValue).view-picker")
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SpectrumControlGeometryPreferenceKey.self,
                        value: ["\(panelID.rawValue)-view-picker": proxy.frame(in: .named("wifi-lens.spectrum"))]
                    )
                }
            }

            switch chartType {
            case .spectrum:
                spectrumBandPicker
                bandPanel.toolbarContent
            case .trend:
                EmptyView()
            case .heatmap:
                bandPicker(label: String(localized: "spectrum.heatmap.band", comment: "Band picker label for the heatmap"))
                heatmapPanel.heatmapToolbarContent
            case .table:
                tablePanel.toolbarContent
            }

            Spacer()

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help(String(localized: "spectrum.dashboard.remove_panel", comment: "Button to remove a spectrum dashboard panel"))
                .accessibilityLabel(String(localized: "spectrum.dashboard.remove_panel", comment: "Button to remove a spectrum dashboard panel"))
                .accessibilityIdentifier("spectrum-dashboard-remove-panel-\(panelID.rawValue)")
            }
        }
        .frame(minHeight: 24)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var bandPanel: SpectrumBandPanel {
        SpectrumBandPanel(
            viewModel: viewModel,
            panelID: panelID,
            band: band,
            selectedNetworkID: $selectedNetworkID
        )
    }

    private var heatmapPanel: SpectrumHeatmapPanel {
        SpectrumHeatmapPanel(viewModel: viewModel, band: band)
    }

    private var spectrumBandPicker: some View {
        bandPicker(label: String(localized: "spectrum.heatmap.band", comment: "Band picker label for the spectrum"))
    }

    private func bandPicker(label: String) -> some View {
        let bands = Self.bandOptions(supportedBands: viewModel.supportedBands)

        return Group {
            if bands.isEmpty {
                Text(band.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Picker(
                    label,
                    selection: $band
                ) {
                    ForEach(bands, id: \.self) { option in
                        Text(option.displayName)
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .accessibilityIdentifier("spectrum.\(panelID.rawValue).band-picker")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SpectrumControlGeometryPreferenceKey.self,
                            value: ["\(panelID.rawValue)-band-picker": proxy.frame(in: .named("wifi-lens.spectrum"))]
                        )
                    }
                }
            }
        }
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        switch chartType {
        case .spectrum:
            bandPanel
        case .trend:
            SpectrumTrendPanel(
                viewModel: viewModel,
                selectedNetworkID: $selectedNetworkID
            )
        case .table:
            tablePanel
        case .heatmap:
            heatmapPanel
        }
    }

    private var tablePanel: SpectrumTablePanel {
        SpectrumTablePanel(
            viewModel: viewModel,
            isVendorColumnAvailable: isVendorColumnAvailable,
            sortOrder: $sortOrder,
            hiddenColumns: $hiddenColumns
        )
    }

    // MARK: - Helpers

    var supportedViewTypes: [SpectrumPanelViewType] {
        var types: [SpectrumPanelViewType] = viewModel.supportedBands.isEmpty ? [] : [.spectrum]
        types.append(.trend)
        types.append(.table)
        types.append(.heatmap)
        return types
    }

    static func bandOptions(supportedBands: Set<ChannelBand>) -> [ChannelBand] {
        ChannelBand.allCases.filter { supportedBands.contains($0) }
    }

}

struct SpectrumControlGeometryPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
