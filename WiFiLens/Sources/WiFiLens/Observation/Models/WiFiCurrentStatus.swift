import Foundation
import WiFiLensCore

struct WiFiCurrentStatus: Equatable, Sendable {
    var timestamp: Date
    var interfaceSnapshotCycleID: UUID? = nil
    var interfaceName: String?
    var ssid: String?
    var bssid: String?
    var channel: Int?
    var band: ChannelBand?
    var rssi: Int?
    var noise: Int?
    var txRate: Double?
    var phyMode: String?
    var security: String?
    var routerIP: String?
    var isConnected: Bool
    var isWiFiPowerOn: Bool
    var error: WiFiObservationError?
}
