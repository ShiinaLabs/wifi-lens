import CoreWLAN
import Foundation
import Logging

private let scannerLogger = Logger(label: "scanner")

public enum WiFiPowerState: Sendable {
    case poweredOn
    case poweredOff
    case interfaceUnavailable
}

@MainActor
public final class WiFiPowerMonitor: NSObject, CWEventDelegate {
    private var continuation: AsyncStream<WiFiPowerState>.Continuation?
    private var pollingTask: Task<Void, Never>?
    private var isMonitoring = false
    public private(set) var currentState: WiFiPowerState = .poweredOn

    public override init() {
        super.init()
    }

    public var events: AsyncStream<WiFiPowerState> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(currentState)
        }
    }

    deinit {
        pollingTask?.cancel()
        guard isMonitoring else { return }
        CWWiFiClient.shared().delegate = nil
        try? CWWiFiClient.shared().stopMonitoringEvent(with: .powerDidChange)
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        CWWiFiClient.shared().delegate = self
        try? CWWiFiClient.shared().startMonitoringEvent(with: .powerDidChange)
        refreshState()
        startPolling()
    }

    public func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
        continuation?.finish()
        continuation = nil
        guard isMonitoring else { return }
        isMonitoring = false
        CWWiFiClient.shared().delegate = nil
        try? CWWiFiClient.shared().stopMonitoringEvent(with: .powerDidChange)
    }

    public func refreshState() {
        guard isMonitoring else { return }
        let previous = currentState
        if let iface = CWWiFiClient.shared().interface() {
            currentState = iface.powerOn() ? .poweredOn : .poweredOff
        } else {
            currentState = .interfaceUnavailable
        }
        if currentState != previous {
            scannerLogger.info("WiFi power state changed: \(previous.logLabel) -> \(currentState.logLabel)")
            continuation?.yield(currentState)
        }
    }

    /// Low-frequency polling as safety net — CoreWLAN callbacks can occasionally miss events
    /// when the user toggles WiFi rapidly from the menu bar.
    private func startPolling() {
        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.refreshState()
                }
            }
        }
    }

    // MARK: - CWEventDelegate

    /// CWEventDelegate is deprecated since macOS 10.15, but Apple provides no replacement
    /// for instant power‑state change notification. The delegate callback is still delivered
    /// reliably on macOS 14+ and is safe to keep.

    public nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            refreshState()
        }
    }
}

#if DEBUG
extension WiFiPowerMonitor {
    public var debugIsMonitoringForTesting: Bool { isMonitoring }
}
#endif

private extension WiFiPowerState {
    var logLabel: String {
        switch self {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .interfaceUnavailable: return "interfaceUnavailable"
        }
    }
}
