import SwiftUI

struct SpectrumTablePanel: View {
    @Bindable var viewModel: ScannerViewModel
    let isVendorColumnAvailable: Bool
    @Binding var sortOrder: [NSSortDescriptor]
    @Binding var hiddenColumns: Set<String>

    var body: some View {
        tableContent
    }

    var toolbarContent: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $viewModel.hideHiddenSSIDs) {
                Text(String(localized: "spectrum.filter.hide_hidden", comment: "Toggle to hide networks with hidden SSIDs"))
                    .font(.body)
            }
            .toggleStyle(.checkbox)
            .controlSize(.regular)

            if !viewModel.combinedTableRows.isEmpty {
                Text(String(format: String(localized: "spectrum.panel.table_count_fmt", comment: "Network count in table toolbar"), viewModel.combinedTableRows.count))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var tableContent: some View {
        NativeTableView(
            rows: NetworkTableRowSorter.sort(
                viewModel.combinedTableRows,
                by: sortOrder
            ),
            selectedID: $viewModel.selectedNetworkID,
            sortOrder: $sortOrder,
            hiddenColumns: $hiddenColumns,
            isVendorColumnAvailable: isVendorColumnAvailable,
            onToggleVisibility: { seriesID in viewModel.toggleVisibility(seriesID: seriesID) },
            onToggleVisibilityLocked: { seriesID in viewModel.toggleVisibilityLocked(seriesID: seriesID) }
        )
    }
}
