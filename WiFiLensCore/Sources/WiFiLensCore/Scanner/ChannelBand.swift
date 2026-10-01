public enum ChannelBand: Int, Sendable, CaseIterable, Hashable {
    case band24GHz = 1
    case band5GHz = 2
    case band6GHz = 3

    public var displayName: String {
        switch self {
        case .band24GHz: String(localized: "wifi.band.24ghz", comment: "2.4 GHz Wi-Fi band name")
        case .band5GHz: String(localized: "wifi.band.5ghz", comment: "5 GHz Wi-Fi band name")
        case .band6GHz: String(localized: "wifi.band.6ghz", comment: "6 GHz Wi-Fi band name")
        }
    }

    /// Short identifier matching the current app's band IDs ("24", "5", "6")
    public var id: String {
        switch self {
        case .band24GHz: "24"
        case .band5GHz: "5"
        case .band6GHz: "6"
        }
    }

    public var maxChannel: Int {
        switch self {
        case .band24GHz: 16
        case .band5GHz: 170
        case .band6GHz: 233
        }
    }

    public init?(id: String) {
        switch id {
        case "24": self = .band24GHz
        case "5":  self = .band5GHz
        case "6":  self = .band6GHz
        default:   return nil
        }
    }
}
