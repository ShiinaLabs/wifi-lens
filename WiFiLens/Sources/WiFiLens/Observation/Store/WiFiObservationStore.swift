import Foundation
import WiFiLensCore

@MainActor
final class WiFiObservationStore: ObservableObject {
    static let shared = WiFiObservationStore()
    @Published var currentStatus: WiFiCurrentStatus?
    @Published var gatewayLatency: GatewayLatencyResult?
    @Published var quality: WiFiQualityResult?

    @Published var latestEnvironmentSnapshot: WiFiEnvironmentSnapshot?
    @Published var channelAnalysis: [ChannelQuality]?
    @Published var channelRecommendation: [ChannelRecommendation]?

    @Published var diagnosis: DiagnosticResult?

    @Published var isRefreshingCurrent = false
    @Published var isScanningEnvironment = false
    @Published var lastUpdated: Date?
    @Published var errors: [WiFiObservationError] = []

    func apply(_ observation: WiFiObservation) {
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
