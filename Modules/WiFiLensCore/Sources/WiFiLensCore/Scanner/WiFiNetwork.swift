import CoreWLAN
import Foundation

public struct WiFiNetwork: Sendable, Identifiable {
    public var id: String { "\(bssid)-\(channel.channelNumber)-\(channel.band.rawValue)" }
    public let ssid: String?
    public let bssid: String
    public let rssi: Int
    public let channel: WiFiChannel
    public let isIBSS: Bool
    public let ieData: Data?

    public init?(from cwNetwork: CWNetwork) {
        guard let wlanChannel = cwNetwork.wlanChannel else { return nil }
        ssid = cwNetwork.ssid
        bssid = cwNetwork.bssid ?? "unknown"
        rssi = cwNetwork.rssiValue
        channel = WiFiChannel(from: wlanChannel)
        isIBSS = cwNetwork.ibss
        ieData = cwNetwork.informationElementData
    }

    public init(ssid: String?, bssid: String, rssi: Int, channel: WiFiChannel, ieData: Data? = nil) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.isIBSS = false
        self.ieData = ieData
    }
}
