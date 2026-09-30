import Foundation

/// Stable, user-facing identifier for a channel recommendation reason.
/// The algorithm emits these; the UI maps them to localized strings.
/// Organized into mutual-exclusion families to prevent contradiction on the same channel.
enum RecommendationReason: String, CaseIterable, Sendable {
    // MARK: - Congestion family (mutually exclusive, strongest wins)

    /// No APs detected on this channel
    case clearSpectrum
    /// 1–2 APs on or near this channel
    case lowCongestion
    /// 6+ APs — used for current-channel diagnosis
    case congested

    // MARK: - Overlap family (mutually exclusive)

    /// Minimal adjacent-channel overlap
    case lowOverlap
    /// High adjacent-channel overlap
    case highOverlap

    // MARK: - Interference family (mutually exclusive)

    /// Interference score ≤ 15
    case lowInterference
    /// Interference score ≥ 40
    case highInterference

    // MARK: - Band preference (independent)

    /// 5/6 GHz when 2.4 GHz has more APs
    case lessCrowdedBand

    // MARK: - Regulatory caveats (independent, coexist with positive reasons)

    case dfsRequired
    case indoorOnly
    case cacRequired
    case radarSensitive

    // MARK: - Status (independent)

    case currentChannel
    case currentlyOptimal

    // MARK: - Display

    var localizationKey: String {
        "channels.reason.\(keySuffix)"
    }

    /// Stable string for the enum case, usable as a localization-key suffix.
    private var keySuffix: String {
        switch self {
        case .clearSpectrum:    "clear_spectrum"
        case .lowCongestion:    "low_congestion"
        case .congested:        "congested"
        case .lowOverlap:       "low_overlap"
        case .highOverlap:      "high_overlap"
        case .lowInterference:  "low_interference"
        case .highInterference: "high_interference"
        case .lessCrowdedBand:  "less_crowded_band"
        case .dfsRequired:      "dfs_required"
        case .indoorOnly:       "indoor_only"
        case .cacRequired:      "cac_required"
        case .radarSensitive:   "radar_sensitive"
        case .currentChannel:   "current_channel"
        case .currentlyOptimal: "currently_optimal"
        }
    }

    var displayText: String {
        NSLocalizedString(localizationKey, comment: "Recommendation reason")
    }
}
