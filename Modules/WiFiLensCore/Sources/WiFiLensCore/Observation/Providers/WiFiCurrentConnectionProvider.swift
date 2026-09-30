import Foundation

extension ChannelBand {
    static func from(channelNumber: Int) -> ChannelBand? {
        switch channelNumber {
        case 1...16: .band24GHz
        case 17...170: .band5GHz
        case 171...233: .band6GHz
        default: nil
        }
    }
}

public protocol WiFiCurrentConnectionProviding: Sendable {
    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus
}

public struct WiFiCurrentConnectionProvider: WiFiCurrentConnectionProviding {
    public init() {}
    public func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus {
        guard let wifi = snapshot.interfaces.first(where: { $0.ssid != nil }) else {
            return WiFiCurrentStatus(
                timestamp: snapshot.capturedAt,
                interfaceSnapshotCycleID: snapshot.cycleID,
                isConnected: false,
                isWiFiPowerOn: true,
                error: .noWiFiConnection
            )
        }
        return Self.makeStatus(from: wifi, snapshot: snapshot)
    }

    public static func makeStatus(
        from wifi: NetworkInterfaceInfo,
        snapshot: NetworkInterfaceSnapshot
    ) -> WiFiCurrentStatus {
        WiFiCurrentStatus(
            timestamp: snapshot.capturedAt,
            interfaceSnapshotCycleID: snapshot.cycleID,
            interfaceName: wifi.interfaceName,
            ssid: wifi.ssid,
            bssid: wifi.bssid,
            channel: wifi.channel,
            band: wifi.band,
            rssi: wifi.rssi,
            txRate: wifi.txRate,
            phyMode: wifi.phyMode,
            security: wifi.security,
            routerIP: wifi.router,
            isConnected: true,
            isWiFiPowerOn: true
        )
    }
}
