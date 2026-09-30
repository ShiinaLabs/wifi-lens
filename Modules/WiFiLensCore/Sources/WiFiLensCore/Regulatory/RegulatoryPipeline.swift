import Foundation
import Observation

/// Extracted regulatory pipeline that handles region inference and channel
/// recommendation computation, taking pressure off ScannerViewModel.
@MainActor
@Observable
public final class RegulatoryPipeline {
    public init() {}
    public var inferredRegion: RegionInferenceResult?
    public var userRegionOverride: RegulatoryDomain?
    public var deviceSupportedChannels = Set<String>()
    public var deviceCachedCapabilities: DevicePHYCapabilities = .default
    public var cachedSupportedChannelsRaw: [(Int, Int)] = []

    public func computeRecommendations(
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
