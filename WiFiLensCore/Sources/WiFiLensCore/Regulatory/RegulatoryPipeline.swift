import Foundation
import Observation

/// Extracted regulatory pipeline that handles region inference and channel
/// recommendation computation, taking pressure off ScannerViewModel.
@MainActor
@Observable
final class RegulatoryPipeline {
    init() {}
    var inferredRegion: RegionInferenceResult?
    var userRegionOverride: RegulatoryDomain?
    var deviceSupportedChannels = Set<String>()
    var deviceCachedCapabilities: DevicePHYCapabilities = .default
    var cachedSupportedChannelsRaw: [(Int, Int)] = []

    func computeRecommendations(
        from channelQualities: [ChannelQuality],
        apCountryCodes: [String],
        userDefaultsOverride: RegulatoryDomain?
    ) -> [ChannelRecommendation] {
        let region = RegionInferenceEngine.infer(
            systemLocale: .current,
            supportedChannels: cachedSupportedChannelsRaw,
            apCountryCodes: apCountryCodes,
            userOverride: userRegionOverride ?? userDefaultsOverride
        )
        inferredRegion = region

        let input = RegulatoryFilter.FilterInput(
            rfResults: channelQualities,
            inferredRegion: region,
            deviceSupportedChannels: deviceSupportedChannels,
            deviceCapabilities: deviceCachedCapabilities,
            userClassificationOverrides: nil
        )
        return RegulatoryFilter.apply(to: input)
    }
}
