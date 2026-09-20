import SwiftUI
import ChartLens

@MainActor
@Observable
final class BandChartViewModel {

    /// Set by the app root to respect Reduce Motion accessibility setting.
    nonisolated(unsafe) static var reduceMotion = false

    let band: ChannelBand

    var isExpanded: Bool = false
    var zoomMin: Double?
    var zoomMax: Double?

    private(set) var allSeriesData: [ChartSeriesData] = []
    private(set) var displayedSeriesData: [ChartSeriesData] = []
    private(set) var interfaceName: String = ""
    private(set) var currentFilterQuery: String = ""
    private(set) var allSnapshots: [String: [NetworkSnapshot]] = [:]
    private(set) var channelOccupancy: [Int: Int] = [:]
    private var currentHiddenBands: Set<String> = []
    private var currentHideHiddenSSIDs: Bool = false
    private var animationTimer: Timer?
    var chartSize: CGSize = .zero

    var hasFilter: Bool { !currentFilterQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    var networkCount: Int { allSeriesData.count }
    var isEmpty: Bool { allSeriesData.isEmpty }

    var xDataMin: Int { band == .band24GHz ? -1 : 1 }
    var xDataMax: Int { band.maxChannel }
    var yMin: Double { Double(Constants.rssiNoiseFloor) }
    var axisTickStartChannel: Int { 1 }

    var renderModel: BandChartRenderModel {
        BandChartRenderModel(
            xDataMin: xDataMin,
            xDataMax: xDataMax,
            yMin: yMin,
            visibleSeriesData: visibleSeriesData(),
            displayedSeriesData: displayedSeriesData,
            strongestRSSI: strongestRSSI(),
            isEmpty: isEmpty,
            zoomMin: zoomMin,
            zoomMax: zoomMax,
            isExpanded: isExpanded,
            axisTickStartChannel: axisTickStartChannel
        )
    }

    init(band: ChannelBand) {
        self.band = band
    }

    private func makeDisplayedSeriesData(from source: [ChartSeriesData], hiddenBands: Set<String>, hideHiddenSSIDs: Bool) -> [ChartSeriesData] {
        let needle = currentFilterQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let bandHidden = hiddenBands.contains(band.id)
        return source.map { series in
            var series = series
            let sourceFilteredOut = series.isFilteredOut
            let textFilter = needle.isEmpty
                || series.ssid.lowercased().contains(needle)
                || series.bssid.lowercased().contains(needle)
            let hiddenSSIDFilter = !hideHiddenSSIDs || !series.isHiddenSSID
            series.isFilteredOut = sourceFilteredOut || bandHidden || !textFilter || !hiddenSSIDFilter
            return series
        }
    }

    private func refreshRenderedState() {
        displayedSeriesData = makeDisplayedSeriesData(
            from: allSeriesData,
            hiddenBands: currentHiddenBands,
            hideHiddenSSIDs: currentHideHiddenSSIDs
        )
    }

    func validateSelection(_ selectedNetworkID: String?) -> Bool {
        guard let selectedNetworkID else { return true }
        return allSeriesData.contains { $0.id == selectedNetworkID }
    }

    func snapshots(for selectedNetworkID: String?) -> [NetworkSnapshot]? {
        guard let selectedNetworkID,
              let series = displayedSeriesData.first(where: { $0.id == selectedNetworkID })
        else { return nil }
        return allSnapshots[series.bssid]
    }

    func series(for selectedNetworkID: String?) -> ChartSeriesData? {
        guard let selectedNetworkID else { return nil }
        return displayedSeriesData.first(where: { $0.id == selectedNetworkID })
    }

    func visibleSeriesData() -> [ChartSeriesData] {
        displayedSeriesData.filter(\.isVisible)
    }

    func strongestRSSI() -> Int {
        Int(visibleSeriesData().map(\.displayRSSI).max() ?? 0)
    }

    // MARK: - RSSI animation

    var isViewVisible = false {
        didSet {
            if isViewVisible {
                if !allSeriesData.isEmpty { startAnimation() }
            } else {
                stopAnimation()
            }
        }
    }

    private func startAnimation() {
        guard animationTimer == nil, isViewVisible else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickAnimation()
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tickAnimation() {
        var anyAnimating = false
        for i in allSeriesData.indices {
            let target = Double(allSeriesData[i].rssi)
            let delta = target - allSeriesData[i].displayRSSI
            if abs(delta) < 0.2 { continue }
            anyAnimating = true
            allSeriesData[i].displayRSSI += BandChartViewModel.reduceMotion ? delta : delta * 0.25
        }
        refreshRenderedState()
        if !anyAnimating {
            stopAnimation()
        }
    }
}

extension BandChartViewModel {

    func updateNetworks(_ networks: [WiFiNetwork], colorHasher: SSIDColorHasher, displayStatesByID: [String: APDisplayState], trends: [String: (direction: TrendDirection, delta: Int)] = [:], snapshots: [String: [NetworkSnapshot]] = [:]) {
        var dataArray = ChannelSpanCalculator.toSeriesData(
            networks,
            colorHasher: colorHasher,
            trends: trends,
            displayStatesByID: displayStatesByID
        )

        let prevByID = Dictionary(uniqueKeysWithValues: allSeriesData.map { ($0.id, $0.displayRSSI) })
        for i in dataArray.indices {
            dataArray[i].displayRSSI = prevByID[dataArray[i].id] ?? Double(dataArray[i].rssi)
        }

        var occ: [Int: Int] = [:]
        for s in dataArray { occ[s.channel, default: 0] += 1 }
        channelOccupancy = occ
        for i in dataArray.indices {
            dataArray[i].qualityScore = Self.computeScore(
                rssi: dataArray[i].rssi,
                channelCount: occ[dataArray[i].channel] ?? 1,
                supportsK: dataArray[i].supportsK,
                supportsR: dataArray[i].supportsR,
                supportsV: dataArray[i].supportsV,
                channelWidth: dataArray[i].channelWidth
            )
        }
        allSeriesData = dataArray
        allSnapshots = snapshots
        currentHiddenBands = []
        currentHideHiddenSSIDs = false
        currentFilterQuery = ""
        refreshRenderedState()
        startAnimation()
    }

    func updateNetworks(_ networks: [WiFiNetwork], colorHasher: SSIDColorHasher, filterQuery: String, trends: [String: (direction: TrendDirection, delta: Int)] = [:], snapshots: [String: [NetworkSnapshot]] = [:], hiddenBSSIDs: Set<String> = [], hiddenBands: Set<String> = [], hideHiddenSSIDs: Bool = false) {
        var dataArray = ChannelSpanCalculator.toSeriesData(networks, colorHasher: colorHasher, trends: trends, hiddenBSSIDs: hiddenBSSIDs)

        let prevByID = Dictionary(uniqueKeysWithValues: allSeriesData.map { ($0.id, $0.displayRSSI) })
        for i in dataArray.indices {
            dataArray[i].displayRSSI = prevByID[dataArray[i].id] ?? Double(dataArray[i].rssi)
        }

        var occ: [Int: Int] = [:]
        for s in dataArray { occ[s.channel, default: 0] += 1 }
        channelOccupancy = occ
        for i in dataArray.indices {
            dataArray[i].qualityScore = Self.computeScore(
                rssi: dataArray[i].rssi,
                channelCount: occ[dataArray[i].channel] ?? 1,
                supportsK: dataArray[i].supportsK,
                supportsR: dataArray[i].supportsR,
                supportsV: dataArray[i].supportsV,
                channelWidth: dataArray[i].channelWidth
            )
        }
        allSeriesData = dataArray
        allSnapshots = snapshots
        currentHiddenBands = hiddenBands
        currentHideHiddenSSIDs = hideHiddenSSIDs
        currentFilterQuery = filterQuery
        refreshRenderedState()
        startAnimation()
    }

    static func computeScore(rssi: Int, channelCount: Int, supportsK: Bool, supportsR: Bool, supportsV: Bool, channelWidth: String) -> Int {
        let rssiScore = max(0, min(100, Int(Double(rssi + 100) * 1.4)))
        let congScore: Int = switch channelCount {
        case 1: 100; case 2: 70; case 3: 50; case 4: 35; default: 20
        }
        let protoCount = [supportsK, supportsR, supportsV].filter { $0 }.count
        let protoScore = [0, 40, 70, 100][protoCount]
        let widthScore: Int = switch channelWidth {
        // 80+80 has no scalar geometry in this model; score it like its
        // single 80 MHz segment rather than implying a contiguous 160 MHz span.
        case "160": 100
        case "80", "80+80": 75
        case "40": 50
        default: 25
        }
        let total = Double(rssiScore) * 0.4 + Double(congScore) * 0.3 + Double(protoScore) * 0.2 + Double(widthScore) * 0.1
        return Int(total.rounded())
    }

    func updateInterfaceName(_ name: String) {
        interfaceName = name
    }

    func applyFilter(_ filterQuery: String? = nil,
                      hiddenBands: Set<String> = [],
                      hideHiddenSSIDs: Bool = false) {
        if let filterQuery {
            currentFilterQuery = filterQuery
        }
        currentHiddenBands = hiddenBands
        currentHideHiddenSSIDs = hideHiddenSSIDs
        refreshRenderedState()
    }

    func toggleExpand() {
        isExpanded.toggle()
    }

    func clearFilter() {
        applyFilter("")
    }

    func toggleVisibility(for seriesID: String) {
        guard let index = allSeriesData.firstIndex(where: { $0.id == seriesID }) else { return }
        allSeriesData[index].isVisible.toggle()
        refreshRenderedState()
    }

    func toggleVisibility(seriesID: String) {
        toggleVisibility(for: seriesID)
    }

    func toggleVisibilityLocked(for seriesID: String) {
        guard let index = allSeriesData.firstIndex(where: { $0.id == seriesID }) else { return }
        allSeriesData[index].visibilityLocked.toggle()
        refreshRenderedState()
    }

    func toggleVisibilityLocked(seriesID: String) {
        toggleVisibilityLocked(for: seriesID)
    }

    func resetZoom() {
        zoomMin = nil
        zoomMax = nil
    }

    func applyZoom(lo: Double, hi: Double) {
        let clampedMin = Swift.max(1.0, lo)
        let clampedMax = Swift.min(Double(band.maxChannel), hi)
        let range = clampedMax - clampedMin
        guard range >= Double(Constants.minZoomRange) else { return }
        zoomMin = clampedMin
        zoomMax = clampedMax
    }
}

#if DEBUG
extension BandChartViewModel {
    func debugInject(series: [ChartSeriesData]) {
        var dataArray = series
        let prevByID = Dictionary(uniqueKeysWithValues: allSeriesData.map { ($0.id, $0.displayRSSI) })
        var occ: [Int: Int] = [:]
        for i in dataArray.indices {
            dataArray[i].displayRSSI = prevByID[dataArray[i].id] ?? Double(dataArray[i].rssi)
            occ[dataArray[i].channel, default: 0] += 1
        }
        channelOccupancy = occ
        for i in dataArray.indices {
            dataArray[i].qualityScore = Self.computeScore(
                rssi: dataArray[i].rssi,
                channelCount: occ[dataArray[i].channel] ?? 1,
                supportsK: dataArray[i].supportsK,
                supportsR: dataArray[i].supportsR,
                supportsV: dataArray[i].supportsV,
                channelWidth: dataArray[i].channelWidth
            )
        }
        allSeriesData = dataArray
        refreshRenderedState()
        startAnimation()
    }
}
#endif
