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

@MainActor
final class WiFiPowerMonitor {
    private let center: WiFiLinkStateCenter
    private var continuation: AsyncStream<WiFiPowerState>.Continuation?
    private var stateTask: Task<Void, Never>?
    private var isMonitoring = false
    private(set) var currentState: WiFiPowerState = .unknown

    init(center: WiFiLinkStateCenter = .shared) {
        self.center = center
    }

    var events: AsyncStream<WiFiPowerState> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation?.finish()
            self.continuation = continuation
            continuation.yield(currentState)
        }
    }

    deinit {
        stateTask?.cancel()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        stateTask = Task { [weak self, center] in
            await center.start()
            let stream = await center.currentStates()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self?.apply(snapshot)
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

    private func apply(_ snapshot: WiFiLinkStateSnapshot) {
        let next: WiFiPowerState
        switch snapshot.radio {
        case .reportedOn:
            next = .poweredOn
        case .reportedOffOrReadFailure:
            // CoreWLAN false can be a read failure; keep scanning in the ambiguous state.
            next = .unknown
        case .unavailable:
            next = snapshot.reason == .interfaceUnavailable ? .interfaceUnavailable : .unknown
        }
        guard currentState != next else { return }
        let previous = currentState
        currentState = next
        scannerLogger.info("WiFi radio evidence changed: \(String(describing: previous)) → \(String(describing: next))")
        continuation?.yield(next)
    }
}

#if DEBUG
extension WiFiPowerMonitor {
    var debugIsMonitoringForTesting: Bool { isMonitoring }
}
#endif
