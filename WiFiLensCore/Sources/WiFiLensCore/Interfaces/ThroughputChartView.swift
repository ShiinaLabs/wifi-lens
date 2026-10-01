import SwiftUI
import ChartLens

public struct ThroughputChartView: View {
    let samples: [ThroughputSample]
    let interfaceName: String

    public init(samples: [ThroughputSample], interfaceName: String) {
        self.samples = samples
        self.interfaceName = interfaceName
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Legend header
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text(String(localized: "common.label.download", comment: "Download/throughput receive label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text(String(localized: "common.label.upload", comment: "Upload/throughput send label"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(interfaceName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, chartStyle.leftAxisWidth + 4)
            .padding(.bottom, 2)

            if samples.count < 2 {
                Spacer()
                Text(String(localized: "common.label.collecting_data", comment: "Status shown while collecting sensor data"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                Chart(series: buildSeries(), axis: axisConfig, style: chartStyle)
            }
        }
    }

    private let chartStyle = ChartStyle(
        leftAxisWidth: 48,
        bottomAxisHeight: 26,
        marginTop: 10,
        marginRight: 10,
        marginBottom: 6
    )

    private var axisConfig: ChartAxisConfig {
        let maxUp = samples.map(\.rateOut).max() ?? 1
        let maxDown = samples.map(\.rateIn).max() ?? 1
        let maxRate = max(maxUp, maxDown, 1_024) * 1.15
        let now = samples.last?.timestamp ?? Date()

        var axis = ChartAxisConfig()
        axis.yMin = -maxRate
        axis.yMax = maxRate
        axis.yStep = maxRate / 4
        axis.showYAxis = true
        axis.yTickLabelOffset = 24
        axis.yTickFont = .system(size: 8)
        axis.gridColor = .gray.opacity(0.12)
        axis.yTickLabel = { rateLabel(abs($0)) }

        // X-axis time labels
        let tickIndices = evenlySpacedTickIndices(count: samples.count, targetCount: min(6, max(3, samples.count / 15)))
        var ticks: [ChartAxisConfig.XTick] = []
        for idx in tickIndices {
            let secs = now.timeIntervalSince(samples[idx].timestamp)
            ticks.append(ChartAxisConfig.XTick(position: Double(idx), label: chartDurationLabel(secs)))
        }
        axis.xTicks = ticks
        axis.xTickLabelOffset = 4
        axis.xTickFont = .system(size: 8)
        return axis
    }

    private func buildSeries() -> [ChartSeries<ChartPoint>] {
        // Download: negative y below baseline (fills downward)
        let dlPts: [ChartPoint] = samples.enumerated().map { i, s in
            ChartPoint(x: Double(i), y: -s.rateIn)
        }
        let dlStyle = ChartSeriesStyle(
            color: .green, lineWidth: 1.5, areaOpacity: 0.18,
            pointRadius: 0, strokeOpacity: 0.7,
            interpolation: .clampedCubic, baseline: 0
        )

        // Upload: positive y above baseline (fills upward)
        let ulPts: [ChartPoint] = samples.enumerated().map { i, s in
            ChartPoint(x: Double(i), y: s.rateOut)
        }
        let ulStyle = ChartSeriesStyle(
            color: .blue, lineWidth: 1.5, areaOpacity: 0.18,
            pointRadius: 0, strokeOpacity: 0.7,
            interpolation: .clampedCubic, baseline: 0
        )

        return [
            ChartSeries(id: "download", points: dlPts, style: dlStyle),
            ChartSeries(id: "upload", points: ulPts, style: ulStyle),
        ]
    }

    private func rateLabel(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1_024 { return String(format: "%.0f", bytesPerSec) }
        if bytesPerSec < 1_048_576 { return String(format: "%.0fK", bytesPerSec / 1_024) }
        if bytesPerSec < 1_073_741_824 { return String(format: "%.1fM", bytesPerSec / 1_048_576) }
        return String(format: "%.1fG", bytesPerSec / 1_073_741_824)
    }
}
