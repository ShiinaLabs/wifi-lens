import SwiftUI
import ChartLens

/// Canvas-based time-series chart showing RSSI over time for a selected BLE device.
/// Draws two lines: raw RSSI (thin, semi-transparent) and EMA-smoothed RSSI (thick, solid).
struct BLETrendChartView: View {
    let samples: [BLERSSISample]
    let color: Color

    private let chartHeight: CGFloat = 200

    var body: some View {
        if samples.count < 2 {
            Text(String(localized: "common.label.collecting_data", comment: "Status shown while collecting sensor data"))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(height: chartHeight)
        } else {
            Chart(series: buildSeries(), axis: axisConfig, style: chartStyle)
                .accessibilityLabel(String(format: String(localized: "ble.accessibility.trend_chart_fmt", comment: "BLE trend chart accessibility label with sample count and range"), samples.count, Int(samples.map(\.smoothedRSSI).min() ?? 0), Int(samples.map(\.smoothedRSSI).max() ?? 0)))
                .frame(height: chartHeight)
        }
    }

    private let chartStyle = ChartStyle(
        leftAxisWidth: 36,
        bottomAxisHeight: 20,
        marginTop: 8,
        marginRight: 4,
        marginBottom: 4
    )

    private var axisConfig: ChartAxisConfig {
        let rawValues = samples.map { Double($0.rawRSSI) }
        let yMin = (rawValues.min() ?? -100) - 10
        let yMax = (rawValues.max() ?? -30) + 10
        let firstTime = samples.first!.timestamp

        var axis = ChartAxisConfig()
        axis.yMin = floor(yMin / 10) * 10
        axis.yMax = ceil(yMax / 10) * 10
        axis.yStep = 10

        var ticks: [ChartAxisConfig.XTick] = []
        for i in 0..<min(4, samples.count) {
            let idx = i * (samples.count - 1) / max(3, 1)
            let clampedIdx = min(idx, samples.count - 1)
            let elapsed = samples[clampedIdx].timestamp.timeIntervalSince(firstTime)
            ticks.append(ChartAxisConfig.XTick(position: Double(clampedIdx), label: formatElapsed(elapsed)))
        }
        axis.xTicks = ticks
        return axis
    }

    private func buildSeries() -> [ChartSeries<ChartPoint>] {
        // Smoothed line (thick, solid)
        let smoothPts: [ChartPoint] = samples.enumerated().map { i, s in
            ChartPoint(x: Double(i), y: s.smoothedRSSI)
        }
        let smoothStyle = ChartSeriesStyle(
            color: color, lineWidth: 1.5, areaOpacity: 0.08,
            pointRadius: 0, strokeOpacity: 1.0, interpolation: .linear
        )

        // Raw line (thin, transparent)
        let rawPts: [ChartPoint] = samples.enumerated().map { i, s in
            ChartPoint(x: Double(i), y: Double(s.rawRSSI))
        }
        let rawStyle = ChartSeriesStyle(
            color: color, lineWidth: 0.8, areaOpacity: 0,
            pointRadius: 0, strokeOpacity: 0.3, interpolation: .linear
        )

        return [
            ChartSeries(id: "smooth", points: smoothPts, style: smoothStyle),
            ChartSeries(id: "raw", points: rawPts, style: rawStyle),
        ]
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        return "\(Int(seconds / 60))m"
    }
}
