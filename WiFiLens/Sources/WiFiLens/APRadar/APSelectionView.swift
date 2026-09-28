import SwiftUI

/// Sheet that lets the user pick one access point from the shared scan
/// results. Reads live from the view model so the list refreshes when a new
/// scan arrives while the sheet is open; actions route back through closures.
/// Sorted by RSSI (strongest first), then SSID, then BSSID.
struct APSelectionView: View {
    @Bindable var viewModel: APRadarViewModel
    let onSelect: (APRadarAPOption) -> Void
    let onRescan: () -> Void
    let onCancel: () -> Void

    /// Fixed sheet size keeps the picker consistent at any window size and
    /// prevents the list from growing the sheet beyond the window.
    private static let sheetSize = CGSize(width: 560, height: 500)

    private var options: [APRadarAPOption] {
        viewModel.selectionOptions
    }

    private var isEmpty: Bool {
        viewModel.latestNetworks.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(options) { option in
                            APSelectionRow(option: option) {
                                onSelect(option)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ap-radar-selection")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "apRadar.selectTarget", comment: "AP Radar selection sheet title"))
                    .font(.headline)
                if !isEmpty {
                    Text(selectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button {
                onRescan()
            } label: {
                Label(
                    String(localized: "apRadar.rescan", comment: "Button to rescan for access points"),
                    systemImage: "arrow.clockwise"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "apRadar.rescan", comment: "Button to rescan for access points"))

            Button(String(localized: "common.action.cancel", comment: "Cancel action")) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var selectionSummary: String {
        String(
            format: String(localized: "apRadar.summary.available", comment: "Summary of APs visible to the selector, e.g. 12 access points available"),
            options.count
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Text(String(localized: "apRadar.empty.title", comment: "Empty state when no access points were found"))
                .font(.headline)

            Text(String(localized: "apRadar.empty.description", comment: "Empty state guidance when no access points were found"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                onRescan()
            } label: {
                Label(
                    String(localized: "apRadar.rescan", comment: "Button to rescan for access points"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single selectable AP row: signal bars, SSID/BSSID on the left, RSSI and
/// band/channel on the right. Uses the same RSSI color scale as Overview so
/// the sheet reads as part of the app.
private struct APSelectionRow: View {
    let option: APRadarAPOption
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                signalBars
                VStack(alignment: .leading, spacing: 2) {
                    Text(ssidLabel)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(option.bssid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rssiLabel)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(rssiColor)
                    Text(metadataLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "apRadar.selection.hint", comment: "VoiceOver hint explaining that tapping an access point starts tracking it"))
        .accessibilityIdentifier("ap-radar-option-\(option.bssid)")
    }

    private var ssidLabel: String {
        option.ssid ?? String(
            localized: "apRadar.target.hiddenNetwork",
            comment: "Label for an access point that hides its SSID"
        )
    }

    private var rssiLabel: String {
        String(
            format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"),
            option.rssi
        )
    }

    private var metadataLabel: String {
        [option.band.displayName, channelLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var channelLabel: String {
        String(
            format: String(localized: "apRadar.target.channel", comment: "Access point channel, e.g. Channel 149"),
            option.channel
        )
    }

    private var rssiColor: Color {
        if option.rssi >= -55 { return .green }
        if option.rssi >= -70 { return .yellow }
        if option.rssi >= -85 { return .orange }
        return .red
    }

    /// Three vertical bars matching OverviewView's signal meter.
    private var signalBars: some View {
        let active = option.rssi >= -85 ? (option.rssi >= -70 ? (option.rssi >= -55 ? 3 : 2) : 1) : 0
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < active ? rssiColor : Color.secondary.opacity(0.15))
                    .frame(width: 4, height: CGFloat(6 + index * 4))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 18)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let quality: String
        if option.rssi >= -55 {
            quality = String(localized: "overview.signal.strong", comment: "Strong signal level label")
        } else if option.rssi >= -70 {
            quality = String(localized: "overview.signal.good", comment: "Good signal level label")
        } else if option.rssi >= -85 {
            quality = String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier")
        } else {
            quality = String(localized: "overview.signal.weak", comment: "Weak signal level label")
        }
        let rssiText = String(
            format: String(localized: "roaming.accessibility.rssi_fmt", comment: "RSSI accessibility label with value and quality"),
            option.rssi,
            quality
        )
        return "\(ssidLabel), \(option.bssid), \(rssiText), \(option.band.displayName), \(channelLabel)"
    }
}
