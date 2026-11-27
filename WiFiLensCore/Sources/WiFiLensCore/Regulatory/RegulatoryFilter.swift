import Foundation
import WiFiLensCoreRust

/// Swift model adapter for portable regulatory filtering and ranking.
enum RegulatoryFilter {
    struct FilterInput: Sendable {
        let rfResults: [ChannelQuality]
        let inferredRegion: RegionInferenceResult
        let deviceSupportedChannels: Set<String>
        let deviceCapabilities: DevicePHYCapabilities
        let userClassificationOverrides: [String: ChannelRecommendation.Classification]?
    }

    static func apply(to input: FilterInput) -> [ChannelRecommendation] {
        var recommendations = input.rfResults.map { ChannelRecommendation(from: $0) }
        var strings: [UInt8] = []
        let candidates = recommendations.map { recommendation in
            let bytes = Array(recommendation.band.utf8)
            let bandOffset = strings.count
            strings.append(contentsOf: bytes)
            let override = input.userClassificationOverrides?["\(recommendation.band)-\(recommendation.channel)"]
            return WiFiLensRegulatoryFilterCandidate(
                band_offset: bandOffset,
                band_length: bytes.count,
                channel: Int32(recommendation.channel),
                rf_score: Int32(recommendation.rfScore),
                score_selected: recommendation.scoreSelected ? 1 : 0,
                recommendation_score: Int32(recommendation.recommendationScore),
                is_current_channel: recommendation.isCurrentChannel ? 1 : 0,
                show_in_simple_view: recommendation.showInSimpleView ? 1 : 0,
                user_classification_override: override.map(classificationCode) ?? 0
            )
        }
        let supported = DeviceCompatibilityFilter.supportedChannelInputs(from: input.deviceSupportedChannels)
        let config = WiFiLensRegulatoryFilterConfig(
            domain: input.inferredRegion.domain.rustCode,
            confidence: input.inferredRegion.confidence.rustCode,
            flags: input.deviceSupportedChannels.isEmpty ? 0 : WIFI_LENS_REGULATORY_FILTER_HAS_SUPPORTED_CHANNELS,
            capability_flags: input.deviceCapabilities.rustCapabilityFlags
        )
        var outputs = [WiFiLensRegulatoryFilterResult](repeating: .init(), count: candidates.count)
        var outputCount = 0
        let status = strings.withUnsafeBufferPointer { stringsBuffer in
            candidates.withUnsafeBufferPointer { candidatesBuffer in
                supported.withUnsafeBufferPointer { supportedBuffer in
                    outputs.withUnsafeMutableBufferPointer { outputBuffer in
                        withUnsafePointer(to: config) { configPointer in
                            wifi_lens_regulatory_filter(
                                candidatesBuffer.baseAddress,
                                candidatesBuffer.count,
                                stringsBuffer.baseAddress,
                                stringsBuffer.count,
                                supportedBuffer.baseAddress,
                                supportedBuffer.count,
                                configPointer,
                                outputBuffer.baseAddress,
                                outputBuffer.count,
                                &outputCount
                            )
                        }
                    }
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust regulatory filter returned status \(status)")
            for index in recommendations.indices {
                let region = input.inferredRegion.domain
                let recommendation = recommendations[index]
                recommendations[index].classification = .restricted
                recommendations[index].showInSimpleView = false
                recommendations[index].restrictionReasons.append(
                    .init(
                        code: "REGION_UNKNOWN",
                        description: "No regulatory data for region \(region.rawValue) band \(recommendation.band)"
                    )
                )
            }
            return recommendations
        }

        var sorted: [ChannelRecommendation] = []
        sorted.reserveCapacity(outputCount)
        for output in outputs.prefix(outputCount) {
            let originalIndex = output.original_index
            var recommendation = recommendations[originalIndex]
            recommendation.classification = classification(from: output.classification)
            recommendation.deviceCompatible = output.device_compatible != 0
            recommendation.deviceIncompatibilityReason = deviceReason(from: output.device_reason)
            recommendation.showInSimpleView = output.show_in_simple_view != 0

            let flags = output.restriction_reason_flags
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_REGION_UNKNOWN) != 0 {
                recommendation.restrictionReasons.append(
                    .init(
                        code: "REGION_UNKNOWN",
                        description:
                            "No regulatory data for region \(input.inferredRegion.domain.rawValue) band \(recommendation.band)"
                    )
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_REGION_BLOCKED) != 0 {
                recommendation.restrictionReasons.append(
                    .init(
                        code: "REGION_BLOCKED",
                        description:
                            "Channel \(recommendation.channel) not allowed in \(input.inferredRegion.domain.rawValue) (\(recommendation.bandDisplay))"
                    )
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_DFS) != 0 {
                recommendation.restrictionReasons.append(
                    .init(code: "DFS", description: "DFS channel (radar detection required, may switch channels)")
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_RADAR_SENSITIVE) != 0 {
                recommendation.restrictionReasons.append(
                    .init(code: "RADAR_SENSITIVE", description: "Frequently affected by radar events")
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_CAC_REQUIRED) != 0 {
                recommendation.restrictionReasons.append(
                    .init(code: "CAC_REQUIRED", description: "Channel Availability Check required before use")
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_INDOOR_ONLY) != 0 {
                recommendation.restrictionReasons.append(
                    .init(
                        code: "INDOOR_ONLY",
                        description: "Indoor use only (\(input.inferredRegion.domain.rawValue) restriction)"
                    )
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_AFC_REQUIRED) != 0 {
                recommendation.restrictionReasons.append(
                    .init(code: "AFC_REQUIRED", description: "AFC coordination required (not yet supported)")
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_REGION_LOW_CONFIDENCE) != 0 {
                recommendation.restrictionReasons.append(
                    .init(code: "REGION_LOW_CONFIDENCE", description: "Region inference confidence is low")
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_DEVICE_INCOMPATIBLE) != 0 {
                recommendation.restrictionReasons.append(
                    .init(
                        code: "DEVICE_INCOMPATIBLE",
                        description: recommendation.deviceIncompatibilityReason ?? "Device incompatible"
                    )
                )
            }
            if flags & reasonFlag(WIFI_LENS_REGULATORY_REASON_USER_OVERRIDE) != 0 {
                recommendation.restrictionReasons.append(
                    .init(
                        code: "USER_OVERRIDE",
                        description: "Classification manually set to \(recommendation.classification.rawValue)"
                    )
                )
            }
            sorted.append(recommendation)
        }
        return sorted
    }

    private static func classificationCode(_ classification: ChannelRecommendation.Classification) -> Int32 {
        switch classification {
        case .recommended: WIFI_LENS_REGULATORY_CLASSIFICATION_RECOMMENDED
        case .advanced: WIFI_LENS_REGULATORY_CLASSIFICATION_ADVANCED
        case .restricted: WIFI_LENS_REGULATORY_CLASSIFICATION_RESTRICTED
        }
    }

    private static func classification(from code: Int32) -> ChannelRecommendation.Classification {
        switch code {
        case WIFI_LENS_REGULATORY_CLASSIFICATION_RECOMMENDED: .recommended
        case WIFI_LENS_REGULATORY_CLASSIFICATION_ADVANCED: .advanced
        default: .restricted
        }
    }

    private static func reasonFlag(_ code: Int32) -> UInt32 {
        1 << (code - 1)
    }

    private static func deviceReason(from code: Int32) -> String? {
        switch code {
        case WIFI_LENS_DEVICE_REASON_CHANNEL_UNSUPPORTED: "Channel not supported by hardware"
        case WIFI_LENS_DEVICE_REASON_6_GHZ_UNSUPPORTED: "Device does not support 6 GHz"
        case WIFI_LENS_DEVICE_REASON_AFC_UNSUPPORTED: "AFC required (not supported)"
        case WIFI_LENS_DEVICE_REASON_DFS_UNSUPPORTED: "Device does not support DFS channels"
        default: nil
        }
    }
}
