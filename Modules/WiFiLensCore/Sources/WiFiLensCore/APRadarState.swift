import Foundation

/// Access point tracked by AP Radar. Identity is exclusively the BSSID;
/// SSID, channel, and band are presentation metadata refreshed from the
/// latest scan results.
public struct TrackedAccessPoint: Equatable, Sendable {
    public let bssid: String
    public var currentSSID: String?
    public var channel: Int?
    public var band: ChannelBand?

    public init(bssid: String, currentSSID: String?, channel: Int?, band: ChannelBand?) {
        self.bssid = Self.normalizedBSSID(bssid)
        // Empty SSIDs from hidden networks are normalized to nil so the UI
        // always shows the "Hidden Network" label instead of a blank name.
        if let currentSSID, !currentSSID.isEmpty {
            self.currentSSID = currentSSID
        } else {
            self.currentSSID = nil
        }
        self.channel = channel
        self.band = band
    }

    /// Canonical BSSID form used for matching and display: uppercased, with
    /// insignificant whitespace removed.
    public static func normalizedBSSID(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .uppercased()
    }
}

/// Current AP Radar session state. Single source of truth; the UI switches
/// on this instead of a set of interlocked booleans.
public enum APRadarState: Equatable {
    case idle
    case tracking(APRadarSnapshot)
    case signalLost(APRadarLostSnapshot)
}

public struct APRadarSnapshot: Equatable {
    public let target: TrackedAccessPoint
    public let rawRSSI: Int?
    public let smoothedRSSI: Double?
    public let trend: SignalTrend
    public let lastSeenAt: Date?

    public init(
        target: TrackedAccessPoint,
        rawRSSI: Int? = nil,
        smoothedRSSI: Double? = nil,
        trend: SignalTrend = .measuring,
        lastSeenAt: Date? = nil
    ) {
        self.target = target
        self.rawRSSI = rawRSSI
        self.smoothedRSSI = smoothedRSSI
        self.trend = trend
        self.lastSeenAt = lastSeenAt
    }
}

public struct APRadarLostSnapshot: Equatable {
    public let target: TrackedAccessPoint
    public let lastRSSI: Double?
    public let lastSeenAt: Date

    public init(target: TrackedAccessPoint, lastRSSI: Double?, lastSeenAt: Date) {
        self.target = target
        self.lastRSSI = lastRSSI
        self.lastSeenAt = lastSeenAt
    }
}

/// AP option surfaced by the selection sheet.
public struct APRadarAPOption: Identifiable, Equatable {
    public let id: String
    public let ssid: String?
    public let bssid: String
    public let rssi: Int
    public let channel: Int
    public let band: ChannelBand

    public init(observation: WiFiNetworkObservation) {
        id = observation.id
        if let ssid = observation.ssid, !ssid.isEmpty {
            self.ssid = ssid
        } else {
            self.ssid = nil
        }
        bssid = observation.bssid
        rssi = observation.rssi
        channel = observation.channel.channelNumber
        band = observation.channel.band
    }
}

extension APRadarState {
    public var isSignalLost: Bool {
        if case .signalLost = self { return true }
        return false
    }

    public var isTracking: Bool {
        if case .tracking = self { return true }
        return false
    }
}
