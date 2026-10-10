import Foundation

public struct WiFiObservation: Equatable, Sendable {
    /// Stable identity of this immutable accepted observation value. It is
    /// independent from its scan cycle and is preserved by value copies.
    public let sourceObservationID: UUID
    public let timestamp: Date
    /// Source identity for this complete observation cycle. It is not a scan
    /// success marker; inspect `environmentSnapshot.error` for that outcome.
    public let sourceCycleID: UUID?
    public let currentStatus: WiFiCurrentStatus?
    let environmentSnapshot: WiFiEnvironmentSnapshot?
    public let gatewayLatency: GatewayLatencyResult?
    let quality: WiFiQualityResult?
    let channelAnalysis: [ChannelQuality]?
    let channelRecommendation: [ChannelRecommendation]?
    let diagnosis: DiagnosticResult?
    let errors: [WiFiObservationError]

    init(
        sourceObservationID: UUID = UUID(),
        timestamp: Date = Date(),
        sourceCycleID: UUID? = nil,
        currentStatus: WiFiCurrentStatus? = nil,
        environmentSnapshot: WiFiEnvironmentSnapshot? = nil,
        gatewayLatency: GatewayLatencyResult? = nil,
        quality: WiFiQualityResult? = nil,
        channelAnalysis: [ChannelQuality]? = nil,
        channelRecommendation: [ChannelRecommendation]? = nil,
        diagnosis: DiagnosticResult? = nil,
        errors: [WiFiObservationError] = []
    ) {
        self.sourceObservationID = sourceObservationID
        self.timestamp = timestamp
        self.sourceCycleID = sourceCycleID ?? environmentSnapshot?.sourceCycleID ?? currentStatus?.interfaceSnapshotCycleID
        self.currentStatus = currentStatus
        self.environmentSnapshot = environmentSnapshot
        self.gatewayLatency = gatewayLatency
        self.quality = quality
        self.channelAnalysis = channelAnalysis
        self.channelRecommendation = channelRecommendation
        self.diagnosis = diagnosis
        self.errors = errors
    }

    public static func == (lhs: WiFiObservation, rhs: WiFiObservation) -> Bool {
        lhs.sourceObservationID == rhs.sourceObservationID &&
        lhs.hasSameContent(as: rhs)
    }

    /// Compares observation payload independently from source identity. Runtime
    /// admission uses this to detect accidental reuse of an identity.
    func hasSameContent(as other: WiFiObservation) -> Bool {
        timestamp == other.timestamp &&
        sourceCycleID == other.sourceCycleID &&
        currentStatus == other.currentStatus &&
        environmentSnapshot == other.environmentSnapshot &&
        gatewayLatency == other.gatewayLatency &&
        quality == other.quality &&
        diagnosis == other.diagnosis &&
        errors == other.errors &&
        Self.channelQualityFingerprint(channelAnalysis) == Self.channelQualityFingerprint(other.channelAnalysis) &&
        Self.channelRecommendationFingerprint(channelRecommendation) == Self.channelRecommendationFingerprint(other.channelRecommendation)
    }

    private struct ChannelQualityFingerprint: Equatable {
        let channel: Int
        let band: String
        let bandDisplay: String
        let qualityScore: Int
        let qualityLevel: ChannelQuality.QualityLevel
        let apCount: Int
        let coChannelCount: Int
        let adjacentCount: Int
        let interferenceScore: Int
        let overlapLevel: ChannelQuality.OverlapLevel
        let strongestNeighborRSSI: Int
        let isRecommended: Bool
        let isCurrentChannel: Bool
        let showInSimpleView: Bool
        let recommendationScore: Int
        let recommendationLevel: ChannelQuality.QualityLevel
        let recommendationConfidence: ChannelQuality.RecommendationConfidence
        let recommendationState: ChannelQuality.RecommendationState
    }

    private struct ChannelRecommendationFingerprint: Equatable {
        let channel: Int
        let band: String
        let bandDisplay: String
        let rfScore: Int
        let rfLevel: ChannelQuality.QualityLevel
        let apCount: Int
        let coChannelCount: Int
        let adjacentCount: Int
        let interferenceScore: Int
        let overlapLevel: ChannelQuality.OverlapLevel
        let strongestNeighborRSSI: Int
        let isCurrentChannel: Bool
        let showInSimpleView: Bool
        let scoreSelected: Bool
        let recommendationScore: Int
        let recommendationLevel: ChannelQuality.QualityLevel
        let recommendationConfidence: ChannelQuality.RecommendationConfidence
        let recommendationState: ChannelQuality.RecommendationState
        let classification: ChannelRecommendation.Classification
        let restrictionReasons: [(String, String)]
        let recommendationReasons: [String]
        let deviceCompatible: Bool
        let deviceIncompatibilityReason: String?

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.channel == rhs.channel && lhs.band == rhs.band && lhs.bandDisplay == rhs.bandDisplay &&
            lhs.rfScore == rhs.rfScore && lhs.rfLevel == rhs.rfLevel && lhs.apCount == rhs.apCount &&
            lhs.coChannelCount == rhs.coChannelCount && lhs.adjacentCount == rhs.adjacentCount &&
            lhs.interferenceScore == rhs.interferenceScore && lhs.overlapLevel == rhs.overlapLevel &&
            lhs.strongestNeighborRSSI == rhs.strongestNeighborRSSI &&
            lhs.isCurrentChannel == rhs.isCurrentChannel && lhs.showInSimpleView == rhs.showInSimpleView &&
            lhs.scoreSelected == rhs.scoreSelected && lhs.recommendationScore == rhs.recommendationScore &&
            lhs.recommendationLevel == rhs.recommendationLevel &&
            lhs.recommendationConfidence == rhs.recommendationConfidence &&
            lhs.recommendationState == rhs.recommendationState && lhs.classification == rhs.classification &&
            lhs.restrictionReasons.elementsEqual(rhs.restrictionReasons, by: ==) &&
            lhs.recommendationReasons == rhs.recommendationReasons &&
            lhs.deviceCompatible == rhs.deviceCompatible &&
            lhs.deviceIncompatibilityReason == rhs.deviceIncompatibilityReason
        }
    }

    private static func channelQualityFingerprint(_ values: [ChannelQuality]?) -> [ChannelQualityFingerprint]? {
        values?.map {
            ChannelQualityFingerprint(
                channel: $0.channel,
                band: $0.band,
                bandDisplay: $0.bandDisplay,
                qualityScore: $0.qualityScore,
                qualityLevel: $0.qualityLevel,
                apCount: $0.apCount,
                coChannelCount: $0.coChannelCount,
                adjacentCount: $0.adjacentCount,
                interferenceScore: $0.interferenceScore,
                overlapLevel: $0.overlapLevel,
                strongestNeighborRSSI: $0.strongestNeighborRSSI,
                isRecommended: $0.isRecommended,
                isCurrentChannel: $0.isCurrentChannel,
                showInSimpleView: $0.showInSimpleView,
                recommendationScore: $0.recommendationScore,
                recommendationLevel: $0.recommendationLevel,
                recommendationConfidence: $0.recommendationConfidence,
                recommendationState: $0.recommendationState
            )
        }
    }

    private static func channelRecommendationFingerprint(_ values: [ChannelRecommendation]?) -> [ChannelRecommendationFingerprint]? {
        values?.map {
            ChannelRecommendationFingerprint(
                channel: $0.channel,
                band: $0.band,
                bandDisplay: $0.bandDisplay,
                rfScore: $0.rfScore,
                rfLevel: $0.rfLevel,
                apCount: $0.apCount,
                coChannelCount: $0.coChannelCount,
                adjacentCount: $0.adjacentCount,
                interferenceScore: $0.interferenceScore,
                overlapLevel: $0.overlapLevel,
                strongestNeighborRSSI: $0.strongestNeighborRSSI,
                isCurrentChannel: $0.isCurrentChannel,
                showInSimpleView: $0.showInSimpleView,
                scoreSelected: $0.scoreSelected,
                recommendationScore: $0.recommendationScore,
                recommendationLevel: $0.recommendationLevel,
                recommendationConfidence: $0.recommendationConfidence,
                recommendationState: $0.recommendationState,
                classification: $0.classification,
                restrictionReasons: $0.restrictionReasons.map { ($0.code, $0.description) },
                recommendationReasons: $0.recommendationReasons.map(\.rawValue),
                deviceCompatible: $0.deviceCompatible,
                deviceIncompatibilityReason: $0.deviceIncompatibilityReason
            )
        }
    }
}
