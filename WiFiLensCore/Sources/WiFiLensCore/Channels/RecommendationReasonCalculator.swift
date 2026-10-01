import Foundation

/// Enriches ChannelRecommendations with user-facing RecommendationReason values.
/// Runs after the regulatory pipeline — reads RF data and existing restrictionReasons
/// codes, then emits structured reason identifiers.
enum RecommendationReasonCalculator {

    /// Compute recommendation reasons for every channel in the list.
    /// Reasons are deterministic and idempotent — safe to call on every scan cycle.
    static func compute(for recommendations: [ChannelRecommendation]) -> [ChannelRecommendation] {
        let bandAPCounts = bandTotalAPCounts(from: recommendations)

        return recommendations.map { ch in
            var result = ch
            var reasons: [RecommendationReason] = []

            // ── Status ──
            if ch.isCurrentChannel {
                reasons.append(.currentChannel)
            }
            if ch.isCurrentChannel && ch.rfScore >= 90 {
                reasons.append(.currentlyOptimal)
            }

            // ── Congestion family (pick strongest) ──
            switch ch.apCount {
            case 0:
                reasons.append(.clearSpectrum)
            case 1...2:
                reasons.append(.lowCongestion)
            case 6... where !ch.isRecommended:
                reasons.append(.congested)
            default:
                break
            }

            // ── Overlap family (pick strongest) ──
            switch ch.overlapLevel {
            case .low where ch.adjacentCount <= 1:
                reasons.append(.lowOverlap)
            case .high where !ch.isRecommended:
                reasons.append(.highOverlap)
            default:
                break
            }

            // ── Interference family (pick strongest) ──
            switch ch.interferenceScore {
            case ...15:
                reasons.append(.lowInterference)
            case 40... where !ch.isRecommended:
                reasons.append(.highInterference)
            default:
                break
            }

            // ── Band preference ──
            if ch.band != "24",
               let band24Count = bandAPCounts["24"],
               let bandCount = bandAPCounts[ch.band],
               band24Count > bandCount {
                reasons.append(.lessCrowdedBand)
            }

            // ── Regulatory caveats (from existing restrictionReasons codes) ──
            for restriction in ch.restrictionReasons {
                switch restriction.code {
                case "DFS":             reasons.append(.dfsRequired)
                case "INDOOR_ONLY":     reasons.append(.indoorOnly)
                case "CAC_REQUIRED":    reasons.append(.cacRequired)
                case "RADAR_SENSITIVE": reasons.append(.radarSensitive)
                default: break
                }
            }

            // ── Deduplicate, preserving first-insertion order ──
            var seen = Set<RecommendationReason>()
            result.recommendationReasons = reasons.filter { seen.insert($0).inserted }
            return result
        }
    }

    private static func bandTotalAPCounts(from recommendations: [ChannelRecommendation]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for ch in recommendations {
            counts[ch.band, default: 0] += ch.apCount
        }
        return counts
    }
}
