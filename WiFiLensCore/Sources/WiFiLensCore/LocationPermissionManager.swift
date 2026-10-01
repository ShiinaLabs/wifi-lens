import CoreLocation
import AppKit
import Logging
import Observation

private let locationLogger = Logger(label: "location")

@MainActor
@Observable
public final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager?

    public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public var showDeniedAlert = false
    public var onAuthorizationGranted: (() -> Void)?

    public var isAuthorizedForSSID: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return true
        default:
            return false
        }
    }

    public init(liveAuthorizationEnabled: Bool = true) {
        manager = liveAuthorizationEnabled ? CLLocationManager() : nil
        super.init()
        manager?.delegate = self
        if let manager {
            authorizationStatus = manager.authorizationStatus
        }
    }

    public func refreshStatus() {
        guard let manager else { return }
        let status = manager.authorizationStatus
        authorizationStatus = status
        showDeniedAlert = status == .denied || status == .restricted
    }

    public func requestPermissionIfNeeded() {
        guard manager != nil else { return }
        refreshStatus()
        locationLogger.debug("requestPermissionIfNeeded() — status=\(authorizationStatus.rawValue)")
        guard authorizationStatus == .notDetermined else { return }
        manager?.requestWhenInUseAuthorization()
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.showDeniedAlert = status == .denied || status == .restricted
            if status != .notDetermined, self.isAuthorizedForSSID {
                self.onAuthorizationGranted?()
            }
        }
    }

    public func openLocationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

}
