import Foundation
import WiFiLensCore

public enum ChannelRecommendationEngine {
    public static func recommend(
        channelAnalysis: [ChannelQuality],
        inferredRegion: RegionInferenceResult,
        deviceSupportedChannels: Set<String>,
        deviceCapabilities: DevicePHYCapabilities
    ) -> [ChannelRecommendation] {
        let input = RegulatoryFilter.FilterInput(
            rfResults: channelAnalysis,
            inferredRegion: inferredRegion,
            deviceSupportedChannels: deviceSupportedChannels,
            deviceCapabilities: deviceCapabilities,
            userClassificationOverrides: nil
        )
        let filtered = RegulatoryFilter.apply(to: input)
        return RecommendationReasonCalculator.compute(for: filtered)
    }
}
