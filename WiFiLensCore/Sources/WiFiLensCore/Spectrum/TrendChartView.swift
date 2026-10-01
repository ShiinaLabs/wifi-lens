import SwiftUI
import ChartLens

struct TrendChartView: View {
    let snapshots: [NetworkSnapshot]
    let color: Color

    var body: some View {
        if snapshots.count < 2 {
            Text(String(localized: "common.label.collecting_data", comment: "Status shown while collecting sensor data"))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            Chart(series: buildSeries(), axis: axisConfig, style: chartStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(accessibilitySummary)
        }
    }

    private let chartStyle = ChartStyle(
        leftAxisWidth: 36,
        bottomAxisHeight: 20,
        marginTop: 8,
        marginRight: 8,
        marginBottom: 4
    )

    private var axisConfig: ChartAxisConfig {
        let values = snapshots.map(\.rssi)
        let dataMin = Double(values.min() ?? -90)
        let dataMax = Double(values.max() ?? -30)
        let headroom: Double = 6
        let baseTime = snapshots[0].timestamp

        var axis = ChartAxisConfig()
        axis.yMin = max(Double(Constants.rssiNoiseFloor), dataMin - headroom)
        axis.yMax = min(0.0, dataMax + headroom)
        axis.yStep = 10
        axis.yTickLabelOffset = 14

        // X-axis time labels positioned at real elapsed offsets from the first sample.
        let latestTime = snapshots[snapshots.count - 1].timestamp
        let tickCount = min(5, max(2, snapshots.count))
        var ticks: [ChartAxisConfig.XTick] = []
        for t in 0..<tickCount {
            let idx = t * (snapshots.count - 1) / max(1, tickCount - 1)
            let offset = snapshots[idx].timestamp.timeIntervalSince(baseTime)
            let secsAgo = latestTime.timeIntervalSince(snapshots[idx].timestamp)
            ticks.append(ChartAxisConfig.XTick(position: offset, label: chartDurationLabel(secsAgo, zeroText: String(localized: "common.label.now", comment: "Just now timestamp indicator"))))
        }
        axis.xTicks = ticks
        axis.xTickLabelOffset = 10
        return axis
    }

    private func buildSeries() -> [ChartSeries<ChartPoint>] {
        let baseTime = snapshots[0].timestamp
        let points: [ChartPoint] = snapshots.map { snap in
            ChartPoint(x: snap.timestamp.timeIntervalSince(baseTime), y: Double(snap.rssi))
        }
        let style = ChartSeriesStyle(
            color: color,
            lineWidth: 1.5,
            areaOpacity: 0.12,
            pointRadius: 2.0,
            strokeOpacity: 1.0,
            interpolation: .linear
        )
        return [ChartSeries(id: "trend", points: points, style: style)]
    }

    /// Meaningful summary for assistive tech: conveys the direction and magnitude
    /// of the signal change rather than just the sample count.
    private var accessibilitySummary: String {
        let first = snapshots[0].rssi
        let last = snapshots[snapshots.count - 1].rssi
        let delta = last - first
        let count = snapshots.count
        switch delta {
        case 2...:
            return String(
                format: String(localized: "spectrum.accessibility.trend_improving_fmt", comment: "RSSI trend improving: from, to, and sample count"),
                first, last, delta, count
            )
        case ...(-2):
            return String(
                format: String(localized: "spectrum.accessibility.trend_declining_fmt", comment: "RSSI trend declining: from, to, change amount, and sample count"),
                first, last, abs(delta), count
            )
        default:
            return String(
                format: String(localized: "spectrum.accessibility.trend_stable_fmt", comment: "RSSI trend stable: level and sample count"),
                last, count
            )
        }
    }
}
