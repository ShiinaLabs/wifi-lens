import Foundation

public struct RoamingSample: Identifiable, Codable {
    public let id = UUID()
    public let timestamp: Date
    public let rssi: Int?
    public let channel: Int?
    public let txRate: Double?
    public var gatewayLatency: Double?

    public init(timestamp: Date, rssi: Int?, channel: Int?, txRate: Double?, gatewayLatency: Double? = nil) {
        self.timestamp = timestamp
        self.rssi = rssi
        self.channel = channel
        self.txRate = txRate
        self.gatewayLatency = gatewayLatency
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, rssi, channel, txRate, gatewayLatency
    }
}

public struct RoamingSegment: Identifiable, Codable {
    public let id = UUID()
    public let bssid: String
    public let startTime: Date
    public var endTime: Date?
    public var samples: [RoamingSample] = []

    public init(bssid: String, startTime: Date, endTime: Date? = nil, samples: [RoamingSample] = []) {
        self.bssid = bssid
        self.startTime = startTime
        self.endTime = endTime
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey {
        case bssid, startTime, endTime, samples
    }

    public var rssiRange: (min: Int, max: Int) {
        let values = samples.compactMap(\.rssi)
        guard !values.isEmpty else { return (-100, -30) }
        return (values.min() ?? -100, values.max() ?? -30)
    }

    /// Consecutive runs of samples with measured RSSI. Missing samples split
    /// the signal line so charts never imply an unobserved measurement.
    public var rssiRuns: [[RoamingSample]] {
        var runs: [[RoamingSample]] = []
        var current: [RoamingSample] = []
        for sample in samples {
            if sample.rssi != nil {
                current.append(sample)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    public var duration: TimeInterval {
        let end = endTime ?? samples.last?.timestamp ?? startTime
        return end.timeIntervalSince(startTime)
    }
}

public struct APTransitionEvent: Identifiable, Codable {
    public let id = UUID()
    public let timestamp: Date
    public let fromBSSID: String
    public let toBSSID: String
    public let rssiBefore: Int?
    public let rssiAfter: Int?
    public let channelBefore: Int?
    public let channelAfter: Int?

    public init(
        timestamp: Date,
        fromBSSID: String,
        toBSSID: String,
        rssiBefore: Int?,
        rssiAfter: Int?,
        channelBefore: Int?,
        channelAfter: Int?
    ) {
        self.timestamp = timestamp
        self.fromBSSID = fromBSSID
        self.toBSSID = toBSSID
        self.rssiBefore = rssiBefore
        self.rssiAfter = rssiAfter
        self.channelBefore = channelBefore
        self.channelAfter = channelAfter
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, fromBSSID, toBSSID, rssiBefore, rssiAfter, channelBefore, channelAfter
    }
}
