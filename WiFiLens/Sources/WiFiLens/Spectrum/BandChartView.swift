import SwiftUI
import WiFiLensCore
import ChartLens

struct WiFiBandChart: View {
    let model: BandChartRenderModel
    @Binding var selectedNetworkID: String?
    let onResetZoom: () -> Void
    let onToggleExpand: () -> Void
    let onApplyZoom: (Double, Double) -> Void

    @State private var hoveredSeries: ChartSeriesData?
    @State private var hoverPoint: CGPoint = .zero
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            chartToolbar
            chartContent
        }
        .overlay {
            if model.isExpanded { expandedOverlay }
        }
    }

    // MARK: - Toolbar

    private var chartToolbar: some View {
        HStack(spacing: 4) {
            if model.zoomMin != nil {
                Button {
                    onResetZoom()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 24, height: 24)
                }
                .help(String(localized: "common.action.reset_zoom", comment: "Reset chart zoom to default"))
                .accessibilityLabel(String(localized: "common.action.reset_zoom", comment: "Reset chart zoom to default"))
            }
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
    }

    // MARK: - Computed properties

    private var visibleSeries: [ChartSeriesData] { model.visibleSeriesData }
    private var hasSelection: Bool { selectedNetworkID != nil }
    private func isSelected(_ s: ChartSeriesData) -> Bool { selectedNetworkID == s.id }

    private func strokeStyle(for s: ChartSeriesData) -> (areaOpacity: Double, strokeOpacity: Double, strokeWidth: CGFloat) {
        if isSelected(s) { return (0.55, 1.0, 2) }
        if hasSelection { return (0.10, 0.20, 1) }
        return (0.3, 0.6, 1)
    }

    // MARK: - Chart Data

    private func buildSeries() -> [ChartSeries<ChartPoint>] {
        visibleSeries.map { s in
            let halfWidth = Double(s.right - s.left) / 2.0
            let sigma = halfWidth / 4.0
            let baseline = Double(Constants.rssiNoiseFloor)
            let st = strokeStyle(for: s)
            return ChartSeries(
                id: s.id,
                points: [
                    ChartPoint(x: Double(s.left), y: s.displayRSSI),
                    ChartPoint(x: Double(s.right), y: s.displayRSSI),
                ],
                style: ChartSeriesStyle(
                    color: s.color, lineWidth: st.strokeWidth,
                    areaOpacity: st.areaOpacity, strokeOpacity: st.strokeOpacity,
                    interpolation: .gaussian(sigma: sigma, baseline: baseline),
                    baseline: baseline
                )
            )
        }
    }

    private func computeGeo(size: CGSize) -> ChartGeometry {
        let regions = chartStyle.regions(size: size)
        let xMin = model.zoomMin ?? Double(model.xDataMin)
        let xMax = model.zoomMax ?? Double(model.xDataMax)
        let yMin = model.yMin
        let yMax = min(0.0, ceil(Double(model.strongestRSSI) / 10.0) * 10)
        return ChartGeometry(
            frameRect: regions.frameRect,
            plotRect: regions.plotRect,
            annotationRect: regions.annotationRect,
            axisLabelRects: regions.axisLabelRects,
            xMin: xMin,
            xMax: xMax,
            yMin: yMin,
            yMax: yMax
        )
    }

    // MARK: - Axis & Style

    private var axisConfig: ChartAxisConfig {
        let xMin = model.zoomMin ?? Double(model.xDataMin)
        let xMax = model.zoomMax ?? Double(model.xDataMax)
        let tickValues = BandChartLayout.axisTickValues(
            xMin: xMin, xMax: xMax,
            maxChannel: model.xDataMax,
            axisTickStartChannel: model.axisTickStartChannel
        )
        var a = ChartAxisConfig()
        a.xMin = xMin; a.xMax = xMax
        a.yMin = model.yMin; a.yStep = 10; a.gridColor = .gray.opacity(0.15)
        a.xTicks = tickValues.map { ChartAxisConfig.XTick(position: Double($0), label: "\($0)") }
        a.xTickLabelOffset = 10; a.yTickLabelOffset = 14
        return a
    }

    private let chartStyle = ChartStyle(
        leftAxisWidth: 38, bottomAxisHeight: 24,
        marginTop: 6, marginRight: 8, marginBottom: 4
    )

    // MARK: - Content

    private var chartContent: some View {
        Group {
            if model.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "common.label.loading", comment: "Loading indicator text"))
                        .foregroundColor(Color(hex: "#888888")).font(.title3)
                    Spacer()
                }
            } else {
                GeometryReader { geometry in
                    let geo = computeGeo(size: geometry.size)
                    Chart(series: buildSeries(), axis: axisConfig, style: chartStyle) { chartGeo, _ in
                        dataLabelOverlay(geo: chartGeo)
                    }
                    .accessibilityLabel(String(localized: "spectrum.accessibility.chart_label", comment: "Spectrum chart accessibility label"))
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            if let (series, pt) = BandChartLayout.nearestSeries(at: location, in: visibleSeries, geometry: geo, radius: 14) {
                                hoveredSeries = series; hoverPoint = pt
                            } else { hoveredSeries = nil }
                        case .ended:
                            isHovering = false; hoveredSeries = nil
                        }
                    }
                    .onTapGesture { selectedNetworkID = hoveredSeries?.id }
                    .gesture(zoomGesture(in: geometry, geo: geo))
                    .overlay {
                        if isHovering, let series = hoveredSeries {
                            ChartTooltip(ssid: series.displaySSID, rssi: series.rssi, channel: series.channel, bssid: series.bssid)
                                .position(x: clampX(hoverPoint.x, in: geo.chartRect), y: max(hoverPoint.y - 22, 4))
                        }
                    }
                    .accessibilityLabel(String(format: String(localized: "spectrum.accessibility.chart_label_fmt", comment: "Chart accessibility label with network count"), model.visibleSeriesData.count))
                }
            }
        }
    }

    // MARK: - Overlays

    private func dataLabelOverlay(geo: ChartGeometry) -> some View {
        let seriesList = model.displayedSeriesData
        let labels = BandChartLayout.placeLabels(
            seriesData: seriesList,
            plotRect: geo.plotRect,
            annotationRect: geo.annotationRect,
            xMin: geo.xMin,
            scaleX: geo.scaleX,
            scaleY: geo.scaleY,
            yMin: geo.yMin,
            selectedNetworkID: selectedNetworkID
        )
        return ForEach(labels, id: \.series.id) { item in
            dataLabel(item)
        }
    }

    @ViewBuilder
    private func dataLabel(_ item: BandChartLayout.LabelPlacement) -> some View {
        switch item.kind {
        case .regular, .compact:
            Text(labelText(for: item))
                .font(.caption2)
                .foregroundColor(item.series.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: item.size.width, height: item.size.height)
                .opacity(item.opacity)
                .position(x: item.x, y: item.y)
        case .marker:
            Circle()
                .fill(item.series.color)
                .frame(width: item.size.width, height: item.size.height)
                .opacity(item.opacity)
                .position(x: item.x, y: item.y)
        }
    }

    private func labelText(for item: BandChartLayout.LabelPlacement) -> String {
        switch item.kind {
        case .regular:
            return "\(item.series.channel) \(item.series.displaySSID)\(trendSuffix(for: item.series))"
        case .compact:
            return "CH \(item.series.channel)"
        case .marker:
            return ""
        }
    }

    private func trendSuffix(for series: ChartSeriesData) -> String {
        guard !series.trendArrow.isEmpty else { return "" }
        let d = series.trendDelta == 0 ? "" : " \(series.trendDelta > 0 ? "+" : "")\(series.trendDelta)"
        return " \(series.trendArrow)\(d)"
    }

    // MARK: - Gestures

    private func clampX(_ x: CGFloat, in rect: CGRect) -> CGFloat {
        min(max(x, rect.minX + 60), rect.maxX - 60)
    }

    private func zoomGesture(in geometry: GeometryProxy, geo: ChartGeometry) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                let startX = min(value.startLocation.x, value.location.x)
                let endX = max(value.startLocation.x, value.location.x)
                guard endX - startX > 20 else { return }
                let relStart = Swift.max(0.0, startX - geo.chartRect.minX)
                let relEnd = Swift.min(geo.chartRect.width, endX - geo.chartRect.minX)
                let lo = geo.xMin + (relStart / geo.chartRect.width) * (geo.xMax - geo.xMin)
                let hi = geo.xMin + (relEnd / geo.chartRect.width) * (geo.xMax - geo.xMin)
                onApplyZoom(lo, hi)
            }
    }

    // MARK: - Expanded Overlay

    private var expandedOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                chartToolbar
                GeometryReader { geometry in
                    let geo = computeGeo(size: geometry.size)
                    Chart(series: buildSeries(), axis: axisConfig, style: chartStyle) { chartGeo, _ in
                        dataLabelOverlay(geo: chartGeo)
                    }
                    .accessibilityLabel(String(localized: "spectrum.accessibility.chart_label", comment: "Spectrum chart accessibility label"))
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            if let (series, pt) = BandChartLayout.nearestSeries(at: location, in: visibleSeries, geometry: geo, radius: 14) {
                                hoveredSeries = series; hoverPoint = pt
                            } else { hoveredSeries = nil }
                        case .ended:
                            isHovering = false; hoveredSeries = nil
                        }
                    }
                    .onTapGesture { selectedNetworkID = hoveredSeries?.id }
                    .gesture(zoomGesture(in: geometry, geo: geo))
                    .overlay {
                        if isHovering, let series = hoveredSeries {
                            ChartTooltip(ssid: series.displaySSID, rssi: series.rssi, channel: series.channel, bssid: series.bssid)
                                .position(x: clampX(hoverPoint.x, in: geo.chartRect), y: max(hoverPoint.y - 22, 4))
                        }
                    }
                    .accessibilityLabel(String(format: String(localized: "spectrum.accessibility.chart_label_fmt", comment: "Chart accessibility label with network count"), model.visibleSeriesData.count))
                }
            }
            .padding()
            Button { onToggleExpand() } label: {
                Image(systemName: "xmark.circle.fill").font(.title).foregroundColor(.secondary)
            }
            .buttonStyle(.plain).padding(8)
            .accessibilityLabel(String(localized: "spectrum.accessibility.close_expanded", comment: "Close expanded chart button"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

typealias BandChartView = WiFiBandChart

// MARK: - Chart Tooltip

private struct ChartTooltip: View {
    let ssid: String; let rssi: Int; let channel: Int; let bssid: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ssid).font(.caption.weight(.semibold)).foregroundColor(.primary)
            Text(String(format: String(localized: "format.channel_rssi", comment: "Channel and RSSI values"), channel, rssi)).font(.caption2).foregroundColor(.secondary)
            Text(bssid).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 4))
    }
}
