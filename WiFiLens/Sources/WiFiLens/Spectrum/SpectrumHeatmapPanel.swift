import CoreGraphics
import SwiftUI
import WiFiLensCore

/// Aggregate thermal field for one band. X and Y use the same channel and RSSI
/// coordinate spaces as the normal Spectrum chart.
struct SpectrumHeatmapPanel: View {
    let viewModel: ScannerViewModel
    let band: ChannelBand
    @State private var renderCoordinator: SpectrumHeatmapRenderCoordinator

    static let timeAxisLabels: [String] = []

    // Leave enough room for the unit-bearing upper RSSI tick label.
    private static let plotLeadingInset: CGFloat = 56
    private static let plotTopInset: CGFloat = 12
    private static let plotTrailingInset: CGFloat = 8
    private static let plotBottomInset: CGFloat = 28

    init(viewModel: ScannerViewModel, band: ChannelBand) {
        self.viewModel = viewModel
        self.band = band
        _renderCoordinator = State(initialValue: SpectrumHeatmapRenderCoordinator())
    }

    var body: some View {
        let model = viewModel.heatmapModel(for: band)
        Group {
            if Self.shouldShowEmptyState(for: model) {
                emptyState
            } else {
                heatmapCanvas(model)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.aggregateAccessibilityLabel(for: band))
    }

    static func shouldShowEmptyState(for model: SpectrumHeatmapModel) -> Bool {
        model.envelopes.isEmpty
    }

    static func aggregateAccessibilityLabel(for band: ChannelBand) -> String {
        String(
            format: String(
                localized: "spectrum.accessibility.aggregate_heatmap_label",
                comment: "Aggregate Wi-Fi activity heatmap accessibility label with band"
            ),
            band.displayName
        )
    }

    static func rssiReferenceValues(for range: ClosedRange<Double>) -> [Double] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: 10))
    }

    static func rssiAxisLabels(for range: ClosedRange<Double>) -> [String] {
        rssiReferenceValues(for: range).enumerated().map { index, value in
            index == rssiReferenceValues(for: range).count - 1 ? "\(Int(value)) dBm" : "\(Int(value))"
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(String(localized: "spectrum.heatmap.empty", comment: "Placeholder when the current scan has no heatmap envelopes"))
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
        }
        .frame(minHeight: 150)
    }

    var heatmapToolbarContent: some View {
        HStack(spacing: 6) {
            Text(String(localized: "spectrum.heatmap.legend.low", comment: "Low end of the heatmap intensity legend"))
                .font(.caption2)
                .foregroundColor(.secondary)
            SpectrumLegendBar()
                .frame(width: 90, height: 8)
            Text(String(localized: "spectrum.heatmap.legend.high", comment: "High end of the heatmap intensity legend"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func heatmapCanvas(_ model: SpectrumHeatmapModel) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let domain = SpectrumHeatmapLayout.channelDomain(
                channels: model.channels,
                band: band
            ) ?? SpectrumHeatmapChannelDomain(
                minChannelCoordinate: band == .band24GHz ? -1 : 1,
                maxChannelCoordinate: Double(band.maxChannel)
            )
            let rssiRange = SpectrumHeatmapLayout.rssiRange(
                for: model.envelopes.map(\.peakRSSI)
            )
            let plotRect = Self.plotRect(in: size)
            let resolution = Self.rasterResolution(for: plotRect.size)
            let key = SpectrumHeatmapRenderKey(
                model: model,
                domain: domain,
                rssiRange: rssiRange,
                resolution: resolution
            )

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0.008, green: 0.014, blue: 0.038))
                if let result = renderCoordinator.result {
                    rasterLayer(result.image, in: plotRect, opacity: 0.42)
                        .blur(radius: 8)
                    rasterLayer(result.image, in: plotRect, opacity: 0.96)
                }
                axisLayer(model: model, domain: domain, rssiRange: rssiRange, plotRect: plotRect)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .task(id: key) {
                renderCoordinator.request(key)
            }
            .onDisappear {
                renderCoordinator.cancel()
            }
        }
        .frame(minHeight: 160, idealHeight: 190, maxHeight: 240)
    }

    private func rasterLayer(
        _ image: CGImage,
        in plotRect: CGRect,
        opacity: Double
    ) -> some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .interpolation(.high)
            .opacity(opacity)
        .frame(width: plotRect.width, height: plotRect.height)
        .position(x: plotRect.midX, y: plotRect.midY)
    }

    private func axisLayer(
        model: SpectrumHeatmapModel,
        domain: SpectrumHeatmapChannelDomain,
        rssiRange: ClosedRange<Double>,
        plotRect: CGRect
    ) -> some View {
        Canvas { context, _ in
            let labelColor = Color.white.opacity(0.58)
            let rssiValues = Self.rssiReferenceValues(for: rssiRange)
            let labels = Self.rssiAxisLabels(for: rssiRange)
            for (index, rssi) in rssiValues.enumerated() {
                guard let y = SpectrumHeatmapLayout.yPosition(
                    forRSSI: rssi,
                    in: plotRect,
                    rssiRange: rssiRange
                ) else { continue }
                let label = Text(labels[index])
                    .font(.caption2)
                    .foregroundColor(labelColor)
                context.draw(
                    context.resolve(label),
                    at: CGPoint(x: plotRect.minX - 8, y: y),
                    anchor: .trailing
                )
            }

            let ticks = SpectrumHeatmapLayout.channelTicks(
                channels: model.channels,
                band: band,
                in: plotRect,
                maximumCount: 10
            )
            for tick in ticks {
                let label = Text("\(tick.channel)")
                    .font(.caption2)
                    .foregroundColor(labelColor)
                context.draw(
                    context.resolve(label),
                    at: CGPoint(x: tick.x, y: plotRect.maxY + 8),
                    anchor: .top
                )
            }
        }
    }

    private static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: plotLeadingInset,
            y: plotTopInset,
            width: max(1, size.width - plotLeadingInset - plotTrailingInset),
            height: max(1, size.height - plotTopInset - plotBottomInset)
        )
    }

    static func rasterResolution(for _: CGSize) -> SpectrumHeatmapResolution {
        SpectrumHeatmapResolution.standard
    }
}

/// Compact toolbar legend matching the thermal colormap.
struct SpectrumLegendBar: View {
    var body: some View {
        Canvas { context, size in
            let strips = 64
            for index in 0..<strips {
                let intensity = Double(index) / Double(strips - 1)
                let rect = CGRect(
                    x: size.width * CGFloat(index) / CGFloat(strips),
                    y: 0,
                    width: size.width / CGFloat(strips) + 0.5,
                    height: size.height
                )
                context.fill(
                    Path(rect),
                    with: .color(SpectrumHeatmapColor.color(forIntensity: intensity))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityLabel(String(localized: "spectrum.heatmap.legend.gradient", comment: "Thermal color gradient legend"))
    }
}
