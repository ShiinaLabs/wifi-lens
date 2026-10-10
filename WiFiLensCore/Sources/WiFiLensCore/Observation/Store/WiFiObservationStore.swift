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
    public static let currentValueMaximumAge: TimeInterval = 15
    public static let shared = WiFiObservationStore()
    public init() {}
    private var validityExpiryTask: Task<Void, Never>?
    /// The latest accepted full observation cycle. A nil field means that the
    /// value was not produced by this cycle; it never means “keep the old one.”
    @Published public private(set) var currentObservation: WiFiObservation?
    /// Bounded history retains prior complete cycles without presenting them as current.
    @Published public private(set) var history: [WiFiObservation] = []
    private(set) var sourceIdentityConflictCount = 0
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
    private var scanLifecycleStartedAt: Date?

    func beginScanLifecycle(at date: Date) {
        scanLifecycleStartedAt = date
        isScanningEnvironment = true
    }

    func endScanLifecycle() {
        isScanningEnvironment = false
        scanLifecycleStartedAt = nil
    }

    @discardableResult
    public func apply(_ observation: WiFiObservation) -> Bool {
        if let existing = history.first(where: { $0.sourceObservationID == observation.sourceObservationID }) {
            guard existing.hasSameContent(as: observation) else {
                sourceIdentityConflictCount &+= 1
                return false
            }
            return false
        }
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
        guard currentObservation.map({ observation.timestamp > $0.timestamp }) ?? true else { return true }

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
        validityExpiryTask?.cancel()
        let observationTimestamp = observation.timestamp
        let observationCycleID = observation.sourceCycleID
        validityExpiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(Self.currentValueMaximumAge)) } catch { return }
            guard let self, currentObservation?.timestamp == observationTimestamp,
                  currentObservation?.sourceCycleID == observationCycleID else { return }
            expireCurrentValuesIfNeeded(at: Date())
        }
        return true
    }

    /// Returns per-domain freshness at read time. Historical values stay in
    /// `history`; after the age limit, a current value is explicitly expired.
    public func validity(at date: Date = Date(), maximumAge: TimeInterval = 15) -> WiFiObservationValidity? {
        guard let validity, let currentObservation else { return validity }
        var result = date.timeIntervalSince(currentObservation.timestamp) > maximumAge
            ? expired(validity)
            : validity
        guard isScanningEnvironment,
              let scanLifecycleStartedAt,
              currentObservation.timestamp >= scanLifecycleStartedAt else {
            result = WiFiObservationValidity(
                currentStatus: result.currentStatus,
                gatewayLatency: result.gatewayLatency == .current ? .expired : result.gatewayLatency,
                environment: result.environment == .current ? .expired : result.environment,
                channelAnalysis: result.channelAnalysis == .current ? .expired : result.channelAnalysis,
                channelRecommendation: result.channelRecommendation == .current ? .expired : result.channelRecommendation,
                quality: result.quality == .current ? .expired : result.quality,
                diagnosis: result.diagnosis == .current ? .expired : result.diagnosis
            )
            return result
        }
        return result
    }

    /// Publishes expiry once so SwiftUI consumers re-render even when no later
    /// observation arrives. Historical observations remain untouched.
    func expireCurrentValuesIfNeeded(at date: Date) {
        guard let currentValidity = validity,
              let currentObservation,
              date.timeIntervalSince(currentObservation.timestamp) > Self.currentValueMaximumAge else { return }
        validity = expired(currentValidity)
    }

    private func expired(_ validity: WiFiObservationValidity) -> WiFiObservationValidity {
        WiFiObservationValidity(
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
