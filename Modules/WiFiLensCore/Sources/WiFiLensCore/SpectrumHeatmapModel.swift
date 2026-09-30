import ChartLens

/// An anonymous spectrum envelope contributed by one network in the current
/// scan. It intentionally contains no access-point identity or time data.
public struct SpectrumHeatmapEnvelope: Hashable, Sendable {
    public let leftX: Double
    public let rightX: Double
    public let peakRSSI: Double
    public let baselineRSSI: Double

    public var gaussian: GaussianEnvelope {
        SpectrumEnvelopeGeometry(
            leftX: leftX,
            rightX: rightX,
            peakRSSI: peakRSSI,
            baselineRSSI: baselineRSSI
        ).gaussian
    }
}

/// The current-scan aggregate view for one band. It deliberately contains no
/// scan history, timestamps, frames, or access-point identity.
public struct SpectrumHeatmapModel: Hashable, Sendable {
    public let band: ChannelBand
    public let channels: [Int]
    public let envelopes: [SpectrumHeatmapEnvelope]

    public init(band: ChannelBand, channels: [Int], envelopes: [SpectrumHeatmapEnvelope]) {
        self.band = band
        self.channels = channels
        self.envelopes = envelopes
    }
}
