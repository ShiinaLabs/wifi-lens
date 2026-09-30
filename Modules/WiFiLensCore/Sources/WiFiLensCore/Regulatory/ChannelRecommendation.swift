import Foundation

/// The output of the regulatory-aware channel recommendation pipeline.
/// Wraps raw RF scoring with all downstream filtering results.
/// Preserves the original RF score, quality level, and AP counts verbatim.
public struct ChannelRecommendation: Identifiable, Sendable {
    // MARK: - Original RF fields (preserved from ChannelQuality)

    public let channel: Int
    public let band: String
    public let bandDisplay: String
    public let rfScore: Int
    public let rfLevel: ChannelQuality.QualityLevel
    public let apCount: Int
    public let coChannelCount: Int
    public let adjacentCount: Int
    public let interferenceScore: Int
    public let overlapLevel: ChannelQuality.OverlapLevel
    public let strongestNeighborRSSI: Int
    public var isCurrentChannel: Bool = false
    public var showInSimpleView: Bool = true

    /// Recommendation selected by counterfactual scoring before regulatory filtering.
    /// Distinct from `classification` — a channel can be score-selected but
    /// still be downgraded by regulatory or device constraints.
    public var scoreSelected: Bool = false

    /// Counterfactual score after excluding the current target AP from interference.
    public var recommendationScore: Int = 0
    public var recommendationLevel: ChannelQuality.QualityLevel = .excellent
    public var recommendationConfidence: ChannelQuality.RecommendationConfidence = .unknown
    public var recommendationState: ChannelQuality.RecommendationState = .targetUnknown

    public var id: String { "\(band)-\(channel)" }

    // MARK: - Classification

    public enum Classification: String, Sendable, CaseIterable {
        case recommended
        case advanced
        case restricted

        public var displayName: String {
            switch self {
            case .recommended: String(localized: "channels.classification.recommended", comment: "Recommended channel classification")
            case .advanced:    String(localized: "channels.classification.advanced", comment: "Advanced channel classification")
            case .restricted:  String(localized: "channels.classification.restricted", comment: "Restricted channel classification")
            }
        }

        public var order: Int {
            switch self {
            case .recommended: 2
            case .advanced:    1
            case .restricted:  0
            }
        }
    }

    public var classification: Classification = .recommended

    // MARK: - Restriction Reasons

    public struct RestrictionReason: Identifiable, Sendable {
        public let id = UUID()
        public let code: String
        public let description: String
    }

    public var restrictionReasons: [RestrictionReason] = []

    // MARK: - Recommendation Reasons (user-facing)

    public var recommendationReasons: [RecommendationReason] = []

    // MARK: - Device Compatibility

    public var deviceCompatible: Bool = true
    public var deviceIncompatibilityReason: String?

    // MARK: - Legacy compatibility

    /// Final recommendation after counterfactual selection and downstream regulatory filtering.
    public var isRecommended: Bool { scoreSelected && classification == .recommended }

    // MARK: - Initializers

    /// Create from a raw `ChannelQuality` result (pure RF, no filtering yet).
    public init(from rf: ChannelQuality) {
        self.channel = rf.channel
        self.band = rf.band
        self.bandDisplay = rf.bandDisplay
        self.rfScore = rf.qualityScore
        self.rfLevel = rf.qualityLevel
        self.apCount = rf.apCount
        self.coChannelCount = rf.coChannelCount
        self.adjacentCount = rf.adjacentCount
        self.interferenceScore = rf.interferenceScore
        self.overlapLevel = rf.overlapLevel
        self.strongestNeighborRSSI = rf.strongestNeighborRSSI
        self.isCurrentChannel = rf.isCurrentChannel
        self.showInSimpleView = rf.showInSimpleView
        self.scoreSelected = rf.isRecommended
        self.recommendationScore = rf.recommendationScore
        self.recommendationLevel = rf.recommendationLevel
        self.recommendationConfidence = rf.recommendationConfidence
        self.recommendationState = rf.recommendationState
    }
}

public enum ChannelRecommendationAvailability: String, Sendable {
    case available
    case currentGoodEnough
    case targetUnknown
    case regulatoryFiltered
    case noSignificantImprovement
    case noData

    public static func from(_ recommendations: [ChannelRecommendation]) -> Self {
        guard !recommendations.isEmpty else { return .noData }
        if recommendations.contains(where: { $0.isCurrentChannel && $0.recommendationState == .currentGoodEnough }) {
            return .currentGoodEnough
        }
        if recommendations.contains(where: { $0.isCurrentChannel && $0.recommendationConfidence == .unknown }) {
            return .targetUnknown
        }
        if recommendations.contains(where: \.isRecommended) { return .available }
        if recommendations.contains(where: { $0.scoreSelected && $0.classification != .recommended }) {
            return .regulatoryFiltered
        }
        return .noSignificantImprovement
    }

    public var icon: String {
        switch self {
        case .available: "lightbulb.fill"
        case .currentGoodEnough: "checkmark.circle.fill"
        case .targetUnknown: "questionmark.circle.fill"
        case .regulatoryFiltered: "exclamationmark.triangle.fill"
        case .noSignificantImprovement: "equal.circle.fill"
        case .noData: "antenna.radiowaves.left.and.right.slash"
        }
    }

    public var title: String {
        switch self {
        case .available:
            String(localized: "channels.recommendation_status.available.title", comment: "Title when channel recommendations are available")
        case .currentGoodEnough:
            String(localized: "channels.recommendation_status.current_good_enough.title", comment: "Title when current channel is already good enough")
        case .targetUnknown:
            String(localized: "channels.recommendation_status.target_unknown.title", comment: "Title when current AP identity is unavailable")
        case .regulatoryFiltered:
            String(localized: "channels.recommendation_status.regulatory_filtered.title", comment: "Title when candidate channels were filtered")
        case .noSignificantImprovement:
            String(localized: "channels.recommendation_status.no_significant_improvement.title", comment: "Title when no channel is meaningfully better")
        case .noData:
            String(localized: "channels.recommendation_status.no_data.title", comment: "Title when no channel data is available")
        }
    }

    public var message: String {
        switch self {
        case .available:
            String(localized: "channels.recommendation_status.available.message", comment: "Message when channel recommendations are available")
        case .currentGoodEnough:
            String(localized: "channels.recommendation_status.current_good_enough.message", comment: "Message when current channel is already good enough")
        case .targetUnknown:
            String(localized: "channels.recommendation_status.target_unknown.message", comment: "Message when current AP identity is unavailable")
        case .regulatoryFiltered:
            String(localized: "channels.recommendation_status.regulatory_filtered.message", comment: "Message when candidate channels were filtered")
        case .noSignificantImprovement:
            String(localized: "channels.recommendation_status.no_significant_improvement.message", comment: "Message when no channel is meaningfully better")
        case .noData:
            String(localized: "channels.recommendation_status.no_data.message", comment: "Message when no channel data is available")
        }
    }
}
