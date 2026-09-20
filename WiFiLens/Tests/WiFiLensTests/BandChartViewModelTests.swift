import Foundation
import SwiftUI
import Testing
import ChartLens
@testable import WiFi_Lens

@Suite @MainActor struct BandChartViewModelTests {

    private func makeSeries(
        id: String = "test-1",
        ssid: String = "TestNet",
        bssid: String = "aa:bb:cc:dd:ee:ff",
        channel: Int = 6,
        rssi: Int = -50,
        phyMode: String = "ax",
        channelWidth: String = "80",
        supportsK: Bool = true,
        supportsR: Bool = true,
        supportsV: Bool = true,
        isHiddenSSID: Bool = false
    ) -> ChartSeriesData {
        let domain = ChartSeriesDomainData(
            id: id,
            ssid: ssid,
            bssid: bssid,
            channel: channel,
            left: channel - 2,
            apex: Double(channel),
            right: channel + 2,
            rssi: rssi,
            phyMode: phyMode,
            channelWidth: channelWidth,
            supportsK: supportsK,
            supportsR: supportsR,
            supportsV: supportsV,
            supportsWPA3: false,
            isHiddenSSID: isHiddenSSID,
            security: "",
            mcs: "",
            nss: "",
            country: ""
        )
        return ChartSeriesData(domain: domain, render: ChartSeriesRenderState(displayRSSI: Double(rssi)))
    }

    private func makeNetwork(
        ssid: String?,
        bssid: String,
        band: ChannelBand,
        channel: Int,
        rssi: Int = -50
    ) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(band: band, channelNumber: channel)
        )
    }

    // MARK: - Filter

    @Test func filterByQueryHidesNonMatchingNetworks() {
        let vm = ScannerViewModel()
        let alpha = makeNetwork(ssid: "Alpha", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let beta = makeNetwork(ssid: "Beta", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)
        let gamma = makeNetwork(ssid: "Gamma", bssid: "00:11:22:33:44:03", band: .band24GHz, channel: 11)

        vm.debugApplyNetworksForTesting([alpha, beta, gamma], supportedBands: Set([ChannelBand.band24GHz]))
        vm.setFilterQuery("Beta", for: .primary)

        #expect(vm.combinedTableRows.count == 3)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().map(\.ssid) == ["Beta"])
    }

    @Test func filterByHiddenBandsRemovesBand() {
        let vm = ScannerViewModel()
        let net1 = makeNetwork(ssid: "Net1", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let net2 = makeNetwork(ssid: "Net2", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)

        vm.debugApplyNetworksForTesting([net1, net2], supportedBands: Set([ChannelBand.band24GHz]))
        vm.hiddenBands = ["24"]
        vm.applyGlobalFilterToBands()

        #expect(vm.combinedTableRows.count == 2)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().isEmpty)
        #expect(vm.combinedTableRows.allSatisfy { $0.isVisible == false })
    }

    @Test func filterByHiddenSSIDsExcludesEmptySSID() {
        let vm = ScannerViewModel()
        let visible = makeNetwork(ssid: "Visible", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let hidden = makeNetwork(ssid: "", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)

        vm.debugApplyNetworksForTesting([visible, hidden], supportedBands: Set([ChannelBand.band24GHz]))
        vm.hideHiddenSSIDs = true
        vm.applyGlobalFilterToBands()

        #expect(vm.combinedTableRows.count == 2)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().count == 1)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().first?.ssid == "Visible")
    }

    @Test func debugInjectPreservesInjectedFilteredState() {
        let vm = BandChartViewModel(band: .band24GHz)
        var visibleSeries = makeSeries(id: "1", ssid: "Visible")
        visibleSeries.isFilteredOut = false
        var filteredSeries = makeSeries(id: "2", ssid: "Filtered")
        filteredSeries.isFilteredOut = true

        vm.debugInject(series: [visibleSeries, filteredSeries])

        #expect(vm.displayedSeriesData.count == 2)
        #expect(vm.displayedSeriesData.first { $0.id == "2" }?.isFilteredOut == true)
        #expect(vm.visibleSeriesData().map(\.id) == ["1", "2"])
    }

    @Test func clearFilterRestoresAllVisible() {
        let vm = ScannerViewModel()
        let alpha = makeNetwork(ssid: "Alpha", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let beta = makeNetwork(ssid: "Beta", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)

        vm.debugApplyNetworksForTesting([alpha, beta], supportedBands: Set([ChannelBand.band24GHz]))
        vm.setFilterQuery("Alpha", for: .primary)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().count == 1)

        vm.setFilterQuery("", for: .primary)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().count == 2)
    }

    @Test func panelFilterOnlyChangesPanelRenderStateNotTableRowPresence() {
        let vm = ScannerViewModel()
        let alpha = makeNetwork(ssid: "Alpha", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let beta = makeNetwork(ssid: "Beta", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)

        vm.debugApplyNetworksForTesting([alpha, beta], supportedBands: Set([ChannelBand.band24GHz]))
        vm.setFilterQuery("Alpha", for: .primary)

        #expect(vm.combinedTableRows.map(\.id) == [alpha.id, beta.id])
        #expect(vm.combinedTableRows.first(where: { $0.id == beta.id })?.isVisible == true)
        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().map(\.id) == [alpha.id])
    }

    @Test func panelFiltersAreIndependentPerView() {
        let vm = ScannerViewModel()
        let alpha = makeNetwork(ssid: "Alpha", bssid: "00:11:22:33:44:01", band: .band24GHz, channel: 1)
        let beta = makeNetwork(ssid: "Beta", bssid: "00:11:22:33:44:02", band: .band24GHz, channel: 6)

        vm.debugApplyNetworksForTesting([alpha, beta], supportedBands: Set([ChannelBand.band24GHz]))
        vm.setFilterQuery("Alpha", for: .primary)
        vm.setFilterQuery("Beta", for: .secondary)

        #expect(vm.bandViewModel(for: .primary, band: .band24GHz).visibleSeriesData().map(\.id) == [alpha.id])
        #expect(vm.bandViewModel(for: .secondary, band: .band24GHz).visibleSeriesData().map(\.id) == [beta.id])
    }

    // MARK: - Validation

    @Test func validateSelectionReturnsTrueForExistingSeries() {
        let vm = BandChartViewModel(band: .band24GHz)
        vm.debugInject(series: [
            makeSeries(id: "valid-id", ssid: "Net"),
        ])
        #expect(vm.validateSelection("valid-id"))
        #expect(!vm.validateSelection("missing-id"))
    }

    // MARK: - computeScore

    @Test func computeScoreExcellentConditions() {
        let score = BandChartViewModel.computeScore(
            rssi: -30, channelCount: 1,
            supportsK: true, supportsR: true, supportsV: true,
            channelWidth: "160"
        )
        #expect(score > 85)
    }

    @Test func computeScoreTreatsVHT80Plus80AsWideOperation() {
        let score = BandChartViewModel.computeScore(
            rssi: -30, channelCount: 1,
            supportsK: true, supportsR: true, supportsV: true,
            channelWidth: "80+80"
        )
        let score80 = BandChartViewModel.computeScore(
            rssi: -30, channelCount: 1,
            supportsK: true, supportsR: true, supportsV: true,
            channelWidth: "80"
        )
        #expect(score == score80)
    }

    @Test func computeScorePoorConditions() {
        let score = BandChartViewModel.computeScore(
            rssi: -90, channelCount: 10,
            supportsK: false, supportsR: false, supportsV: false,
            channelWidth: "20"
        )
        #expect(score < 40)
    }

    @Test func computeScoreChannelCountAffectsScore() {
        let single = BandChartViewModel.computeScore(
            rssi: -50, channelCount: 1,
            supportsK: true, supportsR: true, supportsV: false,
            channelWidth: "80"
        )
        let crowded = BandChartViewModel.computeScore(
            rssi: -50, channelCount: 10,
            supportsK: true, supportsR: true, supportsV: false,
            channelWidth: "80"
        )
        #expect(single > crowded)
    }

    // MARK: - isViewVisible

    @Test func isViewVisibleDefaultsFalse() {
        let vm = BandChartViewModel(band: .band24GHz)
        #expect(!vm.isViewVisible)
    }

    // MARK: - BandChartLayout

    @Test func axisTickValuesSkipChannelsBelowStart() {
        let ticks = BandChartLayout.axisTickValues(xMin: -1, xMax: 14, maxChannel: 14, axisTickStartChannel: 1)
        #expect(!ticks.isEmpty)
        #expect(ticks.allSatisfy { $0 >= 1 })
        #expect(ticks.first == 1)
    }

    @Test func placeLabelsKeepsSelectedSeries() {
        let selected = makeSeries(id: "selected", ssid: "Selected", channel: 6, rssi: -40)
        let other = makeSeries(id: "other", ssid: "Other", channel: 6, rssi: -45)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let labels = BandChartLayout.placeLabels(
            seriesData: [other, selected],
            plotRect: rect,
            annotationRect: rect,
            xMin: 1,
            scaleX: 10,
            scaleY: 1,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: "selected"
        )
        #expect(labels.contains { $0.series.id == "selected" })
    }

    @Test func placeLabelsKeepLeftAndTopEdgeInsideAnnotationRect() throws {
        let series = makeSeries(
            id: "left-edge",
            ssid: "DIRECT-XX-HP Laser XXXXnw",
            channel: 1,
            rssi: -40
        )
        let plotRect = CGRect(x: 38, y: 6, width: 320, height: 160)
        let annotationRect = CGRect(x: 58, y: 26, width: 280, height: 120)

        let labels = BandChartLayout.placeLabels(
            seriesData: [series],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 1,
            scaleX: 24,
            scaleY: 160 / 60,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: nil
        )

        let label = try #require(labels.first)
        let rect = BandChartLayout.estimatedLabelRect(for: label)
        #expect(annotationRect.contains(rect))
    }

    @Test func placeLabelsUseDownwardLaneNearTopBoundary() throws {
        let first = makeSeries(id: "first", ssid: "Collision-A", channel: 52, rssi: -40)
        let second = makeSeries(id: "second", ssid: "Collision-B", channel: 52, rssi: -41)
        let plotRect = CGRect(x: 38, y: 6, width: 360, height: 180)
        let annotationRect = CGRect(x: 58, y: 26, width: 320, height: 140)

        let labels = BandChartLayout.placeLabels(
            seriesData: [first, second],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 36,
            scaleX: 8,
            scaleY: 180 / 60,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: nil
        )

        #expect(labels.count == 2)
        let rects = labels.map { BandChartLayout.estimatedLabelRect(for: $0) }
        #expect(rects.allSatisfy { annotationRect.contains($0) })
        #expect(!rects[0].intersects(rects[1]))
    }

    @Test func acceptedLabelRectIsCenteredOnPlacementPosition() throws {
        let series = makeSeries(id: "centered", ssid: "Centered", channel: 11, rssi: -90)
        let plotRect = CGRect(x: 38, y: 6, width: 320, height: 160)
        let annotationRect = CGRect(x: 58, y: 26, width: 280, height: 120)

        let labels = BandChartLayout.placeLabels(
            seriesData: [series],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 1,
            scaleX: 24,
            scaleY: 160 / 60,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: nil
        )

        let label = try #require(labels.first)
        let rect = BandChartLayout.estimatedLabelRect(for: label)
        #expect(rect.midX == label.x)
        #expect(rect.midY == label.y)
        #expect(annotationRect.contains(rect))
    }

    @Test func regularLabelSitsAboveCurveApex() throws {
        let series = makeSeries(id: "above", ssid: "Above", channel: 6, rssi: -60)
        let plotRect = CGRect(x: 38, y: 6, width: 320, height: 160)
        let annotationRect = CGRect(x: 58, y: 26, width: 280, height: 120)
        let scaleY = plotRect.height / 60
        let yMin = Double(Constants.rssiNoiseFloor)

        let labels = BandChartLayout.placeLabels(
            seriesData: [series],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 1,
            scaleX: 24,
            scaleY: scaleY,
            yMin: yMin,
            selectedNetworkID: nil
        )

        let label = try #require(labels.first)
        let rect = BandChartLayout.estimatedLabelRect(for: label)
        let apexY = plotRect.maxY - (series.displayRSSI - yMin) * scaleY

        #expect(rect.maxY <= apexY - 8)
    }

    @Test func longSSIDPlacementUsesCappedContainedLabelSize() throws {
        let series = makeSeries(
            id: "long",
            ssid: "This network name is intentionally far longer than the label estimate may draw without truncation",
            channel: 6,
            rssi: -40
        )
        let plotRect = CGRect(x: 38, y: 6, width: 320, height: 160)
        let annotationRect = CGRect(x: 58, y: 26, width: 280, height: 120)

        let labels = BandChartLayout.placeLabels(
            seriesData: [series],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 1,
            scaleX: 24,
            scaleY: 160 / 60,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: nil
        )

        let label = try #require(labels.first)
        let rect = BandChartLayout.estimatedLabelRect(for: label)
        #expect(label.size.width == 220)
        #expect(rect.width == label.size.width)
        #expect(annotationRect.contains(rect))
    }

    @Test func selectedLabelFallsBackInsideTooSmallAnnotationRect() throws {
        let selected = makeSeries(id: "selected", ssid: "SelectedNameCannotFit", channel: 6, rssi: -40)
        let plotRect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let annotationRect = CGRect(x: 20, y: 20, width: 5, height: 5)

        let labels = BandChartLayout.placeLabels(
            seriesData: [selected],
            plotRect: plotRect,
            annotationRect: annotationRect,
            xMin: 1,
            scaleX: 10,
            scaleY: 1,
            yMin: Double(Constants.rssiNoiseFloor),
            selectedNetworkID: "selected"
        )

        let label = try #require(labels.first)
        let rect = BandChartLayout.estimatedLabelRect(for: label)
        #expect(label.series.id == "selected")
        #expect(label.kind == .marker)
        #expect(annotationRect.contains(rect))
    }

    @Test func nearestSeriesFindsClosestCurve() {
        let series = makeSeries(id: "hit", ssid: "Hit", channel: 6, rssi: -40)
        let geo = ChartGeometry(
            chartRect: CGRect(x: 0, y: 0, width: 200, height: 120),
            xMin: 1,
            xMax: 14,
            yMin: Double(Constants.rssiNoiseFloor),
            yMax: 0
        )
        let point = geo.dataToPoint(x: Double(series.apex), y: Double(series.displayRSSI))
        let hit = BandChartLayout.nearestSeries(at: point, in: [series], geometry: geo, radius: 20)
        #expect(hit?.0.id == "hit")
    }

    // MARK: - AP Count Limit

    @Test func visibleSeriesDataLimitsToMax() {
        let vm = BandChartViewModel(band: .band5GHz)
        var series: [ChartSeriesData] = []
        for i in 0..<20 {
            series.append(ChartSeriesData(
                id: "ap\(i)",
                ssid: "Network\(i)",
                bssid: "00:11:22:33:44:\(String(format: "%02x", i))",
                channel: 36,
                left: 36,
                apex: 36.0,
                right: 40,
                rssi: -50 - i
            ))
        }
        vm.debugInject(series: series)
        #expect(vm.visibleSeriesData().count == 20)
    }

    @Test func visibleSeriesDataReturnsAllWhenUnderLimit() {
        let vm = BandChartViewModel(band: .band5GHz)
        var series: [ChartSeriesData] = []
        for i in 0..<10 {
            series.append(ChartSeriesData(
                id: "ap\(i)",
                ssid: "Network\(i)",
                bssid: "00:11:22:33:44:\(String(format: "%02x", i))",
                channel: 36,
                left: 36,
                apex: 36.0,
                right: 40,
                rssi: -50 - i
            ))
        }
        vm.debugInject(series: series)
        #expect(vm.visibleSeriesData().count == 10)
    }

    @Test func visibleSeriesDataSortsByRSSI() {
        let vm = BandChartViewModel(band: .band5GHz)
        var series: [ChartSeriesData] = []
        series.append(ChartSeriesData(id: "strong", ssid: "Strong", bssid: "00:00:00:00:00:00", channel: 36, left: 36, apex: 36.0, right: 40, rssi: -30))
        for i in 1..<20 {
            series.append(ChartSeriesData(
                id: "ap\(i)",
                ssid: "Network\(i)",
                bssid: "00:11:22:33:44:\(String(format: "%02x", i))",
                channel: 36,
                left: 36,
                apex: 36.0,
                right: 40,
                rssi: -80 - i
            ))
        }
        vm.debugInject(series: series)
        let result = vm.visibleSeriesData()
        #expect(result.count == 20)
        #expect(result[0].id == "strong")
    }

    // MARK: - SnapshotToChartAdapter

    @Test func channelWidthMHzParsesCorrectly() {
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "160") == 160)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "80") == 80)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "80+80") == 80)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "40") == 40)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "20") == 20)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "") == 20)
        #expect(SnapshotToChartAdapter.channelWidthMHz(from: "invalid") == 20)
    }

    @Test func toSeriesDataUsesNarrowFallbackForVHT80Plus80() {
        let snapshot = NetworkSnapshot(
            timestamp: Date(), bssid: "aa:bb:cc:dd:ee:80", ssid: "NonContiguous",
            rssi: -50, channel: 36, band: "5", phyMode: "ac",
            channelWidth: "80+80", mcs: "", nss: "", security: "",
            country: "", supportsK: false, supportsR: false,
            supportsV: false, supportsWPA3: false, isHiddenSSID: false
        )

        let series = SnapshotToChartAdapter.toSeriesData(
            snapshotsByBSSID: [snapshot.bssid: snapshot],
            band: .band5GHz,
            colorHasher: SSIDColorHasher()
        )

        #expect(series.first?.left == 34)
        #expect(series.first?.right == 50)
        #expect(series.first?.channelWidth == "80+80")
    }

    @Test func toSeriesDataFiltersByBand() {
        let snap24 = NetworkSnapshot(
            timestamp: Date(), bssid: "aa:bb:cc:dd:ee:01", ssid: "Net2G",
            rssi: -50, channel: 6, band: "24", phyMode: "ax",
            channelWidth: "40", mcs: "", nss: "", security: "",
            country: "", supportsK: true, supportsR: true,
            supportsV: true, supportsWPA3: false, isHiddenSSID: false
        )
        let snap5 = NetworkSnapshot(
            timestamp: Date(), bssid: "aa:bb:cc:dd:ee:02", ssid: "Net5G",
            rssi: -45, channel: 52, band: "5", phyMode: "ac",
            channelWidth: "80", mcs: "", nss: "", security: "",
            country: "", supportsK: false, supportsR: false,
            supportsV: false, supportsWPA3: true, isHiddenSSID: false
        )
        let dict = ["bssid1": snap24, "bssid2": snap5]
        let hasher = SSIDColorHasher()

        let series2G = SnapshotToChartAdapter.toSeriesData(snapshotsByBSSID: dict, band: .band24GHz, colorHasher: hasher)
        #expect(series2G.count == 1)
        #expect(series2G.first?.ssid == "Net2G")

        let series5G = SnapshotToChartAdapter.toSeriesData(snapshotsByBSSID: dict, band: .band5GHz, colorHasher: hasher)
        #expect(series5G.count == 1)
        #expect(series5G.first?.ssid == "Net5G")
    }

    @Test func toSeriesDataEmptyInputProducesEmptyOutput() {
        let series = SnapshotToChartAdapter.toSeriesData(
            snapshotsByBSSID: [:],
            band: .band5GHz,
            colorHasher: SSIDColorHasher()
        )
        #expect(series.isEmpty)
    }

    @Test func toSeriesDataSkipsInvalidBand() {
        let snap = NetworkSnapshot(
            timestamp: Date(), bssid: "aa:bb:cc:dd:ee:03", ssid: "BadBand",
            rssi: -50, channel: 6, band: "99", phyMode: "ax",
            channelWidth: "20", mcs: "", nss: "", security: "",
            country: "", supportsK: false, supportsR: false,
            supportsV: false, supportsWPA3: false, isHiddenSSID: false
        )
        let series = SnapshotToChartAdapter.toSeriesData(
            snapshotsByBSSID: ["bssid": snap],
            band: .band5GHz,
            colorHasher: SSIDColorHasher()
        )
        #expect(series.isEmpty)
    }

    // MARK: - Visibility / VisibilityLocked

    @Test func lockedAPNotModifiedByFilter() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([office], supportedBands: Set([ChannelBand.band5GHz]))
        vm.toggleVisibilityLocked(seriesID: office.id)
        vm.setFilterQuery("Home", for: .primary)

        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().first?.id == office.id)
    }

    @Test func unlockedAPModifiedByFilter() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([office], supportedBands: Set([ChannelBand.band5GHz]))
        vm.setFilterQuery("Home", for: .primary)

        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().isEmpty)
    }

    @Test func lockedAPPreservedWhileOtherAPsUpdateForFilter() {
        let vm = ScannerViewModel()
        let locked = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)
        let unlocked = makeNetwork(ssid: "Home", bssid: "66:77:88:99:AA:BB", band: .band5GHz, channel: 40, rssi: -60)

        vm.debugApplyNetworksForTesting([locked, unlocked], supportedBands: Set([ChannelBand.band5GHz]))
        vm.toggleVisibilityLocked(seriesID: locked.id)
        vm.setFilterQuery("Home", for: .primary)

        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().map(\.id) == [locked.id, unlocked.id])
    }

    @Test func toggleVisibility() {
        let vm = BandChartViewModel(band: .band5GHz)
        let series = ChartSeriesData(
            id: "test",
            ssid: "Test",
            bssid: "00:11:22:33:44:55",
            channel: 36,
            left: 36,
            apex: 36.0,
            right: 40,
            rssi: -50,
            isVisible: true
        )
        vm.debugInject(series: [series])
        vm.toggleVisibility(for: "test")
        #expect(vm.allSeriesData.first?.isVisible == false)
        vm.toggleVisibility(for: "test")
        #expect(vm.allSeriesData.first?.isVisible == true)
    }

    @Test func toggleVisibilityLocked() {
        let vm = BandChartViewModel(band: .band5GHz)
        let series = ChartSeriesData(
            id: "test",
            ssid: "Test",
            bssid: "00:11:22:33:44:55",
            channel: 36,
            left: 36,
            apex: 36.0,
            right: 40,
            rssi: -50,
            visibilityLocked: false
        )
        vm.debugInject(series: [series])
        vm.toggleVisibilityLocked(for: "test")
        #expect(vm.allSeriesData.first?.visibilityLocked == true)
        vm.toggleVisibilityLocked(for: "test")
        #expect(vm.allSeriesData.first?.visibilityLocked == false)
    }
}

@Suite @MainActor struct ScannerViewModelDisplayStateTests {

    private func makeNetwork(
        ssid: String?,
        bssid: String,
        band: ChannelBand,
        channel: Int,
        rssi: Int = -50
    ) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(band: band, channelNumber: channel)
        )
    }

    @Test func tableRowsRemainCompleteWhenAutoFilterHidesAPs() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)
        let guest = makeNetwork(ssid: "Guest", bssid: "66:77:88:99:AA:BB", band: .band5GHz, channel: 40)

        vm.debugApplyNetworksForTesting([office, guest], supportedBands: Set([ChannelBand.band5GHz]))
        vm.setFilterQuery("Office", for: .primary)

        #expect(vm.combinedTableRows.map(\.id) == [office.id, guest.id])
        #expect(vm.combinedTableRows.first(where: { $0.id == office.id })?.isVisible == true)
        #expect(vm.combinedTableRows.first(where: { $0.id == guest.id })?.isVisible == true)
        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().map(\.id) == [office.id])
    }

    @Test func lockedHiddenAPIsPreservedWhileOtherAPsRecomputeVisibility() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)
        let guest = makeNetwork(ssid: "Guest", bssid: "66:77:88:99:AA:BB", band: .band5GHz, channel: 40)

        vm.debugApplyNetworksForTesting([office, guest], supportedBands: Set([ChannelBand.band5GHz]))
        vm.toggleVisibility(seriesID: office.id)
        vm.toggleVisibilityLocked(seriesID: office.id)
        vm.setFilterQuery("Guest", for: .primary)

        #expect(vm.combinedTableRows.map(\.id) == [office.id, guest.id])
        #expect(vm.combinedTableRows.first(where: { $0.id == office.id })?.isVisible == false)
        #expect(vm.combinedTableRows.first(where: { $0.id == office.id })?.visibilityLocked == true)
        #expect(vm.combinedTableRows.first(where: { $0.id == guest.id })?.isVisible == true)
        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().map(\.id) == [guest.id])
    }

    @Test func userVisibilityChangeOverridesLockProtection() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([office], supportedBands: Set([ChannelBand.band5GHz]))
        vm.toggleVisibilityLocked(seriesID: office.id)
        vm.toggleVisibility(seriesID: office.id)

        #expect(vm.combinedTableRows.first?.isVisible == false)
        #expect(vm.combinedTableRows.first?.visibilityLocked == true)
        #expect(vm.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().isEmpty)
    }

    @Test func bandViewModelsAreCreatedLazilyPerPanel() {
        let vm = ScannerViewModel()
        let office = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)

        vm.debugApplyNetworksForTesting([office], supportedBands: Set([ChannelBand.band5GHz]))

        // The tertiary panel defaults to Table and never requested a band VM,
        // so no band ViewModels should have been allocated for it.
        #expect(vm.panelBandViewModels(for: .tertiary).isEmpty)

        // Requesting a band VM lazily creates it and immediately syncs the
        // current scan data so the panel is usable right away.
        let bandVM = vm.bandViewModel(for: .tertiary, band: .band5GHz)
        #expect(bandVM.visibleSeriesData().map(\.id) == [office.id])
        #expect(vm.panelBandViewModels(for: .tertiary).map(\.band) == [.band5GHz])
    }

    @Test func sharedTrendAPIsUseSignalHistoryForSelectedNetwork() {
        let vm = ScannerViewModel()
        let network = makeNetwork(ssid: "Office", bssid: "00:11:22:33:44:55", band: .band5GHz, channel: 36)
        let t0 = Date(timeIntervalSince1970: 1_752_001_200)
        let t1 = t0.addingTimeInterval(3)
        vm.debugApplyNetworksForTesting([network], supportedBands: [.band5GHz], timestamp: t0)
        vm.debugApplyNetworksForTesting([network], supportedBands: [.band5GHz], timestamp: t1)

        // A panel that never opened a band must still resolve shared history
        // for the globally selected network.
        let snaps = vm.snapshots(for: network.id)
        #expect(snaps != nil)
        #expect(snaps?.count == 2)
    }
}
