import SwiftUI

/// Keeps live values fresh while retaining the positions established in this sheet.
struct APSelectionOrder {
    private var ids: [String] = []

    mutating func update(_ options: [APRadarAPOption]) {
        let available = Set(options.map(\.id))
        ids.removeAll { !available.contains($0) }
        let retained = Set(ids)
        ids.append(contentsOf: options.map(\.id).filter { !retained.contains($0) })
    }

    func arrange(_ options: [APRadarAPOption]) -> [APRadarAPOption] {
        let lookup = Dictionary(uniqueKeysWithValues: options.map { ($0.id, $0) })
        let retained = Set(ids)
        return ids.compactMap { lookup[$0] } + options.filter { !retained.contains($0.id) }
    }
}

/// Sheet that lets the user pick one access point from the shared scan
/// results. Reads live from the view model so the list refreshes when a new
/// scan arrives while the sheet is open; actions route back through closures.
/// Starts with the strongest APs and preserves row positions during live scans.
struct APSelectionView: View {
    @Bindable var viewModel: APRadarViewModel
    let onSelect: (APRadarAPOption) -> Void
    let onRescan: () -> Void
    let onCancel: () -> Void
    @State private var order = APSelectionOrder()

    /// Fixed sheet size keeps the picker consistent at any window size and
    /// prevents the list from growing the sheet beyond the window.
    private static let sheetSize = CGSize(width: 560, height: 500)

    private var options: [APRadarAPOption] {
        order.arrange(viewModel.selectionOptions)
    }

    private var selectedBSSID: String? {
        switch viewModel.state {
        case .idle: nil
        case .tracking(let snapshot): snapshot.target.bssid
        case .signalLost(let snapshot): snapshot.target.bssid
        }
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
                    LazyVStack(spacing: 8) {
                        ForEach(options) { option in
                            APSelectionRow(option: option, isSelected: option.bssid.uppercased() == selectedBSSID) {
                                onSelect(option)
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ap-radar-selection")
        .onAppear { order.update(viewModel.selectionOptions) }
        .onChange(of: viewModel.selectionOptions.map(\.id)) { _, _ in
            order.update(viewModel.selectionOptions)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.green.opacity(0.12), lineWidth: 1)
                    .frame(width: 48, height: 48)
                Circle().fill(Color.green.opacity(0.06))
                    .overlay(Circle().stroke(Color.green.opacity(0.20), lineWidth: 1))
                    .frame(width: 34, height: 34)
                Image(systemName: "wifi.router")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.green)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "apRadar.selectTarget", comment: "AP Radar selection sheet title"))
                    .font(.title3.weight(.semibold))
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
        .padding(.vertical, 16)
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

/// A quiet instrument row with a numeric signal reading and explicit selection.
private struct APSelectionRow: View {
    let option: APRadarAPOption
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                signalBars
                VStack(alignment: .leading, spacing: 5) {
                    Text(ssidLabel)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 6) {
                        Text(option.band.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        Text(channelLabel).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    Text(option.bssid).font(.caption.monospaced())
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: "\(option.rssi)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(verbatim: "dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: isSelected ? 16 : 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.green.opacity(0.06) : Color.primary.opacity(isHovering ? 0.05 : 0.025))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.green.opacity(0.35) : Color.primary.opacity(isHovering ? 0.12 : 0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(String(localized: "apRadar.selection.hint", comment: "VoiceOver hint explaining that tapping an access point starts tracking it"))
        .accessibilityIdentifier("ap-radar-option-\(option.bssid)")
    }

    private var ssidLabel: String {
        option.ssid ?? String(
            localized: "apRadar.target.hiddenNetwork",
            comment: "Label for an access point that hides its SSID"
        )
    }

    private var channelLabel: String {
        String(
            format: String(localized: "apRadar.target.channel", comment: "Access point channel, e.g. Channel 149"),
            option.channel
        )
    }

    /// Bar count carries signal strength without competing with the RSSI value.
    private var signalBars: some View {
        let active = option.rssi >= -85 ? (option.rssi >= -70 ? (option.rssi >= -55 ? 3 : 2) : 1) : 0
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < active ? Color.green : Color.secondary.opacity(0.15))
                    .frame(width: 4, height: CGFloat(6 + index * 4))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 34, height: 34)
        .background(Color.green.opacity(0.05), in: Circle())
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
