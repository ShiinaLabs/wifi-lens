import AppKit

enum NetworkTableRowSorter {
    static func sort(
        _ rows: [NetworkTableRow],
        by sortOrder: [NSSortDescriptor]
    ) -> [NetworkTableRow] {
        guard !sortOrder.isEmpty else { return rows }
        return rows.sorted { a, b in
            for descriptor in sortOrder {
                let result = compare(a, b, key: descriptor.key ?? "", ascending: descriptor.ascending)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return false
        }
    }

    private static func compare(
        _ a: NetworkTableRow,
        _ b: NetworkTableRow,
        key: String,
        ascending: Bool
    ) -> ComparisonResult {
        let cmp: ComparisonResult
        switch key {
        case "ssid": cmp = a.ssid.localizedCaseInsensitiveCompare(b.ssid)
        case "vendor": cmp = a.vendor.localizedCaseInsensitiveCompare(b.vendor)
        case "bandLabel": cmp = a.bandLabel.localizedCaseInsensitiveCompare(b.bandLabel)
        case "channel": cmp = a.channel < b.channel ? .orderedAscending : a.channel > b.channel ? .orderedDescending : .orderedSame
        case "rssi": cmp = a.rssi > b.rssi ? .orderedAscending : a.rssi < b.rssi ? .orderedDescending : .orderedSame
        case "bssid": cmp = a.bssid.localizedCaseInsensitiveCompare(b.bssid)
        case "phyMode": cmp = a.phyMode.localizedCaseInsensitiveCompare(b.phyMode)
        case "channelWidth":
            let aWidth = channelWidthSortValue(a.channelWidth)
            let bWidth = channelWidthSortValue(b.channelWidth)
            cmp = aWidth < bWidth ? .orderedAscending : aWidth > bWidth ? .orderedDescending : .orderedSame
        case "supportsK": cmp = a.supportsK == b.supportsK ? .orderedSame : a.supportsK ? .orderedDescending : .orderedAscending
        case "supportsR": cmp = a.supportsR == b.supportsR ? .orderedSame : a.supportsR ? .orderedDescending : .orderedAscending
        case "supportsV": cmp = a.supportsV == b.supportsV ? .orderedSame : a.supportsV ? .orderedDescending : .orderedAscending
        case "isHiddenSSID": cmp = a.isHiddenSSID == b.isHiddenSSID ? .orderedSame : a.isHiddenSSID ? .orderedDescending : .orderedAscending
        case "qualityScore": cmp = a.qualityScore > b.qualityScore ? .orderedAscending : a.qualityScore < b.qualityScore ? .orderedDescending : .orderedSame
        case "security": cmp = a.security.localizedCaseInsensitiveCompare(b.security)
        case "mcs": cmp = (Int(a.mcs) ?? 0) < (Int(b.mcs) ?? 0) ? .orderedAscending : (Int(a.mcs) ?? 0) > (Int(b.mcs) ?? 0) ? .orderedDescending : .orderedSame
        case "nss": cmp = (Int(a.nss) ?? 0) < (Int(b.nss) ?? 0) ? .orderedAscending : (Int(a.nss) ?? 0) > (Int(b.nss) ?? 0) ? .orderedDescending : .orderedSame
        case "country": cmp = a.country.localizedCaseInsensitiveCompare(b.country)
        case "lastSeen": cmp = a.lastSeen.localizedCaseInsensitiveCompare(b.lastSeen)
        default: cmp = .orderedSame
        }
        if ascending { return cmp }
        switch cmp {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }

    private static func channelWidthSortValue(_ width: String) -> Int {
        switch width {
        case "80+80": return 80
        default: return Int(width) ?? 0
        }
    }
}
