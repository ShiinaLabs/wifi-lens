import Foundation
import Logging

private let scannerLogger = Logger(label: "scanner")

/// Compatibility facade for existing scan lifecycle consumers. The process-wide
/// link state center owns all system monitoring and shared notifications.
public enum WiFiPowerState: Sendable, Equatable {
    case poweredOn
    case poweredOff
    case interfaceUnavailable
    case unknown
}

struct WiFiPowerSampleIdentity: Equatable, Sendable {
    let runSessionID: UUID
    let sequence: UInt64
    let snapshotID: UUID
}

struct WiFiPowerMonitorEvent: Sendable {
    let state: WiFiPowerState
    /// Nil denotes the cached initial value, not a new radio sample.
    let sampleIdentity: WiFiPowerSampleIdentity?
}

@MainActor
final class WiFiPowerMonitor {
    private let center: WiFiLinkStateCenter
    private var continuation: AsyncStream<WiFiPowerMonitorEvent>.Continuation?
    private var stateTask: Task<Void, Never>?
    private var isMonitoring = false
    private var lastAppliedSnapshotID: UUID?
    private var isReceivingInitialSnapshot = false
#if DEBUG
    private(set) var debugPublishedSampleCount = 0
#endif
    private(set) var currentState: WiFiPowerState = .unknown

    init(center: WiFiLinkStateCenter = .shared) {
        self.center = center
    }

    var events: AsyncStream<WiFiPowerMonitorEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation?.finish()
            self.continuation = continuation
            continuation.yield(WiFiPowerMonitorEvent(state: currentState, sampleIdentity: nil))
        }
    }

    deinit {
        stateTask?.cancel()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isReceivingInitialSnapshot = true
        stateTask = Task { [weak self, center] in
            await center.start()
            let stream = await center.currentStates()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if isReceivingInitialSnapshot {
                    isReceivingInitialSnapshot = false
                    apply(snapshot, countsAsEvidence: false)
                } else {
                    apply(snapshot)
                }
            }
        }
    }

    /// Stops only this compatibility subscription. Other center consumers keep running.
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stateTask?.cancel()
        stateTask = nil
        continuation?.finish()
        continuation = nil
    }

    func refreshState() {
        guard isMonitoring else { return }
        Task { [weak self, center] in
            await center.refresh()
            let snapshot = await center.snapshot()
            self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: WiFiLinkStateSnapshot, countsAsEvidence: Bool = true) {
        guard lastAppliedSnapshotID != snapshot.id else { return }
        lastAppliedSnapshotID = snapshot.id
        let next: WiFiPowerState
        switch snapshot.radio {
        case .reportedOn:
            next = .poweredOn
        case .reportedOff:
            next = .poweredOff
        case .reportedOffOrReadFailure:
            // CoreWLAN false can be a read failure; keep scanning in the ambiguous state.
            next = .unknown
        case .unavailable:
            next = snapshot.reason == .interfaceUnavailable ? .interfaceUnavailable : .unknown
        }
        let previous = currentState
        currentState = next
        if previous != next {
            scannerLogger.info("WiFi radio evidence changed: \(String(describing: previous)) → \(String(describing: next))")
        }
        // Repeated equal states are still fresh evidence samples. The scanner
        // uses them to bound work while radio evidence remains unknown.
        let identity = WiFiPowerSampleIdentity(
            runSessionID: snapshot.runSessionID,
            sequence: snapshot.sequence,
            snapshotID: snapshot.id
        )
        continuation?.yield(WiFiPowerMonitorEvent(state: next, sampleIdentity: countsAsEvidence ? identity : nil))
#if DEBUG
        if countsAsEvidence { debugPublishedSampleCount += 1 }
#endif
    }
}

#if DEBUG
extension WiFiPowerMonitor {
    var debugIsMonitoringForTesting: Bool { isMonitoring }
    func debugApplySnapshotForTesting(_ snapshot: WiFiLinkStateSnapshot) { apply(snapshot) }
}
#endif
