import Foundation
import WiFiLensCore

struct WiFiNetworkCapabilities: Equatable, Sendable {
    var phyMode: String
    var channelWidth: Int
    var supports80211k: Bool
    var supports80211r: Bool
    var supports80211v: Bool
    var supportsWPA3: Bool
    var countryCode: String?
    var isHiddenSSID: Bool
    var mcs: String?
    var nss: String?
    var security: String?

    static let empty = WiFiNetworkCapabilities(
        phyMode: "",
        channelWidth: 20,
        supports80211k: false,
        supports80211r: false,
        supports80211v: false,
        supportsWPA3: false,
        countryCode: nil,
        isHiddenSSID: false,
        mcs: nil,
        nss: nil,
        security: nil
    )

    static func emptyWithWidth(_ width: Int) -> WiFiNetworkCapabilities {
        var caps = WiFiNetworkCapabilities.empty
        caps.channelWidth = width
        return caps
    }
}
