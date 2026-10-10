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

private func generateTestData() -> (segments: [RoamingSegment], transitions: [APTransitionEvent], allSamples: [RoamingSample]) {
    let baseDate = Date()

    func makeSamples(from: Int, to: Int, channel: Int, rssiStart: Double, rssiEnd: Double, wobbleFreq: Double, wobblePhase: Double, wobbleAmp: Double, txStart: Double, txEnd: Double) -> [RoamingSample] {
        let count = to - from
        return (from...to).map { second in
            let progress = Double(second - from) / Double(max(1, count))
            let timestamp = baseDate.addingTimeInterval(TimeInterval(second))
            let base = rssiStart + (rssiEnd - rssiStart) * progress
            let wobble = sin(Double(second) * wobbleFreq + wobblePhase) * wobbleAmp
            let rssi = Int((base + wobble + Double.random(in: -2...2)).rounded())
            let txRate = max(30, txStart + (txEnd - txStart) * progress + Double.random(in: -25...25))
            let latency: Double? = second % 5 == 0 ? Double.random(in: 2.5...18.0) : nil
            return RoamingSample(
                timestamp: timestamp,
                rssi: rssi,
                channel: channel,
                txRate: txRate,
                gatewayLatency: latency
            )
        }
    }

    let seg1Samples = makeSamples(from: 0, to: 60, channel: 36,
                                   rssiStart: -42, rssiEnd: -72,
                                   wobbleFreq: 0.3, wobblePhase: 0, wobbleAmp: 4,
                                   txStart: 866, txEnd: 666)
    let seg2Samples = makeSamples(from: 60, to: 130, channel: 149,
                                   rssiStart: -50, rssiEnd: -78,
                                   wobbleFreq: 0.25, wobblePhase: 1.5, wobbleAmp: 5,
                                   txStart: 650, txEnd: 350)
    let seg3Samples = makeSamples(from: 130, to: 180, channel: 48,
                                   rssiStart: -48, rssiEnd: -55,
                                   wobbleFreq: 0.35, wobblePhase: 2.0, wobbleAmp: 3.5,
                                   txStart: 780, txEnd: 680)

    // Merge: at overlap points, keep the new segment's sample (drop first of later segments)
    let allSamples = seg1Samples + seg2Samples.dropFirst() + seg3Samples.dropFirst()

    let segment1 = RoamingSegment(
        bssid: "aa:bb:cc:dd:ee:01",
        startTime: seg1Samples.first!.timestamp,
        endTime: seg1Samples.last!.timestamp,
        samples: seg1Samples
    )
    let segment2 = RoamingSegment(
        bssid: "aa:bb:cc:dd:ee:02",
        startTime: seg2Samples.first!.timestamp,
        endTime: seg2Samples.last!.timestamp,
        samples: seg2Samples
    )
    let segment3 = RoamingSegment(
        bssid: "aa:bb:cc:dd:ee:03",
        startTime: seg3Samples.first!.timestamp,
        endTime: seg3Samples.last!.timestamp,
        samples: seg3Samples
    )

    let t1 = APTransitionEvent(
        timestamp: seg2Samples.first!.timestamp,
        fromBSSID: "aa:bb:cc:dd:ee:01",
        toBSSID: "aa:bb:cc:dd:ee:02",
        rssiBefore: seg1Samples.last!.rssi,
        rssiAfter: seg2Samples.first!.rssi,
        channelBefore: 36,
        channelAfter: 149
    )
    let t2 = APTransitionEvent(
        timestamp: seg3Samples.first!.timestamp,
        fromBSSID: "aa:bb:cc:dd:ee:02",
        toBSSID: "aa:bb:cc:dd:ee:03",
        rssiBefore: seg2Samples.last!.rssi,
        rssiAfter: seg3Samples.first!.rssi,
        channelBefore: 149,
        channelAfter: 48
    )

    return (
        segments: [segment1, segment2, segment3],
        transitions: [t1, t2],
        allSamples: allSamples
    )
}

// MARK: - Debug Roaming Chart View

struct DebugRoamingChartView: View {
    private let segments: [RoamingSegment]
    private let transitions: [APTransitionEvent]
    private let allSamples: [RoamingSample]
    private let bssidColors: [String: Color]

    init() {
        let data = generateTestData()
        self.segments = data.segments
        self.transitions = data.transitions
        self.allSamples = data.allSamples
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
                Text("Hardcoded test data · 3 APs · 180s · \(allSamples.count) samples")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 16) {
                statBadge("arrow.triangle.swap", "\(transitions.count) transitions")
                statBadge("chart.xyaxis.line", "\(allSamples.count) samples")
                statBadge("clock", "3:00")
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
            segments: segments,
            transitions: transitions,
            allSamples: allSamples,
            bssidColors: bssidColors,
            elapsedTime: 180
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
                    ForEach(Array(transitions.enumerated()), id: \.element.id) { idx, t in
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
    let segments: [RoamingSegment]
    let transitions: [APTransitionEvent]
    let allSamples: [RoamingSample]
    let elapsedTime: TimeInterval
    let bssidColors: [String: Color]
    var timeOffset: TimeInterval = 0
    var sessionStartDate: Date = Date()
    var highlightedTime: TimeInterval?
    var highlightedSample: RoamingSample?

    var body: some View {
        Canvas { context, size in
            let plotLeft = leftAxisWidth
            let plotTop = topMargin
            let plotWidth = size.width - plotLeft - 8
            let plotBottom = size.height - bottomAxisHeight
            let plotHeight = plotBottom - plotTop

            guard plotWidth > 0, plotHeight > 0, !segments.isEmpty else { return }

            let measuredRSSI = allSamples.compactMap(\.rssi)
            let rssiMin = min(-100, measuredRSSI.min() ?? -100)
            let rssiMax = max(-30, measuredRSSI.max() ?? -30)
            let rssiRange = Double(max(1, rssiMax - rssiMin))

            let totalSecs = max(1, elapsedTime)
            let scaleX = plotWidth / CGFloat(totalSecs)

            func xPos(_ ts: Date) -> CGFloat {
                plotLeft + CGFloat(ts.timeIntervalSince(sessionStartDate) - timeOffset) * scaleX
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
                let x = plotLeft + CGFloat(t) * scaleX
                let label = Text(timeFormatter.string(from: t + timeOffset) ?? "0")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                let resolved = context.resolve(label)
                context.draw(resolved, at: CGPoint(x: x, y: plotBottom + 6))
                t += timeStep
            }

            // BSSID labels per segment
            for segment in segments {
                let visibleSamples = segment.samples.filter { sample in
                    let t = sample.timestamp.timeIntervalSince(sessionStartDate) - timeOffset
                    return t >= 0 && t <= elapsedTime
                }
                guard visibleSamples.count >= 2 else { continue }
                let midIdx = visibleSamples.count / 2
                let midX = xPos(visibleSamples[midIdx].timestamp)
                let color = bssidColors[segment.bssid] ?? .blue
                let label = Text(segment.bssid)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color)
                let resolved = context.resolve(label)
                let labelW = resolved.measure(in: CGSize(width: 200, height: 20)).width
                context.draw(resolved, at: CGPoint(x: min(midX, plotLeft + plotWidth - labelW / 2), y: topMargin - 8))
            }

            // Clip
            let clipRect = Path(CGRect(x: plotLeft, y: plotTop - 4, width: plotWidth, height: plotHeight + 8))
            context.clip(to: clipRect)

            // AP ownership intervals are filled separately from measured RSSI.
            let visibleStart = sessionStartDate.addingTimeInterval(timeOffset)
            let visibleEnd = visibleStart.addingTimeInterval(elapsedTime)
            for region in RoamingRegionLayout.intervals(segments: segments, transitions: transitions) {
                let start = max(region.startTime, visibleStart)
                let end = min(region.endTime, visibleEnd)
                guard end > start else { continue }
                let x0 = max(plotLeft, xPos(start))
                let x1 = min(plotLeft + plotWidth, xPos(end))
                guard x1 > x0 else { continue }
                let ownershipBandHeight: CGFloat = 4
                let rect = CGRect(
                    x: x0,
                    y: plotBottom - ownershipBandHeight,
                    width: x1 - x0,
                    height: ownershipBandHeight
                )
                let color = bssidColors[region.bssid] ?? .blue
                context.fill(Path(rect), with: .color(color.opacity(0.3)))
            }

            // Draw measured RSSI runs without bridging missing samples.
            for segment in segments {
                let color = bssidColors[segment.bssid] ?? .blue
                for run in segment.rssiRuns {
                    let samples = run.filter { sample in
                        let t = sample.timestamp.timeIntervalSince(sessionStartDate) - timeOffset
                        return t >= 0 && t <= elapsedTime
                    }
                    let points = samples.compactMap { sample in
                        sample.rssi.map { CGPoint(x: xPos(sample.timestamp), y: yPos($0)) }
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
            }

            // Transition markers
            for transition in transitions {
                let x = xPos(transition.timestamp)
                guard x >= plotLeft, x <= plotLeft + plotWidth else { continue }
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: plotTop))
                dash.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(dash, with: .color(.secondary.opacity(0.3)), style: .init(dash: [4, 4], dashPhase: 0))
            }

            // Hover crosshair
            if let highlightedTime {
                let x = plotLeft + CGFloat(max(0, min(totalSecs, highlightedTime - timeOffset))) * scaleX
                var hoverLine = Path()
                hoverLine.move(to: CGPoint(x: x, y: plotTop))
                hoverLine.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(hoverLine, with: .color(.primary.opacity(0.5)), style: .init(dash: [3, 3], dashPhase: 0))
            }

            // Hover dot
            if let highlightedSample, let rssi = highlightedSample.rssi {
                let x = xPos(highlightedSample.timestamp)
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
    let segments: [RoamingSegment]
    let transitions: [APTransitionEvent]
    let bssidColors: [String: Color]
    let elapsedTime: TimeInterval
    let highlightedTime: TimeInterval?

    var body: some View {
        Canvas { context, size in
            guard !segments.isEmpty, elapsedTime > 0 else { return }

            var rssiVals: [Int] = []
            for seg in segments { rssiVals.append(contentsOf: seg.samples.compactMap(\.rssi)) }
            let rssiMin = Double(min(-100, rssiVals.min() ?? -100))
            let rssiMax = Double(max(-30, rssiVals.max() ?? -30))
            let rssiRange = max(1, rssiMax - rssiMin)

            let startDate = segments.first?.startTime ?? Date()

            func xPos(_ ts: Date) -> CGFloat {
                CGFloat(ts.timeIntervalSince(startDate) / elapsedTime) * size.width
            }
            func yPos(_ rssi: Int) -> CGFloat {
                size.height - CGFloat(Double(rssi) - rssiMin) / CGFloat(rssiRange) * size.height
            }

            for region in RoamingRegionLayout.intervals(segments: segments, transitions: transitions) {
                let x0 = max(0, xPos(region.startTime))
                let x1 = min(size.width, xPos(region.endTime))
                guard x1 > x0 else { continue }
                let rect = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
                let color = bssidColors[region.bssid] ?? .blue
                context.fill(Path(rect), with: .color(color.opacity(0.06)))
            }

            for segment in segments {
                let color = bssidColors[segment.bssid] ?? .blue
                for run in segment.rssiRuns {
                    let points = run.compactMap { sample in
                        sample.rssi.map { CGPoint(x: xPos(sample.timestamp), y: yPos($0)) }
                    }
                    guard let first = points.first else { continue }
                    if points.count == 1 {
                        let dot = CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3)
                        context.fill(Path(ellipseIn: dot), with: .color(color))
                    } else {
                        var path = Path()
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        context.stroke(path, with: .color(color), lineWidth: 1)
                    }
                }
            }

            for t in transitions {
                let x = xPos(t.timestamp)
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
            }

            if let highlightedTime {
                let x = CGFloat(highlightedTime / elapsedTime) * size.width
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
    let segments: [RoamingSegment]
    let transitions: [APTransitionEvent]
    let allSamples: [RoamingSample]
    let bssidColors: [String: Color]
    let elapsedTime: TimeInterval

    @State private var visibleStart: TimeInterval = 0
    @State private var visibleEnd: TimeInterval = 30
    @State private var hoveredDetailTime: TimeInterval?
    @State private var overviewHoverTime: TimeInterval?
    @State private var overviewPlotWidth: CGFloat = 1

    private var activeHoverTime: TimeInterval? { hoveredDetailTime ?? overviewHoverTime }
    private var highlightedSample: RoamingSample? {
        guard let hoverTime = activeHoverTime,
              let sessionStart = segments.first?.startTime ?? allSamples.first?.timestamp else { return nil }
        return allSamples.min { lhs, rhs in
            abs(lhs.timestamp.timeIntervalSince(sessionStart) - hoverTime) < abs(rhs.timestamp.timeIntervalSince(sessionStart) - hoverTime)
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
                            segments: segments,
                            transitions: transitions,
                            bssidColors: bssidColors,
                            elapsedTime: elapsedTime,
                            highlightedTime: activeHoverTime
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
        let sessionStart = segments.first?.startTime ?? allSamples.first?.timestamp ?? Date()
        let chartDuration = max(0.1, elapsedTime)
        let dataStart = min(max(0, visibleStart), chartDuration - 0.1)
        let dataEnd = min(chartDuration, max(dataStart + 0.1, visibleEnd))
        let visibleSamples = allSamples.filter {
            let t = $0.timestamp.timeIntervalSince(sessionStart)
            return t >= dataStart && t <= dataEnd
        }

        guard !segments.isEmpty else {
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
                    segments: segments,
                    transitions: transitions,
                    allSamples: visibleSamples,
                    elapsedTime: rangeSecs,
                    bssidColors: bssidColors,
                    timeOffset: dataStart,
                    sessionStartDate: sessionStart,
                    highlightedTime: activeHoverTime,
                    highlightedSample: highlightedSample
                )

                if let highlightedSample, let hoverTime = activeHoverTime {
                    detailValueBadge(sample: highlightedSample, time: hoverTime, plotWidth: plotWidth)
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

    private func detailValueBadge(sample: RoamingSample, time: TimeInterval, plotWidth: CGFloat) -> some View {
        let timeText = timeFormatter.string(from: time) ?? "0:00"
        return HStack(spacing: 8) {
            Text(timeText)
            Text(sample.rssi.map { "RSSI \($0) dBm" } ?? "RSSI —")
            Text(sample.channel.map { "Ch \($0)" } ?? "Ch —")
            Text(sample.txRate.map { String(format: "Tx %.0f Mbps", $0) } ?? "Tx —")
            if let latency = sample.gatewayLatency {
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
