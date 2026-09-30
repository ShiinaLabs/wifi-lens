import Foundation
import WiFiLensCore

enum ChannelSeriesDataBuilder {
    /// Convert an array of WiFiNetwork to ChartSeriesData suitable for Swift Charts.
    /// Malformed entries are silently skipped (defensive, matches Python behavior).
    static func toSeriesData(
        _ networks: [WiFiNetwork],
        colorHasher: SSIDColorHasher,
        trends: [String: (direction: TrendDirection, delta: Int)] = [:],
        displayStatesByID: [String: APDisplayState] = [:],
        hiddenBSSIDs: Set<String> = []
    ) -> [ChartSeriesData] {
        var series: [ChartSeriesData] = []
        for nw in networks {
            let band = nw.channel.band
            let reportedChannel = nw.channel.channelNumber
            let widthMHz = nw.channel.channelWidthMHz
            let ie = nw.ieData.map { IEParser.parse(data: $0) }
            // Prefer the explicit HT secondary-channel direction when it is
            // available; CoreWLAN remains the fallback for non-HT or unknown
            // operation data.
            let spanDir = ie?.htChannelOperation?.spanDirection ?? nw.channel.spanDirection

            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: reportedChannel,
                widthMHz: widthMHz,
                band: band,
                spanDirection: spanDir
            )

            let apex = Double(left + right) / 2.0

            // Stable ID across scans: caller guarantees no duplicate (bssid, channel, band) tuples
            let stableID = "\(nw.bssid)-\(reportedChannel)-\(band.rawValue)"

            let trend = trends[nw.bssid]
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
                ssid: nw.ssid ?? "n/a",
                bssid: nw.bssid,
                channel: reportedChannel,
                left: left,
                apex: apex,
                right: right,
                rssi: nw.rssi,
                phyMode: ie.map { phyLabel($0) } ?? "",
                channelWidth: ie.map { widthLabel($0) } ?? "",
                supportsK: ie?.supports80211k ?? false,
                supportsR: ie?.supports80211r ?? false,
                supportsV: ie?.supports80211v ?? false,
                supportsWPA3: ie?.supportsWPA3 ?? false,
                isHiddenSSID: ie?.isHiddenSSID ?? false,
                security: ie?.securitySummary ?? "",
                mcs: ie?.mcsSummary ?? "",
                nss: ie?.nssSummary ?? "",
                country: ie?.countryCode ?? ""
            )
            let render = ChartSeriesRenderState(
                displayRSSI: Double(nw.rssi),
                color: colorHasher.color(for: nw.ssid, bssid: nw.bssid),
                isVisible: displayStatesByID[stableID]?.visibility ?? !hiddenBSSIDs.contains(nw.bssid),
                visibilityLocked: displayStatesByID[stableID]?.visibilityLocked ?? false,
                trendArrow: arrow,
                trendDelta: trend?.delta ?? 0
            )

            series.append(ChartSeriesData(domain: domain, render: render))
        }
        return series
    }

    private static func phyLabel(_ ie: IEData) -> String {
        if ie.heSupported { return "ax" }
        if ie.vhtSupported { return "ac" }
        if ie.htSupported { return "n" }
        return ""
    }

    private static func widthLabel(_ ie: IEData) -> String {
        ie.operatingChannelWidth?.label ?? ""
    }
}
