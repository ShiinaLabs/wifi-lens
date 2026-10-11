import SwiftUI
import WiFiLensCore
import ChartLens

#if DEBUG

// MARK: - Chart Layout

private let leftAxisWidth: CGFloat = 40
private let bottomAxisHeight: CGFloat = 24
private let topMargin: CGFloat = 40
private let detailChartHeight: CGFloat = 160
private let overviewHeight: CGFloat = 48

private let segmentColors: [Color] = [
    .blue, .green, .orange, .purple, .teal, .pink, .mint, .indigo
]

private struct BSSIDColorMap {
    private(set) var mapping: [String: Color] = [:]
    private var nextIndex = 0

    mutating func color(for bssid: String) -> Color {
        if let existing = mapping[bssid] { return existing }
        let color = segmentColors[nextIndex % segmentColors.count]
        mapping[bssid] = color
        nextIndex += 1
        return color
    }
}

private func buildBSSIDColorMap(from segments: [RoamingSegment]) -> [String: Color] {
    var map = BSSIDColorMap()
    for segment in segments {
        _ = map.color(for: segment.bssid)
    }
    return map.mapping
}

// MARK: - Formatter

private let timeFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.minute, .second]
    f.unitsStyle = .positional
    f.zeroFormattingBehavior = .pad
    return f
}()

// MARK: - Test Data Generator

private func generateTestData() -> (segments: [RoamingSegment], transitions: [APTransitionEvent]) {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    let accessPoints: [(bssid: String, start: Int, end: Int, channel: Int, startRSSI: Int, endRSSI: Int)] = [
        ("AP-A", 0, 6, 36, -48, -68),
        ("AP-B", 6, 12, 149, -51, -73),
        ("AP-A", 12, 18, 36, -57, -66),
        ("AP-B", 18, 24, 149, -50, -70),
        // No B→C transition is supplied: 24–26 is an intentional unknown gap.
        ("AP-C", 26, 30, 48, -45, -62),
    ]

    let segments = accessPoints.enumerated().map { index, ap in
        // Keep synthetic measurements away from confirmed transition times so
        // the chart demonstrates that region continuity does not extend RSSI.
        let sampleStart = ap.start + (index > 0 ? 1 : 0)
        let sampleEnd = ap.end - (index < 3 ? 1 : 0)
        let samples = stride(from: sampleStart, through: sampleEnd, by: 1).map { second in
            let progress = Double(second - ap.start) / Double(max(1, ap.end - ap.start))
            let isMissingMeasurement = index == 1 && second == 8
            let rssi = isMissingMeasurement
                ? nil
                : Int((Double(ap.startRSSI) + Double(ap.endRSSI - ap.startRSSI) * progress + sin(Double(second) * 0.23) * 2).rounded())
            return RoamingSample(
                timestamp: baseDate.addingTimeInterval(TimeInterval(second)),
                rssi: rssi,
                channel: isMissingMeasurement ? nil : ap.channel,
                txRate: isMissingMeasurement ? nil : 600 - progress * 260,
                gatewayLatency: second.isMultiple(of: 10) ? 4 + progress * 8 : nil
            )
        }
        return RoamingSegment(
            bssid: ap.bssid,
            startTime: baseDate.addingTimeInterval(TimeInterval(ap.start)),
            endTime: baseDate.addingTimeInterval(TimeInterval(ap.end)),
            samples: samples
        )
    }

    let transitions = [
        (0, 1), (1, 2), (2, 3),
    ].map { pair in
        let fromIndex = pair.0
        let toIndex = pair.1
        let from = accessPoints[fromIndex]
        let to = accessPoints[toIndex]
        let time = baseDate.addingTimeInterval(TimeInterval(to.start))
        return APTransitionEvent(
            timestamp: time,
            fromBSSID: from.bssid,
            toBSSID: to.bssid,
            rssiBefore: from.endRSSI,
            rssiAfter: to.startRSSI,
            channelBefore: from.channel,
            channelAfter: to.channel
        )
    }
    return (segments, transitions)
}

// MARK: - Debug Roaming Chart View

struct DebugRoamingChartView: View {
    private let scene: RoamingChartScene
    private let transitionEvents: [APTransitionEvent]
    private let bssidColors: [String: Color]

    init() {
        let data = generateTestData()
        self.scene = RoamingChartScene(segments: data.segments, transitions: data.transitions, duration: 30)
        self.transitionEvents = data.transitions
        self.bssidColors = buildBSSIDColorMap(from: data.segments)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            chartSection
            transitionTable
        }
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Debug Roaming Test")
                    .font(.system(size: 13, weight: .semibold))
                Text("Deterministic test data · repeated roaming, missing RSSI, unknown gap · \(scene.samples.count) samples")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                statBadge("arrow.triangle.swap", "\(transitionEvents.count) transitions")
                statBadge("chart.xyaxis.line", "\(scene.samples.count) samples")
                statBadge("clock", "0:30")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func statBadge(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: Chart

    private var chartSection: some View {
        DebugRoamingTimelineChart(
            scene: scene,
            bssidColors: bssidColors,
            elapsedTime: scene.duration
        )
    }

    // MARK: Transition table

    private var transitionTable: some View {
        VStack(spacing: 0) {
            Divider()
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    tableHeader("Time")
                    tableHeader("From BSSID")
                    tableHeader("To BSSID")
                    tableHeader("RSSI Before")
                    tableHeader("RSSI After")
                    tableHeader("Ch Before")
                    tableHeader("Ch After")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(transitionEvents.enumerated()), id: \.element.id) { idx, t in
                        Divider()
                        GridRow {
                            tableCell(tsLabel(t.timestamp))
                            tableCell(t.fromBSSID, mono: true)
                            tableCell(t.toBSSID, mono: true)
                            tableCell(t.rssiBefore.map { "\($0) dBm" } ?? "—", color: t.rssiBefore.map(rssiColor) ?? .secondary)
                            tableCell(t.rssiAfter.map { "\($0) dBm" } ?? "—", color: t.rssiAfter.map(rssiColor) ?? .secondary)
                            tableCell(t.channelBefore.map(String.init) ?? "—")
                            tableCell(t.channelAfter.map(String.init) ?? "—")
                        }
                        .background(idx.isMultiple(of: 2) ? .clear : Color.primary.opacity(0.04))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
    }

    private func tableCell(_ text: String, mono: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(.system(size: 11, design: mono ? .monospaced : .default))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
            .lineLimit(1)
    }

    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func tsLabel(_ date: Date) -> String {
        Self.tsFormatter.string(from: date)
    }
}

// MARK: - Chart Canvas

private struct DebugChartCanvas: View {
    @Environment(\.displayScale) private var displayScale
    let scene: RoamingChartScene
    let elapsedTime: TimeInterval
    let bssidColors: [String: Color]
    var timeOffset: TimeInterval = 0
    var highlightedTime: TimeInterval?
    var highlightedSample: RoamingChartSamplePoint?

    var body: some View {
        Canvas { context, size in
            let plotLeft = leftAxisWidth
            let plotTop = topMargin
            let plotWidth = size.width - plotLeft - 8
            let plotBottom = size.height - bottomAxisHeight
            let plotHeight = plotBottom - plotTop

            guard plotWidth > 0, plotHeight > 0, !scene.regions.isEmpty else { return }

            let measuredRSSI = scene.signalRuns.flatMap { $0.points.compactMap { $0.sample.rssi } }
            let rssiMin = min(-100, measuredRSSI.min() ?? -100)
            let rssiMax = max(-30, measuredRSSI.max() ?? -30)
            let rssiRange = Double(max(1, rssiMax - rssiMin))

            let totalSecs = max(1, elapsedTime)
            let timeScale = RoamingChartTimeScale(origin: scene.origin)

            func xPos(_ elapsed: TimeInterval) -> CGFloat {
                timeScale.xPosition(
                    for: elapsed,
                    visibleStart: timeOffset,
                    visibleDuration: totalSecs,
                    plotLeft: plotLeft,
                    plotWidth: plotWidth,
                    displayScale: displayScale
                )
            }

            func yPos(_ rssi: Int) -> CGFloat {
                plotTop + CGFloat(rssiMax - rssi) / CGFloat(rssiRange) * plotHeight
            }

            // Grid lines
            let gridStep = 10
            let gridStart = ((rssiMin) / gridStep) * gridStep
            for rssi in stride(from: gridStart, through: rssiMax, by: gridStep) {
                let y = yPos(rssi)
                var line = Path()
                line.move(to: CGPoint(x: plotLeft, y: y))
                line.addLine(to: CGPoint(x: plotLeft + plotWidth, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)

                let label = Text("\(rssi)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                let resolved = context.resolve(label)
                let labelSize = resolved.measure(in: CGSize(width: leftAxisWidth - 4, height: 20))
                context.draw(resolved, at: CGPoint(x: plotLeft - 6 - labelSize.width, y: y))
            }

            // Time axis labels
            let timeStep: TimeInterval = max(10, ceil(totalSecs / 6 / 10) * 10)
            var t: TimeInterval = 0
            while t <= totalSecs {
                let x = xPos(t + timeOffset)
                let label = Text(timeFormatter.string(from: t + timeOffset) ?? "0")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                let resolved = context.resolve(label)
                context.draw(resolved, at: CGPoint(x: x, y: plotBottom + 6))
                t += timeStep
            }

            // BSSID labels per trusted ownership region.
            for region in scene.regions {
                let midX = xPos((region.start + region.end) / 2)
                let color = bssidColors[region.bssid] ?? .blue
                let label = Text(region.bssid)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)
                let resolved = context.resolve(label)
                let labelW = resolved.measure(in: CGSize(width: 200, height: 20)).width
                if region.end - region.start > 2 {
                    context.draw(resolved, at: CGPoint(x: min(max(midX, plotLeft + labelW / 2), plotLeft + plotWidth - labelW / 2), y: topMargin - 8))
                }
            }

            // Clip
            let clipRect = Path(CGRect(x: plotLeft, y: plotTop, width: plotWidth, height: plotHeight))
            context.clip(to: clipRect)

            // Weak, visual-only area bridges use real endpoint measurements
            // and exist only at confirmed transition boundaries.
            for extensionArea in scene.signalAreaExtensions {
                let x0 = xPos(extensionArea.start)
                let x1 = xPos(extensionArea.end)
                guard x1 > x0 else { continue }
                let y = yPos(extensionArea.anchorRSSI)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x1, y: y))
                path.addLine(to: CGPoint(x: x1, y: plotBottom))
                path.addLine(to: CGPoint(x: x0, y: plotBottom))
                path.closeSubpath()
                let color = bssidColors[extensionArea.bssid] ?? .blue
                context.fill(path, with: .color(color.opacity(0.045)))
            }

            for run in scene.signalRuns {
                let color = bssidColors[run.bssid] ?? .blue
                let points = run.points.compactMap { point -> CGPoint? in
                    guard let rssi = point.sample.rssi else { return nil }
                    return CGPoint(x: xPos(point.elapsedTime), y: yPos(rssi))
                }
                guard let first = points.first else { continue }
                guard points.count >= 2 else {
                    let dot = CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                    continue
                }
                var signalArea = Path()
                signalArea.move(to: CGPoint(x: points[0].x, y: plotBottom))
                signalArea.addLine(to: points[0])
                addCatmullRomSpline(to: &signalArea, points: points)
                signalArea.addLine(to: CGPoint(x: points[points.count - 1].x, y: plotBottom))
                signalArea.closeSubpath()
                context.fill(signalArea, with: .color(color.opacity(0.12)))
                context.stroke(catmullRomSpline(points: points), with: .color(color), lineWidth: 2)
            }

            // Transition markers
            for transition in scene.transitions {
                let x = xPos(transition.elapsedTime)
                guard x >= plotLeft, x <= plotLeft + plotWidth else { continue }
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: plotTop))
                dash.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(dash, with: .color(.secondary.opacity(0.3)), style: .init(dash: [4, 4], dashPhase: 0))
            }

            // Hover crosshair
            if let highlightedTime {
                let displayedTime = floor(highlightedTime + timeOffset) - timeOffset
                let x = xPos(timeOffset + max(0, min(totalSecs, displayedTime)))
                var hoverLine = Path()
                hoverLine.move(to: CGPoint(x: x, y: plotTop))
                hoverLine.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(hoverLine, with: .color(.primary.opacity(0.5)), style: .init(dash: [3, 3], dashPhase: 0))
            }

            // Hover dot
            if let highlightedSample, let rssi = highlightedSample.sample.rssi {
                let x = xPos(highlightedSample.elapsedTime)
                let y = yPos(rssi)
                let pointRect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: pointRect), with: .color(.white))
                context.stroke(Path(ellipseIn: pointRect), with: .color(.accentColor), lineWidth: 2)
            }
        }
    }
}

// MARK: - Overview Mini Canvas

private struct DebugOverviewCanvas: View {
    @Environment(\.displayScale) private var displayScale
    let scene: RoamingChartScene
    let bssidColors: [String: Color]
    let elapsedTime: TimeInterval
    let highlightedTime: TimeInterval?

    var body: some View {
        Canvas { context, size in
            guard !scene.regions.isEmpty, elapsedTime > 0 else { return }

            let rssiVals = scene.signalRuns.flatMap { $0.points.compactMap { $0.sample.rssi } }
            let rssiMin = Double(min(-100, rssiVals.min() ?? -100))
            let rssiMax = Double(max(-30, rssiVals.max() ?? -30))
            let rssiRange = max(1, rssiMax - rssiMin)

            let timeScale = RoamingChartTimeScale(origin: scene.origin)
            func xPos(_ time: TimeInterval) -> CGFloat {
                timeScale.xPosition(
                    for: time,
                    visibleStart: 0,
                    visibleDuration: elapsedTime,
                    plotLeft: 0,
                    plotWidth: size.width,
                    displayScale: displayScale
                )
            }
            func yPos(_ rssi: Int) -> CGFloat {
                size.height - CGFloat(Double(rssi) - rssiMin) / CGFloat(rssiRange) * size.height
            }

            context.clip(to: Path(CGRect(origin: .zero, size: size)))

            for extensionArea in scene.signalAreaExtensions {
                let x0 = xPos(extensionArea.start)
                let x1 = xPos(extensionArea.end)
                guard x1 > x0 else { continue }
                let y = yPos(extensionArea.anchorRSSI)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: y))
                path.addLine(to: CGPoint(x: x1, y: y))
                path.addLine(to: CGPoint(x: x1, y: size.height))
                path.addLine(to: CGPoint(x: x0, y: size.height))
                path.closeSubpath()
                let color = bssidColors[extensionArea.bssid] ?? .blue
                context.fill(path, with: .color(color.opacity(0.045)))
            }

            for run in scene.signalRuns {
                let color = bssidColors[run.bssid] ?? .blue
                let points = run.points.compactMap { point in
                    point.sample.rssi.map { CGPoint(x: xPos(point.elapsedTime), y: yPos($0)) }
                }
                guard let first = points.first else { continue }
                if points.count == 1 {
                    let dot = CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                } else {
                    var area = Path()
                    area.move(to: CGPoint(x: points[0].x, y: size.height))
                    area.addLine(to: points[0])
                    for point in points.dropFirst() { area.addLine(to: point) }
                    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.12)))

                    var line = Path()
                    line.move(to: first)
                    for point in points.dropFirst() { line.addLine(to: point) }
                    context.stroke(line, with: .color(color), lineWidth: 1)
                }
            }

            for transition in scene.transitions {
                let x = xPos(transition.elapsedTime)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
            }

            if let highlightedTime {
                let x = xPos(floor(highlightedTime))
                var hoverLine = Path()
                hoverLine.move(to: CGPoint(x: x, y: 0))
                hoverLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(hoverLine, with: .color(.primary.opacity(0.5)), style: .init(dash: [3, 3], dashPhase: 0))
            }
        }
    }
}

// MARK: - Timeline Chart with Range Selector

private struct DebugRoamingTimelineChart: View {
    let scene: RoamingChartScene
    let bssidColors: [String: Color]
    let elapsedTime: TimeInterval

    @State private var visibleStart: TimeInterval = 0
    @State private var visibleEnd: TimeInterval = 30
    @State private var hoveredDetailTime: TimeInterval?
    @State private var overviewHoverTime: TimeInterval?
    @State private var overviewPlotWidth: CGFloat = 1

    private var activeHoverTime: TimeInterval? { hoveredDetailTime ?? overviewHoverTime }
    private var highlightedSample: RoamingChartSamplePoint? {
        guard let hoverTime = activeHoverTime else { return nil }
        return scene.samples.min { lhs, rhs in
            abs(lhs.elapsedTime - hoverTime) < abs(rhs.elapsedTime - hoverTime)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            detailChart
            GeometryReader { geo in
                RangeSelector(
                    domain: 0...elapsedTime,
                    minWindowSpan: 5,
                    defaultWindowSpan: 30,
                    overviewHeight: overviewHeight,
                    overview: {
                        DebugOverviewCanvas(
                            scene: scene,
                            bssidColors: bssidColors,
                            elapsedTime: elapsedTime,
                            highlightedTime: highlightedSample?.elapsedTime ?? activeHoverTime
                        )
                    },
                    edgeLabel: { timeFormatter.string(from: $0) ?? "0:00" },
                    onWindowChange: { range in
                        visibleStart = range.start
                        visibleEnd = range.end
                    },
                    onHover: { time in
                        overviewHoverTime = time
                    },
                    followMax: true
                )
                .onAppear { overviewPlotWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in overviewPlotWidth = w }
            }
            .frame(height: overviewHeight)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            overviewTimeAxis
        }
    }

    private var overviewTimeAxis: some View {
        let midTickCount = max(0, min(4, Int(overviewPlotWidth / 100)))
        var allTicks: [TimeInterval] = [0]
        if elapsedTime > 0, midTickCount > 0 {
            let step = elapsedTime / TimeInterval(midTickCount + 1)
            for i in 1...midTickCount {
                allTicks.append(step * TimeInterval(i))
            }
        }
        allTicks.append(max(0, elapsedTime))

        return HStack(spacing: 0) {
            ForEach(Array(allTicks.enumerated()), id: \.offset) { i, tick in
                if i > 0 { Spacer(minLength: 0) }
                Text(timeFormatter.string(from: tick) ?? "0")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var detailChart: some View {
        let chartDuration = max(0.1, elapsedTime)
        let dataStart = min(max(0, visibleStart), chartDuration - 0.1)
        let dataEnd = min(chartDuration, max(dataStart + 0.1, visibleEnd))

        guard !scene.regions.isEmpty else {
            return AnyView(
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No chart data")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: detailChartHeight + topMargin + bottomAxisHeight)
            )
        }
        let rangeSecs = max(0.1, dataEnd - dataStart)

        return AnyView(GeometryReader { geo in
            let plotWidth = max(1, geo.size.width - leftAxisWidth - 8)
            ZStack(alignment: .topLeading) {
                DebugChartCanvas(
                    scene: scene,
                    elapsedTime: rangeSecs,
                    bssidColors: bssidColors,
                    timeOffset: dataStart,
                    highlightedTime: highlightedSample?.elapsedTime ?? activeHoverTime,
                    highlightedSample: highlightedSample
                )

                if let highlightedSample {
                    detailValueBadge(sample: highlightedSample, plotWidth: plotWidth)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let plotX = max(0, min(plotWidth, location.x - leftAxisWidth))
                    hoveredDetailTime = dataStart + TimeInterval(plotX / plotWidth) * rangeSecs
                case .ended:
                    hoveredDetailTime = nil
                }
            }
        }
        .frame(height: detailChartHeight + topMargin + bottomAxisHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .clipped())
    }

    private func detailValueBadge(sample: RoamingChartSamplePoint, plotWidth: CGFloat) -> some View {
        let timeText = timeFormatter.string(from: sample.elapsedTime) ?? "0:00"
        return HStack(spacing: 8) {
            Text(timeText)
            Text(sample.sample.rssi.map { "RSSI \($0) dBm" } ?? "RSSI —")
            Text(sample.sample.channel.map { "Ch \($0)" } ?? "Ch —")
            Text(sample.sample.txRate.map { String(format: "Tx %.0f Mbps", $0) } ?? "Tx —")
            if let latency = sample.sample.gatewayLatency {
                Text(String(format: "RTT %.1f ms", latency))
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassBackground(.regular, in: Capsule())
        .padding(.leading, 12)
        .padding(.top, 6)
    }
}

// MARK: - RSSI color

private func rssiColor(_ rssi: Int) -> Color {
    if rssi >= -50 { return .green }
    if rssi >= -70 { return .yellow }
    if rssi >= -85 { return .orange }
    return .red
}

#endif
