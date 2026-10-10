import SwiftUI
import AppKit
import ChartLens

// MARK: - Chart Layout

private let pointSpacing: CGFloat = 4
private let chartHeight: CGFloat = 180
private let leftAxisWidth: CGFloat = 40
private let bottomAxisHeight: CGFloat = 24
private let topMargin: CGFloat = 40

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

// MARK: - Formatters

private let timeFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.minute, .second]
    f.unitsStyle = .positional
    f.zeroFormattingBehavior = .pad
    return f
}()

// MARK: - View

public struct RoamingTestView: View {
    @Bindable var viewModel: RoamingTestViewModel
    @State private var showStartConfirmation = false

    public init(viewModel: RoamingTestViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isPortable {
                nonPortableWarning
            }

            switch viewModel.state {
            case .idle:
                idleState
            case .ready, .running, .stopped:
                runningContent
            }
        }
        .task {
            if viewModel.state == .idle {
                viewModel.checkReadiness()
            }
        }
        .alert(String(localized: "roaming.overwrite.title", comment: "Confirm overwrite roaming session data"),
               isPresented: $showStartConfirmation) {
            Button(String(localized: "common.action.cancel", comment: "Cancel action"), role: .cancel) { }
            Button(String(localized: "common.action.overwrite", comment: "Overwrite / discard and start new session"), role: .destructive) {
                viewModel.startTest()
            }
        } message: {
            Text(String(localized: "roaming.overwrite.message", comment: "Warning that starting a new roaming test will discard current session data"))
        }
    }

    // MARK: - Non-portable warning

    private var nonPortableWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(String(localized: "roaming.warning.not_portable", comment: "Warning that roaming test needs a laptop, not desktop Mac"))
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: 16) {
            Spacer()
            if let error = viewModel.errorMessage {
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text(error)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(String(localized: "common.action.check_again", comment: "Check again button")) {
                    viewModel.checkReadiness()
                }
                .padding(.top, 8)
            } else {
                ProgressView()
                Text(String(localized: "overview.status.checking", comment: "Status while checking Wi-Fi connection"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roaming-idle-state")
    }

    // MARK: - Running / Stopped content

    private var runningContent: some View {
        VStack(spacing: 0) {
            signalInfoCard
            statusBar
            trendChart
            transitionTable
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roaming-active-state")
    }

    // MARK: - Signal info card

    private var signalInfoCard: some View {
        HStack(spacing: 16) {
            // Left: SSID + status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(viewModel.currentSSID ?? "—")
                        .font(.title3.weight(.semibold))
                        // Same guardrail as OverviewView.connectionCard: without a line
                        // limit, an unbreakable long SSID would push the metrics off
                        // the card at narrow widths.
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(viewModel.currentSSID ?? "")
                }
                HStack(spacing: 8) {
                    if let bssid = viewModel.currentBSSID {
                        Text(bssid)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let phy = viewModel.currentPhyMode {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(phy)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Right: metrics
            HStack(spacing: 20) {
                let rssi = viewModel.currentRSSI
                metricLabel(String(localized: "channels.table.col.rssi", comment: "RSSI column header"), rssi.map { "\($0) dBm" } ?? "—", rssi.map(rssiColor) ?? .secondary)
                metricLabel(String(localized: "overview.health.channel_label", comment: "Channel quality health indicator label"), viewModel.currentChannel.map(String.init) ?? "—", .primary)
                metricLabel(String(localized: "interfaces.field.tx_rate", comment: "Transmit rate field label"), viewModel.currentTxRate.map { String(format: "%.0f Mbps", $0) } ?? "—", .primary)
                if let latency = viewModel.gatewayLatency {
                    metricLabel(String(localized: "roaming.field.latency", comment: "Latency field label in roaming view"), String(format: "%.1f ms", latency), latencyColor(latency))
                        .accessibilityLabel(String(format: String(localized: "roaming.accessibility.latency_fmt", comment: "Latency accessibility label with value and quality"), String(format: "%.1f", latency), latencyQualityDescription(latency)))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func metricLabel(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundColor(color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text(timeFormatter.string(from: viewModel.elapsedTime) ?? "0:00")
                    .font(.subheadline.monospacedDigit())
            }

            HStack(spacing: 4) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text("\(viewModel.totalSamples) \(String(localized: "common.label.samples", comment: "Sample count unit label"))")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text("\(viewModel.transitions.count) \(String(localized: "common.label.transitions", comment: "AP transition count unit label"))")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.state == .stopped, viewModel.totalSamples > 0 {
                Button {
                    viewModel.saveSession()
                } label: {
                    Label(String(localized: "common.action.save", comment: "Save button label"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "common.action.save", comment: "Save button label"))
                .accessibilityIdentifier("roaming-save-session-button")
            }

            if viewModel.state != .running {
                Button {
                    viewModel.loadSession()
                } label: {
                    Label(String(localized: "common.action.load", comment: "Load button label"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "common.action.load", comment: "Load button label"))
                .accessibilityIdentifier("roaming-load-session-button")
            }

            if viewModel.isRunning {
                Button {
                    viewModel.stopTest()
                } label: {
                    Label(String(localized: "common.action.stop", comment: "Stop action button"), systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .help(String(localized: "roaming.control.stop_tooltip", comment: "Tooltip for stop roaming test button"))
                .accessibilityLabel(String(localized: "roaming.control.stop_tooltip", comment: "Tooltip for stop roaming test button"))
                .accessibilityIdentifier("roaming.stop-button")
            } else {
                Button {
                    if viewModel.state == .stopped, viewModel.totalSamples > 0 {
                        showStartConfirmation = true
                    } else {
                        viewModel.startTest()
                    }
                } label: {
                    Label(String(localized: "common.action.start", comment: "Start action button"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!viewModel.canStart)
                .help(String(localized: "roaming.control.start_tooltip", comment: "Tooltip for start roaming test button"))
                .accessibilityLabel(String(localized: "roaming.control.start_tooltip", comment: "Tooltip for start roaming test button"))
                .accessibilityIdentifier("roaming.start-button")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Trend chart

    private var trendChart: some View {
        let allSamples = segments.flatMap { $0.samples }.sorted { $0.timestamp < $1.timestamp }
        let totalSeconds = max(1, viewModel.elapsedTime)
        let bssidColors = buildBSSIDColorMap(from: viewModel.segments)
        return RoamingTimelineChart(
            segments: viewModel.segments,
            transitions: viewModel.transitions,
            allSamples: allSamples,
            bssidColors: bssidColors,
            elapsedTime: totalSeconds
        )
    }

    private var segments: [RoamingSegment] { viewModel.segments }

    // MARK: - Transition table

    private var transitionTable: some View {
        Group {
            if viewModel.transitions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.triangle.swap")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text(String(localized: viewModel.isRunning ? "roaming.state.waiting" : "roaming.state.no_transitions"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Header
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            tableHeader(String(localized: "roaming.table.col.time", comment: "Time column header in transition table"))
                            tableHeader(String(localized: "roaming.table.col.from_bssid", comment: "Source BSSID column header"))
                            tableHeader(String(localized: "roaming.table.col.to_bssid", comment: "Destination BSSID column header"))
                            tableHeader(String(localized: "roaming.table.col.rssi_before", comment: "RSSI before transition column header"))
                            tableHeader(String(localized: "roaming.table.col.rssi_after", comment: "RSSI after transition column header"))
                            tableHeader(String(localized: "roaming.table.col.ch_before", comment: "Channel before transition column header"))
                            tableHeader(String(localized: "roaming.table.col.ch_after", comment: "Channel after transition column header"))
                        }
                    }

                    ScrollView {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            ForEach(Array(viewModel.transitions.enumerated()), id: \.element.id) { idx, t in
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
        }
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
    }

    private func tableCell(_ text: String, mono: Bool = false, color: Color = .primary) -> some View {
        Text(text)
            .font(mono ? .caption.monospacedDigit() : .caption)
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

private struct ChartCanvas: View {
    let segments: [RoamingSegment]
    let transitions: [APTransitionEvent]
    let allSamples: [RoamingSample]
    let chartWidth: CGFloat?
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

            guard plotWidth > 0, plotHeight > 0, !allSamples.isEmpty else { return }

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
                    .font(.caption2)
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
                    .font(.caption2)
                    .foregroundColor(.secondary)
                let resolved = context.resolve(label)
                context.draw(resolved, at: CGPoint(x: x, y: plotBottom + 6))
                t += timeStep
            }

            for (_, segment) in segments.enumerated() {
                let visibleSamples = segment.samples.filter { sample in
                    let t = sample.timestamp.timeIntervalSince(sessionStartDate) - timeOffset
                    return t >= 0 && t <= elapsedTime
                }
                guard visibleSamples.count >= 2 else { continue }
                let midIdx = visibleSamples.count / 2
                let midX = xPos(visibleSamples[midIdx].timestamp)
                let color = bssidColors[segment.bssid] ?? .blue
                let label = Text(segment.bssid)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(color)
                let resolved = context.resolve(label)
                let labelW = resolved.measure(in: CGSize(width: 200, height: 20)).width
                context.draw(resolved, at: CGPoint(x: min(midX, plotLeft + plotWidth - labelW / 2), y: topMargin - 8))
            }

            let clipRect = Path(CGRect(x: plotLeft, y: plotTop - 4, width: plotWidth, height: plotHeight + 8))
            context.clip(to: clipRect)

            for (_, segment) in segments.enumerated() {
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

                    var areaPath = Path()
                    areaPath.move(to: CGPoint(x: points[0].x, y: plotBottom))
                    areaPath.addLine(to: points[0])
                    addCatmullRomSpline(to: &areaPath, points: points)
                    areaPath.addLine(to: CGPoint(x: points[points.count - 1].x, y: plotBottom))
                    areaPath.closeSubpath()
                    context.fill(areaPath, with: .color(color.opacity(0.12)))

                    context.stroke(catmullRomSpline(points: points), with: .color(color), lineWidth: 2)
                }
            }

            for transition in transitions {
                let x = xPos(transition.timestamp)
                guard x >= plotLeft, x <= plotLeft + plotWidth else { continue }
                var dash = Path()
                dash.move(to: CGPoint(x: x, y: plotTop))
                dash.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(dash, with: .color(.secondary.opacity(0.3)), style: .init(dash: [4, 4], dashPhase: 0))
            }

            if let highlightedTime {
                let x = plotLeft + CGFloat(max(0, min(totalSecs, highlightedTime - timeOffset))) * scaleX
                var hoverLine = Path()
                hoverLine.move(to: CGPoint(x: x, y: plotTop))
                hoverLine.addLine(to: CGPoint(x: x, y: plotBottom))
                context.stroke(hoverLine, with: .color(.primary.opacity(0.5)), style: .init(dash: [3, 3], dashPhase: 0))
            }

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

// MARK: - Timeline Chart with Range Selector

private let overviewHeight: CGFloat = 48
private let detailChartHeight: CGFloat = 160

private struct RoamingTimelineChart: View {
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
        guard let hoverTime = activeHoverTime, let sessionStart = allSamples.first?.timestamp else { return nil }
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
                        OverviewCanvas(
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

    // MARK: Detail chart

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
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var detailChart: some View {
        let sessionStart = allSamples.first?.timestamp ?? Date()
        let visibleSamples = allSamples.filter {
            let t = $0.timestamp.timeIntervalSince(sessionStart)
            return t >= visibleStart && t <= visibleEnd
        }

        guard let firstSample = visibleSamples.first, let lastSample = visibleSamples.last else {
            return AnyView(
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))
                        .accessibilityHidden(true)
                    Text(String(localized: "common.empty.no_chart_data", comment: "Empty state when no chart data is available"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(height: detailChartHeight + topMargin + bottomAxisHeight)
            )
        }
        let dataStart = firstSample.timestamp.timeIntervalSince(sessionStart)
        let dataEnd = lastSample.timestamp.timeIntervalSince(sessionStart)
        let rangeSecs = max(0.1, dataEnd - dataStart)

        return AnyView(GeometryReader { geo in
            let plotWidth = max(1, geo.size.width - leftAxisWidth - 8)
            ZStack(alignment: .topLeading) {
                ChartCanvas(
                    segments: segments,
                    transitions: transitions,
                    allSamples: visibleSamples,
                    chartWidth: nil,
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
            Text(sample.rssi.map { String(format: String(localized: "roaming.detail.rssi_fmt", comment: "Roaming detail RSSI badge"), $0) } ?? "—")
            Text(sample.channel.map { String(format: String(localized: "roaming.detail.channel_fmt", comment: "Roaming detail channel badge"), $0) } ?? "—")
            Text(sample.txRate.map { String(format: String(localized: "roaming.detail.tx_rate_fmt", comment: "Roaming detail Tx rate badge"), $0) } ?? "—")
            if let latency = sample.gatewayLatency {
                Text(String(format: String(localized: "roaming.detail.rtt_fmt", comment: "Roaming detail RTT badge"), latency))
            }
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassBackground(.regular, in: Capsule())
        .padding(.leading, 12)
        .padding(.top, 6)
    }
}

// MARK: - Overview mini canvas

private struct OverviewCanvas: View {
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

            let startDate = segments.first?.samples.first?.timestamp ?? Date()

            func xPos(_ ts: Date) -> CGFloat {
                CGFloat(ts.timeIntervalSince(startDate) / elapsedTime) * size.width
            }
            func yPos(_ rssi: Int) -> CGFloat {
                size.height - CGFloat(Double(rssi) - rssiMin) / CGFloat(rssiRange) * size.height
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

// MARK: - RSSI color

private func rssiColor(_ rssi: Int) -> Color {
    if rssi >= -50 { return .green }
    if rssi >= -70 { return .yellow }
    if rssi >= -85 { return .orange }
    return .red
}

private func latencyColor(_ ms: Double) -> Color {
    if ms < 5 { return .green }
    if ms < 20 { return .yellow }
    return .red
}

private func rssiQualityDescription(_ rssi: Int) -> String {
    if rssi >= -55 { return String(localized: "overview.signal.strong", comment: "Strong signal level label") }
    if rssi >= -70 { return String(localized: "overview.signal.good", comment: "Good signal level label") }
    if rssi >= -85 { return String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier") }
    return String(localized: "overview.signal.weak", comment: "Weak signal level label")
}

private func latencyQualityDescription(_ ms: Double) -> String {
    if ms < 5 { return String(localized: "roaming.latency.excellent", comment: "Excellent latency level") }
    if ms < 20 { return String(localized: "roaming.latency.good", comment: "Good latency level") }
    return String(localized: "roaming.latency.poor", comment: "Poor latency level")
}
