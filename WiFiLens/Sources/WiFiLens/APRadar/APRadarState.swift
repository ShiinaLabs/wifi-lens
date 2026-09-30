import Foundation
import WiFiLensCore

/// Access point tracked by AP Radar. Identity is exclusively the BSSID;
/// SSID, channel, and band are presentation metadata refreshed from the
/// latest scan results.
struct TrackedAccessPoint: Equatable, Sendable {
    let bssid: String
    var currentSSID: String?
    var channel: Int?
    var band: ChannelBand?

    init(bssid: String, currentSSID: String?, channel: Int?, band: ChannelBand?) {
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
    static func normalizedBSSID(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .uppercased()
    }
}

/// Relative signal trend derived from smoothed RSSI samples.
enum SignalTrend: Equatable, Sendable {
    case measuring
    case gettingCloser
    case stable
    case movingAway
}

/// Current AP Radar session state. Single source of truth; the UI switches
/// on this instead of a set of interlocked booleans.
enum APRadarState: Equatable {
    case idle
    case tracking(APRadarSnapshot)
    case signalLost(APRadarLostSnapshot)
}

struct APRadarSnapshot: Equatable {
    let target: TrackedAccessPoint
    let rawRSSI: Int?
    let smoothedRSSI: Double?
    let trend: SignalTrend
    let lastSeenAt: Date?

    init(
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

struct APRadarLostSnapshot: Equatable {
    let target: TrackedAccessPoint
    let lastRSSI: Double?
    let lastSeenAt: Date
}

/// AP option surfaced by the selection sheet.
struct APRadarAPOption: Identifiable, Equatable {
    let id: String
    let ssid: String?
    let bssid: String
    let rssi: Int
    let channel: Int
    let band: ChannelBand

    init(observation: WiFiNetworkObservation) {
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
    var isSignalLost: Bool {
        if case .signalLost = self { return true }
        return false
    }

    var isTracking: Bool {
        if case .tracking = self { return true }
        return false
    }
}
