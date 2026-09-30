import SwiftUI
import WiFiLensCore

struct LocationPermissionRequiredView: View {
    let accessState: ScanAccessState
    let openLocationPreferences: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.5)
                .accessibilityLabel(String(localized: "permission.location.waiting", comment: "Status while waiting for Location Services authorization"))
            switch accessState {
            case .waitingForAuthorization:
                Text(String(localized: "permission.location.waiting", comment: "Status while waiting for Location Services authorization"))
                    .foregroundColor(.orange)
                Button(String(localized: "common.action.open_system_settings", comment: "Button to open macOS System Settings")) {
                    openLocationPreferences()
                }
                .accessibilityIdentifier("open-location-settings-button")
            case .denied:
                Text(String(localized: "permission.location.required_short", comment: "Short label: Location Services required"))
                    .foregroundColor(.secondary)
                Button(String(localized: "common.action.open_location_preferences", comment: "Button to open Location Services preferences")) {
                    openLocationPreferences()
                }
                .accessibilityIdentifier("open-location-settings-button")
            default:
                Text(String(localized: "permission.location.required_short", comment: "Short label: Location Services required"))
                    .foregroundColor(.secondary)
                Button(String(localized: "common.action.open_location_preferences", comment: "Button to open Location Services preferences")) {
                    openLocationPreferences()
                }
                .accessibilityIdentifier("open-location-settings-button")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("location-permission-view")
    }
}
