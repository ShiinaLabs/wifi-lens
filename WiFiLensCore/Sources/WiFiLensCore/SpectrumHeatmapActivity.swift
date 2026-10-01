import ChartLens
import Foundation

/// Converts current-scan networks into anonymous frequency envelopes.
enum SpectrumHeatmapActivity {
    static func envelope(
        for network: WiFiNetwork,
        band: ChannelBand
    ) -> SpectrumHeatmapEnvelope? {
        envelope(for: network, rssi: Double(network.rssi), band: band)
    }

    static func envelope(
        for network: WiFiNetwork,
        rssi: Double,
        band: ChannelBand
    ) -> SpectrumHeatmapEnvelope? {
        guard network.channel.band == band,
              (1...band.maxChannel).contains(network.channel.channelNumber),
              rssi.isFinite,
              SpectrumHeatmapLayout.fixedRSSIRange.contains(rssi),
              network.channel.channelWidthMHz > 0 else { return nil }

        let block = ChannelSpanCalculator.channelBlock(
            primaryChannel: network.channel.channelNumber,
            widthMHz: network.channel.channelWidthMHz,
            band: band,
            spanDirection: network.channel.spanDirection
        )
        guard block.right > block.left else { return nil }

        return SpectrumHeatmapEnvelope(
            leftX: Double(block.left),
            rightX: Double(block.right),
            peakRSSI: rssi,
            baselineRSSI: Double(Constants.rssiNoiseFloor)
        )
    }

    /// Returns the shared ChartLens sampler for a current-scan envelope.
    /// This preserves the same Gaussian mathematics as the Spectrum chart.
    static func gaussianEnvelope(for envelope: SpectrumHeatmapEnvelope) -> GaussianEnvelope {
        envelope.gaussian
    }

}
