import Foundation
import WiFiLensCoreRust

/// Adds localized-display identifiers returned by the portable recommendation rules.
enum RecommendationReasonCalculator {
    private static let reasonCodes: [(Int32, RecommendationReason)] = [
        (WIFI_LENS_RECOMMENDATION_REASON_CURRENT_CHANNEL, .currentChannel),
        (WIFI_LENS_RECOMMENDATION_REASON_CURRENTLY_OPTIMAL, .currentlyOptimal),
        (WIFI_LENS_RECOMMENDATION_REASON_CLEAR_SPECTRUM, .clearSpectrum),
        (WIFI_LENS_RECOMMENDATION_REASON_LOW_CONGESTION, .lowCongestion),
        (WIFI_LENS_RECOMMENDATION_REASON_CONGESTED, .congested),
        (WIFI_LENS_RECOMMENDATION_REASON_LOW_OVERLAP, .lowOverlap),
        (WIFI_LENS_RECOMMENDATION_REASON_HIGH_OVERLAP, .highOverlap),
        (WIFI_LENS_RECOMMENDATION_REASON_LOW_INTERFERENCE, .lowInterference),
        (WIFI_LENS_RECOMMENDATION_REASON_HIGH_INTERFERENCE, .highInterference),
        (WIFI_LENS_RECOMMENDATION_REASON_LESS_CROWDED_BAND, .lessCrowdedBand),
        (WIFI_LENS_RECOMMENDATION_REASON_DFS_REQUIRED, .dfsRequired),
        (WIFI_LENS_RECOMMENDATION_REASON_INDOOR_ONLY, .indoorOnly),
        (WIFI_LENS_RECOMMENDATION_REASON_CAC_REQUIRED, .cacRequired),
        (WIFI_LENS_RECOMMENDATION_REASON_RADAR_SENSITIVE, .radarSensitive),
    ]

    static func compute(for recommendations: [ChannelRecommendation]) -> [ChannelRecommendation] {
        var strings: [UInt8] = []
        let inputs = recommendations.map { recommendation in
            let bytes = Array(recommendation.band.utf8)
            let bandOffset = strings.count
            strings.append(contentsOf: bytes)
            var restrictionFlags: UInt32 = 0
            if recommendation.restrictionReasons.contains(where: { $0.code == "DFS" }) {
                restrictionFlags |= WIFI_LENS_RESTRICTION_HAS_DFS
            }
            if recommendation.restrictionReasons.contains(where: { $0.code == "INDOOR_ONLY" }) {
                restrictionFlags |= WIFI_LENS_RESTRICTION_HAS_INDOOR_ONLY
            }
            if recommendation.restrictionReasons.contains(where: { $0.code == "CAC_REQUIRED" }) {
                restrictionFlags |= WIFI_LENS_RESTRICTION_HAS_CAC_REQUIRED
            }
            if recommendation.restrictionReasons.contains(where: { $0.code == "RADAR_SENSITIVE" }) {
                restrictionFlags |= WIFI_LENS_RESTRICTION_HAS_RADAR_SENSITIVE
            }
            return WiFiLensRecommendationReasonInput(
                band_offset: bandOffset,
                band_length: bytes.count,
                channel: Int32(recommendation.channel),
                rf_score: Int32(recommendation.rfScore),
                ap_count: Int32(recommendation.apCount),
                is_current_channel: recommendation.isCurrentChannel ? 1 : 0,
                is_recommended: recommendation.isRecommended ? 1 : 0,
                adjacent_count: Int32(recommendation.adjacentCount),
                interference_score: Int32(recommendation.interferenceScore),
                overlap_level: overlapCode(recommendation.overlapLevel),
                restriction_flags: restrictionFlags
            )
        }
        var outputs = [WiFiLensRecommendationReasonResult](repeating: .init(), count: inputs.count)
        var outputCount = 0
        let status = strings.withUnsafeBufferPointer { stringsBuffer in
            inputs.withUnsafeBufferPointer { inputBuffer in
                outputs.withUnsafeMutableBufferPointer { outputBuffer in
                    wifi_lens_recommendation_reasons(
                        inputBuffer.baseAddress,
                        inputBuffer.count,
                        stringsBuffer.baseAddress,
                        stringsBuffer.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count,
                        &outputCount
                    )
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust recommendation reason calculation returned status \(status)")
            return recommendations
        }

        return zip(recommendations, outputs.prefix(outputCount)).map { recommendation, output in
            var result = recommendation
            result.recommendationReasons = Self.reasonCodes.compactMap { code, reason in
                output.reason_flags & (1 << (code - 1)) == 0 ? nil : reason
            }
            return result
        }
    }

    private static func overlapCode(_ overlap: ChannelQuality.OverlapLevel) -> Int32 {
        switch overlap {
        case .low: 1
        case .moderate: 2
        case .high: 3
        }
    }
}
