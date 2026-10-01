import Foundation

public enum WiFiObservationError: Error, Equatable, Sendable {
    case noWiFiInterface
    case wifiPowerOff
    case noWiFiConnection
    case missingSSID
    case missingBSSID
    case missingRouterIP
    case locationPermissionRequired
    case currentStatusFetchFailed(String)
    case environmentScanFailed(String)
    case gatewayPingFailed(String)
    case analyzerFailed(String)
}
