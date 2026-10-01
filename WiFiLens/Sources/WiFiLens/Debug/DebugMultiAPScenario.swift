import Foundation
import WiFiLensCore

#if DEBUG

enum DebugTrend: String, Codable, CaseIterable, Equatable {
    case none
    case up
    case down
    case stable

    var arrow: String {
        switch self {
        case .none: ""
        case .up: "▲"
        case .down: "▼"
        case .stable: "●"
        }
    }

    var title: String {
        switch self {
        case .none: "None"
        case .up: "Up"
        case .down: "Down"
        case .stable: "Stable"
        }
    }
}

enum DebugScenarioPreset: String, CaseIterable, Codable, Identifiable {
    case labelCollision
    case dense24GHz
    case wide5GHzOverlap
    case sparse6GHz
    case hiddenAndFiltered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .labelCollision: "Label collision"
        case .dense24GHz: "Dense 2.4 GHz"
        case .wide5GHzOverlap: "5 GHz wide overlap"
        case .sparse6GHz: "6 GHz sparse"
        case .hiddenAndFiltered: "Hidden and filtered"
        }
    }
}

struct DebugScenario: Codable, Equatable {
    var version: Int
    var bandID: String
    var presetID: String?
    var aps: [DebugAPConfig]
}

struct DebugAPConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var enabled: Bool
    var ssid: String
    var bssidSuffix: String
    var channel: Int
    var widthMHz: Int
    var rssi: Int
    var colorHex: String
    var hiddenSSID: Bool
    var visible: Bool
    var filtered: Bool
    var supportsK: Bool
    var supportsR: Bool
    var supportsV: Bool
    var supportsWPA3: Bool
    var country: String
    var trend: DebugTrend
    var trendDelta: Int
}

struct DebugChartSeriesSource {
    var ap: DebugAPConfig
    var domain: ChartSeriesDomainData
}

struct DebugScenarioStore {
    static let storageKey = "debug.multiAPChart.scenario.v1"

    var defaults: UserDefaults = .standard

    func load() -> DebugScenario {
        guard let data = defaults.data(forKey: Self.storageKey),
              let scenario = try? JSONDecoder().decode(DebugScenario.self, from: data),
              scenario.version == DebugScenarioBuilder.currentVersion
        else {
            return DebugScenarioBuilder.scenario(for: .labelCollision)
        }
        return DebugScenarioBuilder.normalized(scenario)
    }

    func save(_ scenario: DebugScenario) {
        guard let data = try? JSONEncoder().encode(DebugScenarioBuilder.normalized(scenario)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

enum DebugScenarioBuilder {
    static let currentVersion = 1

    static func scenario(for preset: DebugScenarioPreset) -> DebugScenario {
        switch preset {
        case .labelCollision:
            return DebugScenario(version: currentVersion, bandID: ChannelBand.band5GHz.id, presetID: preset.id, aps: [
                ap("Collision-A", suffix: "A1", channel: 52, width: 40, rssi: -45, color: "#3B82F6", trend: .up, delta: 3),
                ap("Collision-B", suffix: "A2", channel: 56, width: 40, rssi: -47, color: "#10B981", trend: .down, delta: -2),
                ap("Collision-C", suffix: "A3", channel: 60, width: 40, rssi: -49, color: "#F59E0B", trend: .stable, delta: 0),
                ap("Collision-D", suffix: "A4", channel: 64, width: 40, rssi: -51, color: "#EF4444"),
                ap("Collision-E", suffix: "A5", channel: 56, width: 80, rssi: -55, color: "#8B5CF6"),
            ])
        case .dense24GHz:
            return DebugScenario(version: currentVersion, bandID: ChannelBand.band24GHz.id, presetID: preset.id, aps: [
                ap("Kitchen", suffix: "24", channel: 1, width: 20, rssi: -42, color: "#3B82F6", k: true, v: true),
                ap("Living", suffix: "25", channel: 6, width: 20, rssi: -48, color: "#10B981", k: true, r: true),
                ap("Office", suffix: "26", channel: 11, width: 20, rssi: -54, color: "#F59E0B"),
                ap("Guest", suffix: "27", channel: 6, width: 40, rssi: -62, color: "#EF4444", filtered: true),
                ap("IoT", suffix: "28", channel: 1, width: 20, rssi: -68, color: "#8B5CF6", hidden: true),
            ])
        case .wide5GHzOverlap:
            return DebugScenario(version: currentVersion, bandID: ChannelBand.band5GHz.id, presetID: preset.id, aps: [
                ap("DFS-80", suffix: "51", channel: 52, width: 80, rssi: -43, color: "#2563EB", k: true, r: true, v: true, wpa3: true),
                ap("DFS-40", suffix: "52", channel: 60, width: 40, rssi: -57, color: "#16A34A"),
                ap("UNII-160", suffix: "53", channel: 100, width: 160, rssi: -64, color: "#EA580C"),
                ap("Upper-80", suffix: "54", channel: 149, width: 80, rssi: -70, color: "#7C3AED"),
            ])
        case .sparse6GHz:
            return DebugScenario(version: currentVersion, bandID: ChannelBand.band6GHz.id, presetID: preset.id, aps: [
                ap("6E-Lab-A", suffix: "61", channel: 37, width: 80, rssi: -46, color: "#0EA5E9", wpa3: true),
                ap("6E-Lab-B", suffix: "62", channel: 85, width: 160, rssi: -58, color: "#22C55E", wpa3: true),
                ap("6E-Lab-C", suffix: "63", channel: 181, width: 80, rssi: -73, color: "#F97316", wpa3: true),
            ])
        case .hiddenAndFiltered:
            return DebugScenario(version: currentVersion, bandID: ChannelBand.band5GHz.id, presetID: preset.id, aps: [
                ap("Visible", suffix: "71", channel: 36, width: 80, rssi: -41, color: "#3B82F6", k: true),
                ap("", suffix: "72", channel: 44, width: 40, rssi: -53, color: "#10B981", hidden: true),
                ap("Filtered", suffix: "73", channel: 149, width: 80, rssi: -60, color: "#F59E0B", filtered: true),
                ap("Invisible", suffix: "74", channel: 157, width: 40, rssi: -67, color: "#EF4444", visible: false),
            ])
        }
    }

    static func defaultAP(for band: ChannelBand, index: Int) -> DebugAPConfig {
        let channel: Int = switch band {
        case .band24GHz: 6
        case .band5GHz: 52
        case .band6GHz: 37
        }
        return ap("Debug-\(index)", suffix: String(format: "%02X", index), channel: channel, width: 20, rssi: -55, color: "#3B82F6")
    }

    static func allowedWidths(for band: ChannelBand) -> [Int] {
        band == .band24GHz ? [20, 40] : [20, 40, 80, 160]
    }

    static func normalized(_ scenario: DebugScenario) -> DebugScenario {
        let band = ChannelBand(id: scenario.bandID) ?? .band5GHz
        return DebugScenario(
            version: currentVersion,
            bandID: band.id,
            presetID: scenario.presetID,
            aps: scenario.aps.map { normalized($0, band: band) }
        )
    }

    static func normalized(_ ap: DebugAPConfig, band: ChannelBand) -> DebugAPConfig {
        var copy = ap
        copy.channel = min(max(copy.channel, 1), band.maxChannel)
        copy.widthMHz = validWidth(copy.widthMHz, for: band)
        copy.rssi = min(max(copy.rssi, Constants.rssiNoiseFloor), -1)
        copy.colorHex = normalizedHex(copy.colorHex)
        copy.country = String(copy.country.prefix(2)).uppercased()
        return copy
    }

    static func seriesSources(from scenario: DebugScenario, band: ChannelBand) -> [DebugChartSeriesSource] {
        normalized(scenario).aps
            .filter(\.enabled)
            .map { ap in
                let normalizedAP = normalized(ap, band: band)
                let block = ChannelSpanCalculator.channelBlock(
                    primaryChannel: normalizedAP.channel,
                    widthMHz: normalizedAP.widthMHz,
                    band: band
                )
                let domain = ChartSeriesDomainData(
                    id: "\(normalizedAP.id.uuidString)-\(band.id)",
                    ssid: normalizedAP.ssid,
                    bssid: bssid(from: normalizedAP.bssidSuffix),
                    channel: normalizedAP.channel,
                    left: block.left,
                    apex: Double(block.left + block.right) / 2.0,
                    right: block.right,
                    rssi: normalizedAP.rssi,
                    phyMode: "ax",
                    channelWidth: "\(normalizedAP.widthMHz)",
                    supportsK: normalizedAP.supportsK,
                    supportsR: normalizedAP.supportsR,
                    supportsV: normalizedAP.supportsV,
                    supportsWPA3: normalizedAP.supportsWPA3,
                    isHiddenSSID: normalizedAP.hiddenSSID,
                    security: normalizedAP.supportsWPA3 ? "WPA3" : "WPA2",
                    mcs: "",
                    nss: "",
                    country: normalizedAP.country
                )
                return DebugChartSeriesSource(ap: normalizedAP, domain: domain)
            }
    }

    static func band(for scenario: DebugScenario) -> ChannelBand {
        ChannelBand(id: scenario.bandID) ?? .band5GHz
    }

    private static func ap(
        _ ssid: String,
        suffix: String,
        channel: Int,
        width: Int,
        rssi: Int,
        color: String,
        hidden: Bool = false,
        visible: Bool = true,
        filtered: Bool = false,
        k: Bool = false,
        r: Bool = false,
        v: Bool = false,
        wpa3: Bool = false,
        trend: DebugTrend = .none,
        delta: Int = 0
    ) -> DebugAPConfig {
        DebugAPConfig(
            id: UUID(),
            enabled: true,
            ssid: ssid,
            bssidSuffix: suffix,
            channel: channel,
            widthMHz: width,
            rssi: rssi,
            colorHex: color,
            hiddenSSID: hidden,
            visible: visible,
            filtered: filtered,
            supportsK: k,
            supportsR: r,
            supportsV: v,
            supportsWPA3: wpa3,
            country: "",
            trend: trend,
            trendDelta: delta
        )
    }

    private static func validWidth(_ width: Int, for band: ChannelBand) -> Int {
        let allowed = allowedWidths(for: band)
        return allowed.contains(width) ? width : 20
    }

    private static func normalizedHex(_ colorHex: String) -> String {
        let trimmed = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard trimmed.count == 6, trimmed.allSatisfy(\.isHexDigit) else { return "#3B82F6" }
        return "#\(trimmed)"
    }

    private static func bssid(from suffix: String) -> String {
        let hex = suffix.uppercased().filter(\.isHexDigit)
        let lastByte = String(hex.suffix(2)).leftPadding(toLength: 2, withPad: "0")
        return "02:00:00:00:00:\(lastByte)"
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad pad: String) -> String {
        guard count < toLength else { return self }
        return String(repeating: pad, count: toLength - count) + self
    }
}

#endif
