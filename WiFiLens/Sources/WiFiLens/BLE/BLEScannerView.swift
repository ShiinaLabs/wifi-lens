import SwiftUI
import WiFiLensCore

struct BLEScannerView: View {
    let viewModel: BLEViewModel?
    let bleEnabled: Bool

    var body: some View {
        if let viewModel {
            BLEScannerContentView(viewModel: viewModel)
        } else {
            BLEDisabledView()
        }
    }
}

private struct BLEDisabledView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "ble.disabled.title", comment: "Title when BLE feature is disabled in settings"))
                .font(.title3)
                .multilineTextAlignment(.center)
            // .fixedSize(vertical:) is unsafe on this text: it reports the height needed at
            // the *minimum* proposed width, wrapping into a ~1400pt column that SwiftUI then
            // imposes as the main window's minimum height.
            Text(String(localized: "ble.disabled.description", comment: "Description prompting user to enable BLE in settings"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("ble-disabled-state")
        .accessibilityElement(children: .contain)
    }
}

private struct BLEScannerContentView: View {
    @Bindable var viewModel: BLEViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.bluetoothState == .poweredOff {
                bluetoothOffView
            } else if viewModel.bluetoothState == .unauthorized
                        || viewModel.bluetoothPermission.authorizationStatus == .denied
                        || viewModel.bluetoothPermission.authorizationStatus == .restricted {
                unauthorizedView
            } else if viewModel.bluetoothPermission.authorizationStatus == .notDetermined {
                permissionRequiredView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                interferenceBanner
                if viewModel.devices.isEmpty {
                    scanningEmptyView
                } else {
                    contentView
                }
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            deviceTable
            if let history = viewModel.selectedDeviceHistory, history.count >= 2 {
                Divider()
                trendChartSection(history)
            }
        }
    }

    private var deviceTable: some View {
        Table(viewModel.displayedDevices, selection: $viewModel.selectedDeviceID) {
            TableColumn(String(localized: "common.label.name", comment: "Name column header")) { device in
                HStack(spacing: 4) {
                    Circle()
                        .fill(rssiColor(device.smoothedRSSI))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(device.displayName)
                        .font(.body)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 160)

            TableColumn(String(localized: "ble.table.col.identifier", comment: "Device identifier column header")) { device in
                Text(device.shortIdentifier)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn(String(localized: "channels.table.col.rssi", comment: "RSSI column header")) { device in
                HStack(spacing: 4) {
                    Text("\(device.rssi)")
                        .font(.body.monospaced().bold())
                    Text(String(localized: "ble.table.unit.dbm", comment: "dBm unit label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 60, ideal: 70)

            TableColumn(String(localized: "ble.table.col.smoothed", comment: "Smoothed RSSI column header")) { device in
                Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), Int(device.smoothedRSSI.rounded())))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            .width(min: 70, ideal: 80)

            TableColumn(String(localized: "ble.table.col.ads", comment: "Advertisement count column header")) { device in
                Text("\(device.advertisementCount)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            .width(min: 30, ideal: 40)

            TableColumn(String(localized: "ble.table.col.last_seen", comment: "Last seen time column header")) { device in
                Text(formatTimeAgo(device.lastSeen))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 80)
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
    }

    private func trendChartSection(_ history: [BLERSSISample]) -> some View {
        let chartColor = rssiColor(viewModel.selectedDevice?.smoothedRSSI ?? -50)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let device = viewModel.selectedDevice {
                    Circle()
                        .fill(chartColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(String(format: String(localized: "ble.rssi_history_fmt", comment: "RSSI history chart title with device name"), device.displayName))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle().fill(chartColor.opacity(0.3)).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(String(localized: "ble.trend.raw", comment: "Raw RSSI chart label")).font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(chartColor).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(String(localized: "ble.trend.smooth", comment: "Smoothed RSSI chart label")).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)

            BLETrendChartView(
                samples: history,
                color: chartColor
            )
            .id(viewModel.selectedDeviceID ?? "")
            .padding(.horizontal, 16)

            HStack(spacing: 16) {
                if let first = history.first {
                    LabeledContent(String(localized: "common.label.first", comment: "First data point label")) {
                        Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), first.rawRSSI))
                            .font(.caption.monospaced())
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                if let last = history.last {
                    LabeledContent(String(localized: "common.label.latest", comment: "Latest/most recent data point label")) {
                        Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), last.rawRSSI))
                            .font(.caption.monospaced())
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                if let device = viewModel.selectedDevice {
                    LabeledContent(String(localized: "common.label.samples_title", comment: "Sample count column header or title")) {
                        Text("\(history.count)")
                            .font(.caption.monospaced())
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    LabeledContent(String(localized: "ble.trend.ema", comment: "EMA (Exponential Moving Average) abbreviation")) {
                        Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), Int(device.smoothedRSSI.rounded())))
                            .font(.caption.monospaced().bold())
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Interference tip

    private var interferenceBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(String(localized: "ble.banner.interference", comment: "Info banner about BLE and 2.4 GHz Wi-Fi interference"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: - Empty / error states

    private var scanningEmptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text(String(localized: "ble.empty.scanning", comment: "Status while scanning for BLE devices"))
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var bluetoothOffView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)
            Text(String(localized: "ble.state.bluetooth_off_title", comment: "Title when Bluetooth is disabled"))
                .font(.body)
                .foregroundColor(.secondary)
            Text(String(localized: "ble.state.bluetooth_off_desc", comment: "Instructions to enable Bluetooth"))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
            Spacer()
        }
    }

    private var unauthorizedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "hand.raised.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)
            Text(String(localized: "ble.state.bluetooth_perm_denied_title", comment: "Title when Bluetooth permission is denied"))
                .font(.body)
                .foregroundColor(.secondary)
            Text(String(localized: "ble.state.bluetooth_perm_denied_desc", comment: "Instructions to grant Bluetooth permission"))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var permissionRequiredView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)
            Text(String(localized: "ble.state.bluetooth_perm_required_title", comment: "Title when Bluetooth permission is needed"))
                .font(.body)
                .foregroundColor(.secondary)
            Text(String(localized: "ble.state.bluetooth_perm_required_desc", comment: "Detailed instructions to grant Bluetooth permission"))
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func rssiColor(_ rssi: Double) -> Color {
        switch rssi {
        case ..<(-80): .red
        case ..<(-60): .yellow
        default:       .green
        }
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        switch delta {
        case ..<1:   return String(localized: "common.label.now", comment: "Just now timestamp indicator")
        case ..<60:  return String(format: String(localized: "format.seconds_ago", comment: "Relative time: N seconds ago"), Int(delta))
        case ..<3600: return String(format: String(localized: "format.minutes_ago", comment: "Relative time: N minutes ago"), Int(delta / 60))
        default:     return String(localized: "symbol.em_dash", comment: "Em dash symbol used as placeholder")
        }
    }
}
