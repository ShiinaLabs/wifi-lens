import Foundation
import CoreWLAN
import WiFiLensCore

protocol RoamingProbeProviding: Sendable {
    func fetchCurrentProbe() async -> WiFiCurrentStatus
}

struct RoamingProbeProvider: RoamingProbeProviding {
    func fetchCurrentProbe() async -> WiFiCurrentStatus {
        await MainActor.run {
            guard let iface = CWWiFiClient.shared().interface() else {
                return WiFiCurrentStatus(
                    timestamp: Date(),
                    isConnected: false,
                    isWiFiPowerOn: false,
                    error: .noWiFiInterface
                )
            }
            let ssid = iface.ssid()
            let bssid = iface.bssid()
            let channelNum = iface.wlanChannel()?.channelNumber
            let band = channelNum.flatMap { ChannelBand.from(channelNumber: $0) }
            return WiFiCurrentStatus(
                timestamp: Date(),
                interfaceName: iface.interfaceName,
                ssid: ssid,
                bssid: bssid,
                channel: channelNum,
                band: band,
                rssi: iface.rssiValue(),
                txRate: iface.transmitRate(),
                isConnected: ssid != nil,
                isWiFiPowerOn: true
            )
        }
    }
}
