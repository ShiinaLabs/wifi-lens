import CoreGraphics

/// The same channel-coordinate domain used by `WiFiBandChart` and ChartLens.
/// Regulatory channel lists are used for labels and scanner input, but never
/// to compress or clip the numeric chart coordinate space.
public struct SpectrumHeatmapChannelDomain: Hashable, Sendable {
    public let minChannelCoordinate: Double
    public let maxChannelCoordinate: Double

    public var span: Double { maxChannelCoordinate - minChannelCoordinate }

    public init(minChannelCoordinate: Double, maxChannelCoordinate: Double) {
        self.minChannelCoordinate = minChannelCoordinate
        self.maxChannelCoordinate = maxChannelCoordinate
    }
}

public enum SpectrumHeatmapLayout {
    public static let fixedRSSIRange = (-100.0)...(-30.0)

    public static func channelDomain(channels: [Int], band: ChannelBand) -> SpectrumHeatmapChannelDomain? {
        guard !channels.isEmpty else { return nil }
        let minChannel = band == .band24GHz ? -1.0 : 1.0
        return SpectrumHeatmapChannelDomain(
            minChannelCoordinate: minChannel,
            maxChannelCoordinate: Double(band.maxChannel)
        )
    }

    public static func xPosition(
        forChannelCoordinate channel: Double,
        domain: SpectrumHeatmapChannelDomain,
        in rect: CGRect
    ) -> CGFloat? {
        guard rect.width > 0, domain.span > 0, channel.isFinite,
              channel >= domain.minChannelCoordinate,
              channel <= domain.maxChannelCoordinate else { return nil }
        return rect.minX + CGFloat((channel - domain.minChannelCoordinate) / domain.span) * rect.width
    }

    public static func channelCoordinate(
        forX x: CGFloat,
        domain: SpectrumHeatmapChannelDomain,
        in rect: CGRect
    ) -> Double? {
        guard rect.width > 0, domain.span > 0,
              x >= rect.minX, x <= rect.maxX else { return nil }
        return domain.minChannelCoordinate + Double((x - rect.minX) / rect.width) * domain.span
    }

    public static func yPosition(forRSSI rssi: Double, in rect: CGRect, rssiRange: ClosedRange<Double>) -> CGFloat? {
        guard rect.height > 0, rssi.isFinite, rssiRange.lowerBound < rssiRange.upperBound else { return nil }
        let clamped = min(rssiRange.upperBound, max(rssiRange.lowerBound, rssi))
        let normalized = (clamped - rssiRange.lowerBound) / (rssiRange.upperBound - rssiRange.lowerBound)
        return rect.maxY - CGFloat(normalized) * rect.height
    }

    public static func rssi(forY y: CGFloat, in rect: CGRect, rssiRange: ClosedRange<Double>) -> Double? {
        guard rect.height > 0, y >= rect.minY, y <= rect.maxY,
              rssiRange.lowerBound < rssiRange.upperBound else { return nil }
        let normalized = Double((rect.maxY - y) / rect.height)
        return rssiRange.lowerBound + normalized * (rssiRange.upperBound - rssiRange.lowerBound)
    }

    /// Matches `BandChartViewModel`'s rounded upper Y bound for the strongest
    /// currently displayed spectrum series.
    public static func rssiRange(for peakRSSIs: [Double]) -> ClosedRange<Double> {
        let lower = fixedRSSIRange.lowerBound
        let strongest = peakRSSIs.max() ?? fixedRSSIRange.upperBound
        let roundedUpper = min(0, ceil(strongest / 10.0) * 10.0)
        return lower...max(lower + 10, roundedUpper)
    }

    public static func channelTicks(
        channels: [Int],
        band: ChannelBand,
        in rect: CGRect,
        maximumCount: Int = 10
    ) -> [(channel: Int, x: CGFloat)] {
        guard let domain = channelDomain(channels: channels, band: band) else { return [] }
        let xMin = domain.minChannelCoordinate
        let xMax = domain.maxChannelCoordinate
        let desiredTicks = max(1, min(band.maxChannel - Int(xMin), 15))
        let step = max(1, Int((xMax - xMin) / Double(desiredTicks)))
        let values = Array(stride(from: Int(xMin), through: Int(xMax), by: step))
            .filter { $0 >= 1 }
        let count = min(10, max(0, maximumCount), values.count)
        let indexes = (0..<count).map { offset in
            Int((Double(offset) * Double(values.count - 1) / Double(max(1, count - 1))).rounded())
        }
        return indexes.compactMap { index in
            let channel = values[index]
            guard let x = xPosition(forChannelCoordinate: Double(channel), domain: domain, in: rect) else { return nil }
            return (channel: channel, x: x)
        }
    }
}
