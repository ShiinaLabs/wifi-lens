import CoreBluetooth
import AppKit
import Logging

@MainActor
@Observable
public final class BluetoothPermissionManager {
    private static let logger = Logger(label: "ble")

    public private(set) var authorizationStatus: CBManagerAuthorization = .notDetermined
    var showDeniedAlert = false

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .allowedAlways:
            return true
        default:
            return false
        }
    }

    public init() {
        refreshStatus()
    }

    func refreshStatus() {
        authorizationStatus = CBCentralManager.authorization
        showDeniedAlert = authorizationStatus == .denied || authorizationStatus == .restricted
        Self.logger.debug("Bluetooth auth status: \(authorizationStatus.rawValue)")
    }

    /// Creating a CBCentralManager triggers the system permission dialog
    /// when status is .notDetermined. We create a temporary one just for
    /// authorization — BLEScanner creates its own for actual scanning.
    func requestPermissionIfNeeded() {
        refreshStatus()
        guard authorizationStatus == .notDetermined else { return }
        let temp = CBCentralManager(delegate: nil, queue: nil)
        // The act of initing CBCentralManager while .notDetermined shows
        // the system dialog. The result is delivered via the CBCentralManager's
        // delegate callback (handled by BLEScanner when scanning starts).
        // Store a reference so it isn't immediately deallocated.
        _ = temp
    }

    func openBluetoothPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
}
