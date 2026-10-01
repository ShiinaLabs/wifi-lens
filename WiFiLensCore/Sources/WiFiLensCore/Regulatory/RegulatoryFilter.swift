import Foundation

// MARK: - Regulatory Filter Pipeline

/// The main regulatory-aware filtering pipeline.
/// Takes raw RF scoring results and applies region rules + device compatibility
/// checks to produce classified channel recommendations.
///
/// RF scoring and regulatory filtering are completely decoupled —
/// `ChannelQualityCalculator` is never modified.
enum RegulatoryFilter {

    struct FilterInput: Sendable {
        let rfResults: [ChannelQuality]
        let inferredRegion: RegionInferenceResult
        let deviceSupportedChannels: Set<String>    // "bandRaw-channel" keys
        let deviceCapabilities: DevicePHYCapabilities
        let userClassificationOverrides: [String: ChannelRecommendation.Classification]?  // keyed by "band-channel"
    }

    // MARK: - Pipeline Entry Point

    static func apply(to input: FilterInput) -> [ChannelRecommendation] {
        // Step 1: Wrap each ChannelQuality in a ChannelRecommendation
        var recommendations = input.rfResults.map { ChannelRecommendation(from: $0) }

        // Step 2: Apply regulatory rules
        let region = input.inferredRegion.domain
        let rules = region != .unknown ? RegulatoryDatabase.rules[region] : nil

        for i in recommendations.indices {
            let rec = recommendations[i]

            // Look up band rules
            guard let bandRules = rules?[rec.band] else {
                // No rules for this band in this region → mark restricted
                recommendations[i].classification = .restricted
                recommendations[i].restrictionReasons.append(
                    .init(code: "REGION_UNKNOWN", description: "No regulatory data for region \(region.rawValue) band \(rec.band)")
                )
                continue
            }

            // Check if channel is allowed
            guard bandRules.allowedChannels.contains(rec.channel) else {
                recommendations[i].classification = .restricted
                recommendations[i].restrictionReasons.append(
                    .init(code: "REGION_BLOCKED", description: "Channel \(rec.channel) not allowed in \(region.rawValue) (\(rec.bandDisplay))")
                )
                continue
            }

            // Check channel metadata for caveats
            if let meta = bandRules.channelMeta[rec.channel] {
                // DFS channels → advanced
                if meta.isDFS {
                    recommendations[i].classification = .advanced
                    recommendations[i].restrictionReasons.append(
                        .init(code: "DFS", description: "DFS channel (radar detection required, may switch channels)")
                    )
                }

                // Radar-sensitive subcategory
                if meta.isRadarSensitive {
                    recommendations[i].restrictionReasons.append(
                        .init(code: "RADAR_SENSITIVE", description: "Frequently affected by radar events")
                    )
                }

                // CAC required
                if meta.requiresCAC {
                    recommendations[i].restrictionReasons.append(
                        .init(code: "CAC_REQUIRED", description: "Channel Availability Check required before use")
                    )
                }

                // Indoor-only
                if meta.isIndoorOnly {
                    recommendations[i].classification = min(recommendations[i].classification, .advanced)
                    recommendations[i].restrictionReasons.append(
                        .init(code: "INDOOR_ONLY", description: "Indoor use only (\(region.rawValue) restriction)")
                    )
                }

                // AFC-required (6 GHz standard power)
                if meta.requiresAFC {
                    recommendations[i].classification = .restricted
                    recommendations[i].restrictionReasons.append(
                        .init(code: "AFC_REQUIRED", description: "AFC coordination required (not yet supported)")
                    )
                }
            }

            // Low-confidence region inference → note it, and downgrade if currently recommended
            if input.inferredRegion.confidence == .low {
                recommendations[i].restrictionReasons.append(
                    .init(code: "REGION_LOW_CONFIDENCE", description: "Region inference confidence is low")
                )
                if recommendations[i].classification == .recommended {
                    recommendations[i].classification = .advanced
                }
            }
        }

        // Step 3: Device compatibility filter
        for i in recommendations.indices {
            let rec = recommendations[i]
            let meta = rules?[rec.band]?.channelMeta[rec.channel]

            let compatResult = DeviceCompatibilityFilter.check(
                channel: rec.channel,
                band: rec.band,
                capabilities: input.deviceCapabilities,
                supportedChannels: input.deviceSupportedChannels,
                channelMeta: meta
            )

            if !compatResult.isCompatible {
                recommendations[i].deviceCompatible = false
                recommendations[i].deviceIncompatibilityReason = compatResult.reason
                recommendations[i].restrictionReasons.append(
                    .init(code: "DEVICE_INCOMPATIBLE", description: compatResult.reason ?? "Device incompatible")
                )
                if recommendations[i].classification != .restricted {
                    recommendations[i].classification = .restricted
                }
            }
        }

        // Step 4: Apply user classification overrides
        if let overrides = input.userClassificationOverrides {
            for i in recommendations.indices {
                let key = "\(recommendations[i].band)-\(recommendations[i].channel)"
                if let override = overrides[key] {
                    recommendations[i].classification = override
                    recommendations[i].restrictionReasons.append(
                        .init(code: "USER_OVERRIDE", description: "Classification manually set to \(override.rawValue)")
                    )
                }
            }
        }

        // Step 5: Sort — current channel first, then by classification tier,
        // then counterfactual-selected channels, then recommendation score, then observed RF score.
        recommendations.sort { a, b in
            // Current channel always first
            if a.isCurrentChannel != b.isCurrentChannel {
                return a.isCurrentChannel
            }
            // Classification tier
            if a.classification.order != b.classification.order {
                return a.classification.order > b.classification.order
            }
            // Counterfactual recommendation
            if a.scoreSelected != b.scoreSelected {
                return a.scoreSelected
            }
            // Counterfactual recommendation score descending
            if a.recommendationScore != b.recommendationScore {
                return a.recommendationScore > b.recommendationScore
            }
            // RF score descending (fallback)
            if a.rfScore != b.rfScore {
                return a.rfScore > b.rfScore
            }
            // Band, then channel
            if a.band != b.band {
                return a.band < b.band
            }
            return a.channel < b.channel
        }

        // Update showInSimpleView: restricted channels hidden by default
        for i in recommendations.indices {
            if recommendations[i].classification == .restricted {
                recommendations[i].showInSimpleView = false
            }
        }

        return recommendations
    }
}

// MARK: - Comparable helper for downgrade logic

private func min(_ a: ChannelRecommendation.Classification, _ b: ChannelRecommendation.Classification) -> ChannelRecommendation.Classification {
    a.order < b.order ? a : b
}
