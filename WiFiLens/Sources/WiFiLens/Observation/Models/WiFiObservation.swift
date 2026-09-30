import Foundation
import WiFiLensCore

struct WiFiObservation: Equatable, Sendable {
    var timestamp: Date
    var currentStatus: WiFiCurrentStatus?
    var environmentSnapshot: WiFiEnvironmentSnapshot?
    var gatewayLatency: GatewayLatencyResult?
    var quality: WiFiQualityResult?
    var channelAnalysis: [ChannelQuality]?
    var channelRecommendation: [ChannelRecommendation]?
    var diagnosis: DiagnosticResult?
    var errors: [WiFiObservationError]

    init(
        timestamp: Date = Date(),
        currentStatus: WiFiCurrentStatus? = nil,
        environmentSnapshot: WiFiEnvironmentSnapshot? = nil,
        gatewayLatency: GatewayLatencyResult? = nil,
        quality: WiFiQualityResult? = nil,
        channelAnalysis: [ChannelQuality]? = nil,
        channelRecommendation: [ChannelRecommendation]? = nil,
        diagnosis: DiagnosticResult? = nil,
        errors: [WiFiObservationError] = []
    ) {
        self.timestamp = timestamp
        self.currentStatus = currentStatus
        self.environmentSnapshot = environmentSnapshot
        self.gatewayLatency = gatewayLatency
        self.quality = quality
        self.channelAnalysis = channelAnalysis
        self.channelRecommendation = channelRecommendation
        self.diagnosis = diagnosis
        self.errors = errors
    }

    static func == (lhs: WiFiObservation, rhs: WiFiObservation) -> Bool {
        lhs.timestamp == rhs.timestamp &&
        lhs.currentStatus == rhs.currentStatus &&
        lhs.environmentSnapshot == rhs.environmentSnapshot &&
        lhs.gatewayLatency == rhs.gatewayLatency &&
        lhs.quality == rhs.quality &&
        lhs.diagnosis == rhs.diagnosis &&
        lhs.errors == rhs.errors &&
        channelQualityFingerprint(lhs.channelAnalysis) == channelQualityFingerprint(rhs.channelAnalysis) &&
        channelRecommendationFingerprint(lhs.channelRecommendation) == channelRecommendationFingerprint(rhs.channelRecommendation)
    }

    private static func channelQualityFingerprint(_ q: [ChannelQuality]?) -> (count: Int, scores: [Int], channels: [Int]) {
        guard let q else { return (0, [], []) }
        return (q.count, q.map(\.qualityScore), q.map(\.channel))
    }

    private static func channelRecommendationFingerprint(_ r: [ChannelRecommendation]?) -> (count: Int, channels: [Int], rfScores: [Int], recScores: [Int]) {
        guard let r else { return (0, [], [], []) }
        return (r.count, r.map(\.channel), r.map(\.rfScore), r.map(\.recommendationScore))
    }
}
