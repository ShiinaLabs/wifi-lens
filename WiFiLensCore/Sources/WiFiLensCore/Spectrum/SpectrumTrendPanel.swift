import SwiftUI

struct SpectrumTrendPanel: View {
    let viewModel: ScannerViewModel
    @Binding var selectedNetworkID: String?

    var body: some View {
        Group {
            if let selID = selectedNetworkID,
               let snaps = viewModel.snapshots(for: selID),
               let color = selectedNetworkColor(for: selID),
               snaps.count >= 2 {
                TrendChartView(snapshots: snaps, color: color)
            } else {
                VStack {
                    Spacer()
                    Text(String(localized: "spectrum.panel.select_network_for_trend", comment: "Placeholder when no network is selected for trend chart"))
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }

    private func selectedNetworkColor(for networkID: String) -> Color? {
        guard let network = viewModel.deduplicatedNetworks.first(where: { $0.id == networkID }) else { return nil }
        return viewModel.colorHasher.color(for: network.ssid, bssid: network.bssid)
    }
}
