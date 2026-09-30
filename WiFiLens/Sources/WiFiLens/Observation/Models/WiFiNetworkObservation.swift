import Foundation
import WiFiLensCore

struct WiFiNetworkObservation: Identifiable, Equatable, Sendable {
    var id: String
    var ssid: String?
    var bssid: String
    var rssi: Int
    var channel: WiFiChannel
    var isIBSS: Bool
    var capabilities: WiFiNetworkCapabilities
    var rawIEData: Data?
    var isCurrentNetwork: Bool

    init(
        ssid: String?,
        bssid: String,
        rssi: Int,
        channel: WiFiChannel,
        isIBSS: Bool = false,
        capabilities: WiFiNetworkCapabilities = .empty,
        rawIEData: Data? = nil,
        isCurrentNetwork: Bool = false
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.rssi = rssi
        self.channel = channel
        self.isIBSS = isIBSS
        self.capabilities = capabilities
        self.rawIEData = rawIEData
        self.isCurrentNetwork = isCurrentNetwork
        self.id = WiFiNetworkObservation.makeID(
            bssid: bssid, ssid: ssid, channel: channel,
            security: capabilities.security, phyMode: capabilities.phyMode
        )
    }

    static func makeID(
        bssid: String,
        ssid: String?,
        channel: WiFiChannel,
        security: String?,
        phyMode: String?
    ) -> String {
        if !bssid.isEmpty && bssid != "unknown" {
            return "\(bssid)-\(channel.channelNumber)-\(channel.band.rawValue)"
        }
        let parts = [
            ssid ?? "",
            "\(channel.channelNumber)",
            channel.band.id,
            security ?? "",
            phyMode ?? ""
        ]
        return "local-\(parts.joined(separator: "-"))"
    }

    static func == (lhs: WiFiNetworkObservation, rhs: WiFiNetworkObservation) -> Bool {
        lhs.id == rhs.id &&
        lhs.ssid == rhs.ssid &&
        lhs.bssid == rhs.bssid &&
        lhs.rssi == rhs.rssi &&
        lhs.channel.band == rhs.channel.band &&
        lhs.channel.channelNumber == rhs.channel.channelNumber &&
        lhs.channel.channelWidthMHz == rhs.channel.channelWidthMHz &&
        lhs.isIBSS == rhs.isIBSS &&
        lhs.capabilities == rhs.capabilities &&
        lhs.rawIEData == rhs.rawIEData &&
        lhs.isCurrentNetwork == rhs.isCurrentNetwork
    }
}
