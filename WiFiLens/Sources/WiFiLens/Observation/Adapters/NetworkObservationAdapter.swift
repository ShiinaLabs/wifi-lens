import Foundation

enum NetworkObservationAdapter {
    static func adapt(
        _ network: WiFiNetwork,
        isCurrentNetwork: Bool = false,
        currentBSSID: String? = nil
    ) -> WiFiNetworkObservation {
        let ieData = network.ieData
        let capabilities = ieData.map { IEParser.parse(data: $0) }
            .map { parseCapabilities($0, fallbackWidth: network.channel.channelWidthMHz) }
            ?? WiFiNetworkCapabilities.emptyWithWidth(network.channel.channelWidthMHz)

        let isCurrent = isCurrentNetwork || network.bssid == currentBSSID

        return WiFiNetworkObservation(
            ssid: network.ssid,
            bssid: network.bssid,
            rssi: network.rssi,
            channel: network.channel,
            isIBSS: network.isIBSS,
            capabilities: capabilities,
            rawIEData: ieData,
            isCurrentNetwork: isCurrent
        )
    }

    static func adaptAll(
        _ networks: [WiFiNetwork],
        currentBSSID: String? = nil
    ) -> [WiFiNetworkObservation] {
        networks.map { adapt($0, currentBSSID: currentBSSID) }
    }

    static func parseCapabilities(_ ie: IEData, fallbackWidth: Int = 20) -> WiFiNetworkCapabilities {
        let phyMode: String = {
            if ie.heSupported { return "ax" }
            if ie.vhtSupported { return "ac" }
            if ie.htSupported { return "n" }
            return ""
        }()

        let channelWidth: Int = {
            if ie.supports160MHz { return 160 }
            if ie.supports80MHz { return 80 }
            if let operation = ie.htChannelOperation { return operation.widthMHz }
            return fallbackWidth
        }()

        return WiFiNetworkCapabilities(
            phyMode: phyMode,
            channelWidth: channelWidth,
            supports80211k: ie.supports80211k,
            supports80211r: ie.supports80211r,
            supports80211v: ie.supports80211v,
            supportsWPA3: ie.supportsWPA3,
            countryCode: ie.countryCode,
            isHiddenSSID: ie.isHiddenSSID,
            mcs: ie.mcsSummary,
            nss: ie.nssSummary,
            security: ie.securitySummary
        )
    }
}
