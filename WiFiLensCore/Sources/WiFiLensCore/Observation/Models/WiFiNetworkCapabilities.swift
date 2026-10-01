import Foundation

public struct WiFiNetworkCapabilities: Equatable, Sendable {
    public init(phyMode: String, channelWidth: Int, supports80211k: Bool, supports80211r: Bool, supports80211v: Bool, supportsWPA3: Bool, countryCode: String? = nil, isHiddenSSID: Bool = false, mcs: String? = nil, nss: String? = nil, security: String? = nil) {
        self.phyMode = phyMode; self.channelWidth = channelWidth; self.supports80211k = supports80211k; self.supports80211r = supports80211r
        self.supports80211v = supports80211v; self.supportsWPA3 = supportsWPA3; self.countryCode = countryCode; self.isHiddenSSID = isHiddenSSID
        self.mcs = mcs; self.nss = nss; self.security = security
    }
    public var phyMode: String
    public var channelWidth: Int
    public var supports80211k: Bool
    public var supports80211r: Bool
    public var supports80211v: Bool
    public var supportsWPA3: Bool
    public var countryCode: String?
    public var isHiddenSSID: Bool
    public var mcs: String?
    public var nss: String?
    public var security: String?

    public static let empty = WiFiNetworkCapabilities(
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

    public static func emptyWithWidth(_ width: Int) -> WiFiNetworkCapabilities {
        var caps = WiFiNetworkCapabilities.empty
        caps.channelWidth = width
        return caps
    }
}
