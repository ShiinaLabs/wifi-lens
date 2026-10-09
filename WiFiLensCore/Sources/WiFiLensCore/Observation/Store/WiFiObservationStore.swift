import Foundation

public enum WiFiObservationFieldValidity: String, Equatable, Sendable {
    case current
    case failed
    case notTested
    case expired
}

public struct WiFiObservationValidity: Equatable, Sendable {
    public let currentStatus: WiFiObservationFieldValidity
    public let gatewayLatency: WiFiObservationFieldValidity
    public let environment: WiFiObservationFieldValidity
    public let channelAnalysis: WiFiObservationFieldValidity
    public let channelRecommendation: WiFiObservationFieldValidity
    public let quality: WiFiObservationFieldValidity
    public let diagnosis: WiFiObservationFieldValidity
}

@MainActor
public final class WiFiObservationStore: ObservableObject {
    private static let historyLimit = 120
    public static let shared = WiFiObservationStore()
    public init() {}
    /// The latest accepted full observation cycle. A nil field means that the
    /// value was not produced by this cycle; it never means “keep the old one.”
    @Published public private(set) var currentObservation: WiFiObservation?
    /// Bounded history retains prior complete cycles without presenting them as current.
    @Published public private(set) var history: [WiFiObservation] = []
    @Published public private(set) var validity: WiFiObservationValidity?
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
        history.append(observation)
        history.sort { $0.timestamp < $1.timestamp }
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        if !observation.errors.isEmpty {
            errors.append(contentsOf: observation.errors)
            if errors.count > 20 {
                errors = Array(errors.suffix(20))
            }
        }

        // Late completions remain queryable in history, but cannot replace a
        // newer current projection or make its validity appear fresh again.
        guard currentObservation.map({ observation.timestamp > $0.timestamp }) ?? true else { return }

        currentObservation = observation
        currentStatus = observation.currentStatus
        gatewayLatency = observation.gatewayLatency
        quality = observation.quality
        latestEnvironmentSnapshot = observation.environmentSnapshot
        channelAnalysis = observation.channelAnalysis
        channelRecommendation = observation.channelRecommendation
        diagnosis = observation.diagnosis
        lastUpdated = observation.timestamp
        validity = Self.validity(for: observation)
    }

    /// Returns per-domain freshness at read time. Historical values stay in
    /// `history`; after the age limit, a current value is explicitly expired.
    public func validity(at date: Date = Date(), maximumAge: TimeInterval = 15) -> WiFiObservationValidity? {
        guard let validity, let currentObservation else { return validity }
        guard date.timeIntervalSince(currentObservation.timestamp) > maximumAge else { return validity }
        return WiFiObservationValidity(
            currentStatus: validity.currentStatus == .current ? .expired : validity.currentStatus,
            gatewayLatency: validity.gatewayLatency == .current ? .expired : validity.gatewayLatency,
            environment: validity.environment == .current ? .expired : validity.environment,
            channelAnalysis: validity.channelAnalysis == .current ? .expired : validity.channelAnalysis,
            channelRecommendation: validity.channelRecommendation == .current ? .expired : validity.channelRecommendation,
            quality: validity.quality == .current ? .expired : validity.quality,
            diagnosis: validity.diagnosis == .current ? .expired : validity.diagnosis
        )
    }

    private static func validity(for observation: WiFiObservation) -> WiFiObservationValidity {
        let environmentFailed = observation.environmentSnapshot?.error != nil
        let environment: WiFiObservationFieldValidity = observation.environmentSnapshot.map { $0.error == nil ? .current : .failed } ?? .notTested
        func derived<T>(_ value: T?) -> WiFiObservationFieldValidity {
            if value != nil { return .current }
            return environmentFailed ? .failed : .notTested
        }
        let status: WiFiObservationFieldValidity = observation.currentStatus.map { $0.error == nil ? .current : .failed } ?? .notTested
        let latency: WiFiObservationFieldValidity
        if let result = observation.gatewayLatency {
            switch result.probeOutcome {
            case .notTested, nil:
                latency = .notTested
            case .executionFailed, .cancelled, .localTimeout:
                latency = .failed
            case .replied, .noReply:
                latency = .current
            }
        } else {
            latency = .notTested
        }
        return WiFiObservationValidity(
            currentStatus: status,
            gatewayLatency: latency,
            environment: environment,
            channelAnalysis: derived(observation.channelAnalysis),
            channelRecommendation: derived(observation.channelRecommendation),
            quality: derived(observation.quality),
            diagnosis: derived(observation.diagnosis)
        )
    }
}
