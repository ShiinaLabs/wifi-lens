import Foundation

public struct WiFiCurrentStatus: Equatable, Sendable {
    public init(timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil, band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil, security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool) {
        self.init(timestamp: timestamp, interfaceSnapshotCycleID: interfaceSnapshotCycleID, interfaceName: interfaceName, ssid: ssid, bssid: bssid, channel: channel, band: band, rssi: rssi, noise: noise, txRate: txRate, phyMode: phyMode, security: security, routerIP: routerIP, isConnected: isConnected, isWiFiPowerOn: isWiFiPowerOn, error: nil)
    }

    init(timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil, band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil, security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool, error: WiFiObservationError?) {
        self.timestamp = timestamp; self.interfaceSnapshotCycleID = interfaceSnapshotCycleID; self.interfaceName = interfaceName
        self.ssid = ssid; self.bssid = bssid; self.channel = channel; self.band = band; self.rssi = rssi; self.noise = noise
        self.txRate = txRate; self.phyMode = phyMode; self.security = security; self.routerIP = routerIP
        self.isConnected = isConnected; self.isWiFiPowerOn = isWiFiPowerOn; self.error = error
    }
    public var timestamp: Date
    var interfaceSnapshotCycleID: UUID? = nil
    public var interfaceName: String?
    public var ssid: String?
    public var bssid: String?
    public var channel: Int?
    public var band: ChannelBand?
    public var rssi: Int?
    public var noise: Int?
    public var txRate: Double?
    public var phyMode: String?
    public var security: String?
    public var routerIP: String?
    public var isConnected: Bool
    public var isWiFiPowerOn: Bool
    var error: WiFiObservationError?
}
