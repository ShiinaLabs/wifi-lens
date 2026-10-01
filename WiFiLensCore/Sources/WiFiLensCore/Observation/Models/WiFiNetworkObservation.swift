import Foundation

public struct WiFiNetworkObservation: Identifiable, Equatable, Sendable {
    public var id: String
    public var ssid: String?
    public var bssid: String
    public var rssi: Int
    public var channel: WiFiChannel
    public var isIBSS: Bool
    public var capabilities: WiFiNetworkCapabilities
    public var rawIEData: Data?
    public var isCurrentNetwork: Bool

    public init(
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

    public static func makeID(
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

    public static func == (lhs: WiFiNetworkObservation, rhs: WiFiNetworkObservation) -> Bool {
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
