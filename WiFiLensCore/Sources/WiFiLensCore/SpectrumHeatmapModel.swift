import ChartLens

/// An anonymous spectrum envelope contributed by one network in the current
/// scan. It intentionally contains no access-point identity or time data.
struct SpectrumHeatmapEnvelope: Hashable, Sendable {
    let leftX: Double
    let rightX: Double
    let peakRSSI: Double
    let baselineRSSI: Double

    var gaussian: GaussianEnvelope {
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
struct SpectrumHeatmapModel: Hashable, Sendable {
    let band: ChannelBand
    let channels: [Int]
    let envelopes: [SpectrumHeatmapEnvelope]

    init(band: ChannelBand, channels: [Int], envelopes: [SpectrumHeatmapEnvelope]) {
        self.band = band
        self.channels = channels
        self.envelopes = envelopes
    }
}
