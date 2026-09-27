import CoreWLAN
import Foundation

struct WiFiNetwork: Sendable, Identifiable {
    var id: String { "\(bssid)-\(channel.channelNumber)-\(channel.band.rawValue)" }
    let ssid: String?
    let bssid: String
    let rssi: Int
    let channel: WiFiChannel
    let isIBSS: Bool
    let ieData: Data?

    init?(from cwNetwork: CWNetwork) {
        guard let wlanChannel = cwNetwork.wlanChannel else { return nil }
        ssid = cwNetwork.ssid
        bssid = cwNetwork.bssid ?? "unknown"
        rssi = cwNetwork.rssiValue
        channel = WiFiChannel(from: wlanChannel)
        isIBSS = cwNetwork.ibss
        ieData = cwNetwork.informationElementData
    }

    init(ssid: String?, bssid: String, rssi: Int, channel: WiFiChannel, ieData: Data? = nil) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.isIBSS = false
        self.ieData = ieData
    }
}
