import SwiftUI

enum ChannelViewMode: String, CaseIterable {
    case simple
    case table

    static func fromToolbarSelection(_ selection: SecondaryToolbarItemID) -> Self {
        switch selection {
        case .channelsSimple:
            .simple
        case .channelsTable:
            .table
        default:
            .simple
        }
    }

    var displayName: String {
        switch self {
        case .simple: String(localized: "channels.mode.simple", comment: "Simple view mode for channel quality")
        case .table:  String(localized: "channels.mode.professional", comment: "Professional view mode for channel quality")
        }
    }
}

struct ChannelQualityView: View {
    let channels: [ChannelRecommendation]
    let mode: ChannelViewMode
    @State private var sortKey: SortKey = .rfScore
    @State private var sortAscending: Bool = false
    @State private var selectedID: String?

    enum SortKey: String { case channel, bandDisplay, rfScore, rfLevel, apCount, coChannelCount, adjacentCount, overlapLevel, strongestNeighborRSSI, interferenceScore, classification }

    private var displayed: [ChannelRecommendation] {
        if mode == .simple {
            return channels.filter(\.showInSimpleView)
        }

        return channels.sorted { a, b in
            let cmp: Bool = switch sortKey {
            case .channel:              a.channel < b.channel
            case .bandDisplay:          a.bandDisplay < b.bandDisplay
            case .rfScore:             a.rfScore < b.rfScore
            case .rfLevel:             a.rfScore < b.rfScore
            case .apCount:              a.apCount < b.apCount
            case .coChannelCount:       a.coChannelCount < b.coChannelCount
            case .adjacentCount:        a.adjacentCount < b.adjacentCount
            case .overlapLevel:         a.overlapLevel.rawValue < b.overlapLevel.rawValue
            case .strongestNeighborRSSI: a.strongestNeighborRSSI < b.strongestNeighborRSSI
            case .interferenceScore:    a.interferenceScore < b.interferenceScore
            case .classification:       a.classification.order < b.classification.order
            }
            return sortAscending ? cmp : !cmp
        }
    }

    private var recommendationAvailability: ChannelRecommendationAvailability {
        .from(channels)
    }

    var body: some View {
        VStack(spacing: 0) {
            if channels.isEmpty {
                Spacer()
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text(String(localized: "spectrum.empty.no_channel_data", comment: "Empty state when no channel data exists"))
                    .foregroundColor(.secondary)
                Spacer()
            } else if mode == .simple {
                simpleList
            } else {
                tableView
            }
        }
        // Ideal dimensions are page layout hints, not a signal to resize the app window.
        // Do not pair them with scene-level `.windowResizability(.contentSize)`. The
        // minimums were removed because `minWidth: 700` forces the whole page to lay out
        // 700pt wide — wider than the ~600pt detail column at the minimum window size,
        // which clips the page's right edge.
        .frame(idealWidth: 1000, idealHeight: 700)
    }

    // MARK: - Recommendation Status

    private var recommendationStatusBanner: some View {
        Group {
            if !channels.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: recommendationAvailability.icon)
                        .font(.caption)
                        .foregroundColor(recommendationAvailability == .available ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recommendationAvailability.title)
                            .font(.caption.weight(.semibold))
                        Text(recommendationAvailability.message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Simple

    private var simpleList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                recommendationStatusBanner
                ForEach(displayed) { ch in
                    ChannelCard(channel: ch)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Table

    private var tableView: some View {
        ScrollView {
            VStack(spacing: 10) {
                recommendationStatusBanner
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        sortHeader(String(localized: "channels.table.col.ch", comment: "Channel column header (abbreviated)"), .channel)
                        sortHeader(String(localized: "channels.table.col.band", comment: "Band column header"), .bandDisplay)
                        sortHeader(String(localized: "channels.table.col.score", comment: "Quality score column header"), .rfScore)
                        sortHeader(String(localized: "channels.table.col.level", comment: "Quality level column header"), .rfLevel)
                        sortHeader(String(localized: "channels.table.col.aps", comment: "Access Point count column header"), .apCount)
                        sortHeader(String(localized: "channels.table.col.co_ch", comment: "Co-channel count column header"), .coChannelCount)
                        sortHeader(String(localized: "channels.table.col.adjacent", comment: "Adjacent channel count column header"), .adjacentCount)
                        sortHeader(String(localized: "channels.table.col.overlap", comment: "Overlap column header"), .overlapLevel)
                        sortHeader(String(localized: "channels.table.col.rssi", comment: "RSSI column header"), .strongestNeighborRSSI)
                        sortHeader(String(localized: "channels.table.col.interference", comment: "Interference column header"), .interferenceScore)
                        sortHeader(String(localized: "channels.table.col.class", comment: "Regulatory class column header"), .classification)
                    }
                    .background(.bar)

                    ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, ch in
                        Divider()
                        GridRow {
                            cell("\(ch.channel)", bold: ch.isCurrentChannel, color: ch.isCurrentChannel ? .accentColor : .primary)
                            cell(ch.bandDisplay)
                            cell("\(ch.rfScore)", color: Color(hex: ch.rfLevel.color))
                            cell(ch.rfLevel.displayName, color: Color(hex: ch.rfLevel.color))
                            cell("\(ch.apCount)")
                            cell("\(ch.coChannelCount)")
                            cell("\(ch.adjacentCount)")
                            cell(ch.overlapLevel.displayName)
                            cell("\(ch.strongestNeighborRSSI)")
                            cell("\(ch.interferenceScore)")
                            cell(ch.isRecommended ? "★" : ch.classification != .recommended ? ch.classification.displayName : "")
                        }
                        .background(rowBG(ch.id, idx: idx))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = ch.id }
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sortHeader(_ text: String, _ key: SortKey) -> some View {
        Button {
            if sortKey == key { sortAscending.toggle() }
            else { sortKey = key; sortAscending = true }
        } label: {
            HStack(spacing: 2) {
                Text(text)
                if sortKey == key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.medium))
            .foregroundColor(sortKey == key ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .accessibilityLabel(String(format: String(localized: "channels.accessibility.sort_by", comment: "Sort by column accessibility label"), text))
    }

    private func rowBG(_ id: String, idx: Int) -> Color {
        if selectedID == id { return .accentColor.opacity(0.25) }
        return idx.isMultiple(of: 2) ? .clear : .primary.opacity(0.04)
    }

    private func cell(_ text: String, bold: Bool = false, color: Color = .primary) -> some View {
        Text(text).font(bold ? .caption.weight(.semibold) : .caption)
            .foregroundColor(color).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 5)
    }
}

// MARK: - Card

private struct ChannelCard: View {
    let channel: ChannelRecommendation

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(Color(hex: channel.rfLevel.color).opacity(0.15))
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    Text("\(channel.channel)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(Color(hex: channel.rfLevel.color))
                }
                Text(channel.bandDisplay)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 54)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(channel.rfLevel.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: channel.rfLevel.color))
                    if channel.isRecommended { badge(String(localized: "channels.badge.recommended", comment: "Star badge marking recommended channel"), color: "#FF9F0A") }
                    if channel.isRecommended && !channel.recommendationReasons.isEmpty {
                        ReasonPopover(reasons: channel.recommendationReasons)
                    }
                    if channel.isCurrentChannel { badge(String(localized: "channels.badge.current", comment: "Dot badge marking current channel"), color: "#007AFF") }
                    if channel.classification == .advanced {
                        badge(String(localized: "channels.badge.dfs", comment: "Badge for DFS/advanced classification"), color: "#FF9F0A")
                    } else if channel.classification == .restricted {
                        badge(String(localized: "channels.classification.restricted", comment: "Restricted channel classification"), color: "#FF3B30")
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [Color(hex: channel.rfLevel.color).opacity(0.6), Color(hex: channel.rfLevel.color)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(channel.rfScore) / 100, height: 6)
                    }
                }
                .frame(height: 6)
                Text(String(format: String(localized: "format.score_fraction", comment: "Score value out of 100"), channel.rfScore))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Text(String(localized: "channels.card.co_label", comment: "Co-channel label on detail card"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("\(channel.coChannelCount)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text(String(localized: "channels.card.adj_label", comment: "Adjacent channel label on detail card"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("\(channel.adjacentCount)")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
                .minimumScaleFactor(0.8)
                .allowsTightening(true)

                HStack(spacing: 4) {
                    Image(systemName: "wave.3.right").font(.caption2).foregroundColor(.secondary)
                    Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), channel.strongestNeighborRSSI)).font(.caption).foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Text(channel.overlapLevel.displayName)
                        .font(.caption)
                        .foregroundColor(overlapColor(channel.overlapLevel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(overlapColor(channel.overlapLevel).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(String(localized: "channels.card.overlap_label", comment: "Overlap label on detail card"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                }
            }
            .layoutPriority(1)
        }
        .padding(12)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: String(localized: "channels.accessibility.card_label", comment: "Channel card accessibility label with channel, band, quality, and score"),
            channel.channel, channel.bandDisplay, channel.rfLevel.displayName, channel.rfScore))
    }

    private func badge(_ text: String, color: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(Color(hex: color))
    }

    private func overlapColor(_ level: ChannelQuality.OverlapLevel) -> Color {
        switch level {
        case .low: .green; case .moderate: .orange; case .high: .red
        }
    }
}
