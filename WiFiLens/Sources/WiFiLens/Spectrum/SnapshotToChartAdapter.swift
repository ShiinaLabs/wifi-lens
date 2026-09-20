import Foundation
import SwiftUI
import ChartLens

/// Converts recorded NetworkSnapshot data into ChartSeriesData for history playback.
/// Mirrors ChannelSpanCalculator.toSeriesData() but operates on snapshots instead of WiFiNetwork.
enum SnapshotToChartAdapter {

    /// Parse scalar channel widths for geometry. 80+80 remains non-contiguous
    /// and uses the existing narrow fallback until segment centers are modeled.
    static func channelWidthMHz(from widthStr: String) -> Int {
        switch widthStr {
        case "160": return 160
        case "80":  return 80
        case "40":  return 40
        case "20":  return 20
        default:    return 20
        }
    }

    /// For each BSSID in the session, find the snapshot whose timestamp is closest to `targetTime`.
    /// Returns a [bssid: single-snapshot] dict representing the session "slice" at that moment.
    static func snapshotsNearest(
        to targetTime: Date,
        in snapshots: [String: [NetworkSnapshot]]
    ) -> [String: NetworkSnapshot] {
        var result: [String: NetworkSnapshot] = [:]
        for (bssid, snaps) in snapshots {
            guard !snaps.isEmpty else { continue }
            var best = snaps[0]
            var bestDist = abs(best.timestamp.timeIntervalSince(targetTime))
            for snap in snaps.dropFirst() {
                let dist = abs(snap.timestamp.timeIntervalSince(targetTime))
                if dist < bestDist {
                    bestDist = dist
                    best = snap
                }
            }
            result[bssid] = best
        }
        return result
    }

    /// Convert a per-BSSID snapshot map (one snapshot per BSSID at a given time point)
    /// into ChartSeriesData array for a single band chart.
    static func toSeriesData(
        snapshotsByBSSID: [String: NetworkSnapshot],
        band: ChannelBand,
        colorHasher: SSIDColorHasher,
        trends: [String: (direction: TrendDirection, delta: Int)] = [:]
    ) -> [ChartSeriesData] {
        var series: [ChartSeriesData] = []
        for (bssid, snap) in snapshotsByBSSID {
            guard let snapBand = ChannelBand(id: snap.band), snapBand == band else { continue }

            let widthMHz = channelWidthMHz(from: snap.channelWidth)
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: snap.channel,
                widthMHz: widthMHz,
                band: band,
                spanDirection: nil
            )
            let apex = Double(left + right) / 2.0
            let stableID = "\(bssid)-\(snap.channel)-\(band.rawValue)"

            let trend = trends[bssid]
            let arrow: String = {
                switch trend?.direction {
                case .up:     return "▲"
                case .down:   return "▼"
                case .stable: return "●"
                case .none:   return ""
                }
            }()

            let domain = ChartSeriesDomainData(
                id: stableID,
                ssid: snap.ssid,
                bssid: bssid,
                channel: snap.channel,
                left: left,
                apex: apex,
                right: right,
                rssi: snap.rssi,
                phyMode: snap.phyMode,
                channelWidth: snap.channelWidth,
                supportsK: snap.supportsK,
                supportsR: snap.supportsR,
                supportsV: snap.supportsV,
                supportsWPA3: snap.supportsWPA3,
                isHiddenSSID: snap.isHiddenSSID,
                security: snap.security,
                mcs: snap.mcs,
                nss: snap.nss,
                country: snap.country
            )
            let render = ChartSeriesRenderState(
                displayRSSI: Double(snap.rssi),
                color: colorHasher.color(for: snap.ssid, bssid: bssid),
                isVisible: true,
                trendArrow: arrow,
                trendDelta: trend?.delta ?? 0
            )
            series.append(ChartSeriesData(domain: domain, render: render))
        }
        return series
    }
}
