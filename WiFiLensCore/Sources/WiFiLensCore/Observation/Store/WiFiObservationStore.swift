import Foundation

@MainActor
public final class WiFiObservationStore: ObservableObject {
    public static let shared = WiFiObservationStore()
    public init() {}
    @Published public var currentStatus: WiFiCurrentStatus?
    @Published public var gatewayLatency: GatewayLatencyResult?
    @Published public var quality: WiFiQualityResult?

    @Published public var latestEnvironmentSnapshot: WiFiEnvironmentSnapshot?
    @Published public var channelAnalysis: [ChannelQuality]?
    @Published public var channelRecommendation: [ChannelRecommendation]?

    @Published public var diagnosis: DiagnosticResult?

    @Published public var isRefreshingCurrent = false
    @Published public var isScanningEnvironment = false
    @Published public var lastUpdated: Date?
    @Published public var errors: [WiFiObservationError] = []

    public func apply(_ observation: WiFiObservation) {
        if let status = observation.currentStatus {
            currentStatus = status
        }
        if let latency = observation.gatewayLatency {
            gatewayLatency = latency
        }
        if let q = observation.quality {
            quality = q
        }
        if let snapshot = observation.environmentSnapshot {
            latestEnvironmentSnapshot = snapshot
        }
        if let analysis = observation.channelAnalysis {
            channelAnalysis = analysis
        }
        if let recs = observation.channelRecommendation {
            channelRecommendation = recs
        }
        if let diag = observation.diagnosis {
            diagnosis = diag
        }
        if !observation.errors.isEmpty {
            errors.append(contentsOf: observation.errors)
            if errors.count > 20 {
                errors = Array(errors.suffix(20))
            }
        }
        lastUpdated = Date()
    }
}
