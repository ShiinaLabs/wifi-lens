import CoreLocation
import AppKit

@MainActor
@Observable
final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager?

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var showDeniedAlert = false
    var onAuthorizationGranted: (() -> Void)?

    var isAuthorizedForSSID: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .authorized:
            return true
        default:
            return false
        }
    }

    init(liveAuthorizationEnabled: Bool = true) {
        manager = liveAuthorizationEnabled ? CLLocationManager() : nil
        super.init()
        manager?.delegate = self
        if let manager {
            authorizationStatus = manager.authorizationStatus
        }
    }

    func refreshStatus() {
        guard let manager else { return }
        let status = manager.authorizationStatus
        authorizationStatus = status
        showDeniedAlert = status == .denied || status == .restricted
    }

    func requestPermissionIfNeeded() {
        guard manager != nil else { return }
        refreshStatus()
        AppLogger.location.debug("requestPermissionIfNeeded() — status=\(authorizationStatus.rawValue)")
        guard authorizationStatus == .notDetermined else { return }
        manager?.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.showDeniedAlert = status == .denied || status == .restricted
            if status != .notDetermined, self.isAuthorizedForSSID {
                self.onAuthorizationGranted?()
            }
        }
    }

    func openLocationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

}
