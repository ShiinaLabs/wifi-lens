import SwiftUI

struct SpectrumPanelContainer: View {
    let viewModel: ScannerViewModel
    @Binding var descriptor: SpectrumPanelDescriptor
    let isVendorColumnAvailable: Bool
    let canRemove: Bool
    @Binding var selectedNetworkID: String?
    @Binding var sortOrder: [NSSortDescriptor]
    @Binding var hiddenColumns: Set<String>
    let onRemove: () -> Void

    init(
        viewModel: ScannerViewModel,
        descriptor: Binding<SpectrumPanelDescriptor>,
        isVendorColumnAvailable: Bool,
        canRemove: Bool,
        selectedNetworkID: Binding<String?>,
        sortOrder: Binding<[NSSortDescriptor]>,
        hiddenColumns: Binding<Set<String>>,
        onRemove: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self._descriptor = descriptor
        self.isVendorColumnAvailable = isVendorColumnAvailable
        self.canRemove = canRemove
        self._selectedNetworkID = selectedNetworkID
        self._sortOrder = sortOrder
        self._hiddenColumns = hiddenColumns
        self.onRemove = onRemove
    }

    var body: some View {
        SpectrumPanelView(
            viewModel: viewModel,
            panelID: descriptor.id,
            isVendorColumnAvailable: isVendorColumnAvailable,
            band: $descriptor.band,
            chartType: $descriptor.viewType,
            selectedNetworkID: $selectedNetworkID,
            sortOrder: $sortOrder,
            hiddenColumns: $hiddenColumns,
            canRemove: canRemove,
            onRemove: onRemove
        )
        .onAppear(perform: normalizeBand)
        .onChange(of: viewModel.supportedBands) { _, _ in normalizeBand() }
    }

    private func normalizeBand() {
        guard !viewModel.supportedBands.isEmpty,
              !viewModel.supportedBands.contains(descriptor.band),
              let replacement = viewModel.supportedBands.min(by: { $0.rawValue < $1.rawValue }) else {
            return
        }

        descriptor.band = replacement
    }
}
