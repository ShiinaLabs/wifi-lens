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

/// A trusted access-point ownership interval used for chart background fills.
/// It deliberately contains no RSSI data: measurement continuity is rendered
/// independently from connection ownership.
public struct RoamingRegionInterval: Equatable, Sendable {
    public let bssid: String
    public var startTime: Date
    public var endTime: Date

    public init(bssid: String, startTime: Date, endTime: Date) {
        self.bssid = bssid
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Computes chart fill intervals from trusted segment ownership and confirmed
/// transitions. RSSI sample gaps do not shorten an ownership interval, while
/// unconfirmed gaps between segments remain unfilled.
public enum RoamingRegionLayout {
    public static func intervals(
        segments: [RoamingSegment],
        transitions: [APTransitionEvent],
        openSegmentEnd: Date? = nil
    ) -> [RoamingRegionInterval] {
        guard !segments.isEmpty else { return [] }

        var intervals = segments.enumerated().map { index, segment in
            let measuredEnd = segment.samples.map(\.timestamp).max() ?? segment.startTime
            let proposedEnd: Date
            if index == segments.count - 1, segment.endTime == nil, let openSegmentEnd {
                proposedEnd = max(segment.startTime, openSegmentEnd)
            } else {
                proposedEnd = max(segment.startTime, segment.endTime ?? measuredEnd)
            }
            return RoamingRegionInterval(
                bssid: segment.bssid,
                startTime: segment.startTime,
                endTime: proposedEnd
            )
        }

        guard intervals.count > 1 else { return intervals }
        for index in 0..<(intervals.count - 1) {
            let previousSegment = segments[index]
            let nextSegment = segments[index + 1]
            let transition = transitions.first { event in
                event.fromBSSID == previousSegment.bssid
                    && event.toBSSID == nextSegment.bssid
                    && event.timestamp >= previousSegment.startTime
                    && event.timestamp <= intervals[index + 1].endTime
            }

            if let transition {
                // The recorded event timestamp is the one shared boundary for
                // both fills; the underlying segment/sample timestamps remain
                // unchanged.
                intervals[index].endTime = transition.timestamp
                intervals[index + 1].startTime = transition.timestamp
            } else if intervals[index].endTime > intervals[index + 1].startTime {
                // Conflicting ranges without a confirmed transition cannot be
                // painted as overlapping AP ownership.
                intervals[index].endTime = intervals[index + 1].startTime
            }
        }

        return intervals.filter { $0.endTime >= $0.startTime }
    }
}
