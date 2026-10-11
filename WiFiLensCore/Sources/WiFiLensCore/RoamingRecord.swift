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

/// Converts timestamps and visible time windows into a single chart coordinate
/// system. Pixel alignment is applied once to each shared time boundary so a
/// region edge and its transition marker cannot round independently.
public struct RoamingChartTimeScale: Sendable {
    public let origin: Date

    public init(origin: Date) {
        self.origin = origin
    }

    public func elapsedTime(for timestamp: Date) -> TimeInterval {
        Self.displayedElapsedTime(for: timestamp, sessionStart: origin)
    }

    public static func displayedElapsedTime(for timestamp: Date, sessionStart: Date) -> TimeInterval {
        floor(max(0, timestamp.timeIntervalSince(sessionStart)))
    }

    public func xPosition(
        for elapsedTime: TimeInterval,
        visibleStart: TimeInterval,
        visibleDuration: TimeInterval,
        plotLeft: CGFloat,
        plotWidth: CGFloat,
        displayScale: CGFloat
    ) -> CGFloat {
        let duration = max(0.001, visibleDuration)
        let rawX = plotLeft + CGFloat((elapsedTime - visibleStart) / duration) * plotWidth
        let scale = max(1, displayScale)
        return (rawX * scale).rounded() / scale
    }
}

public enum RoamingChartBoundaryEvidence: Equatable, Sendable {
    case segmentObservation
    case confirmedTransition(eventIndex: Int)
}

public struct RoamingChartRegion: Equatable, Sendable {
    public let segmentIndex: Int
    public let bssid: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var startEvidence: RoamingChartBoundaryEvidence
    public var endEvidence: RoamingChartBoundaryEvidence
}

public struct RoamingChartSamplePoint {
    public let elapsedTime: TimeInterval
    public let sample: RoamingSample
}

public struct RoamingSignalRun {
    public let segmentIndex: Int
    public let bssid: String
    public let points: [RoamingChartSamplePoint]
}

/// A visual-only extension of a measured area to a confirmed AP transition.
/// It never participates in signal runs or persisted measurements.
public struct RoamingSignalAreaExtension: Equatable, Sendable {
    public let segmentIndex: Int
    public let eventIndex: Int
    public let bssid: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let anchorRSSI: Int
}

public struct RoamingChartTransition {
    public let elapsedTime: TimeInterval
    public let eventIndex: Int
    public let fromSegmentIndex: Int
    public let toSegmentIndex: Int
    public let event: APTransitionEvent
}

public struct RoamingChartGap: Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let previousSegmentIndex: Int?
    public let nextSegmentIndex: Int?
}

/// Immutable, persistence-independent rendering input for all roaming charts.
/// It resolves timestamps and event-to-segment relationships before drawing.
public struct RoamingChartScene {
    public let origin: Date
    public let duration: TimeInterval
    public let regions: [RoamingChartRegion]
    public let signalRuns: [RoamingSignalRun]
    public let signalAreaExtensions: [RoamingSignalAreaExtension]
    public let transitions: [RoamingChartTransition]
    public let gaps: [RoamingChartGap]
    public let samples: [RoamingChartSamplePoint]

    public init(
        segments: [RoamingSegment],
        transitions sourceTransitions: [APTransitionEvent],
        duration requestedDuration: TimeInterval,
        origin requestedOrigin: Date? = nil
    ) {
        let timestamps = segments.flatMap { segment in
            [segment.startTime, segment.endTime].compactMap { $0 } + segment.samples.map(\.timestamp)
        } + sourceTransitions.map(\.timestamp)
        let origin = requestedOrigin ?? timestamps.min() ?? Date(timeIntervalSince1970: 0)
        self.origin = origin
        let timeScale = RoamingChartTimeScale(origin: origin)
        func elapsed(_ timestamp: Date) -> TimeInterval { timeScale.elapsedTime(for: timestamp) }

        let segmentEnds = segments.map { segment -> Date in
            let lastSample = segment.samples.map(\.timestamp).max() ?? segment.startTime
            return max(segment.startTime, max(segment.endTime ?? lastSample, lastSample))
        }

        let orderedEvents = sourceTransitions.enumerated().sorted {
            if $0.element.timestamp == $1.element.timestamp { return $0.offset < $1.offset }
            return $0.element.timestamp < $1.element.timestamp
        }
        var consumedEventIndices = Set<Int>()
        var matchedByPair: [Int: (eventIndex: Int, event: APTransitionEvent)] = [:]
        var lastMatchedTimestamp: Date?

        if segments.count > 1 {
            for leftIndex in 0..<(segments.count - 1) {
                let left = segments[leftIndex]
                let right = segments[leftIndex + 1]
                let candidates = orderedEvents.filter { indexedEvent in
                    let event = indexedEvent.element
                    return !consumedEventIndices.contains(indexedEvent.offset)
                        && event.fromBSSID == left.bssid
                        && event.toBSSID == right.bssid
                        && event.timestamp >= left.startTime
                        && event.timestamp <= right.startTime
                        && (lastMatchedTimestamp.map { event.timestamp >= $0 } ?? true)
                }

                guard candidates.count == 1, let candidate = candidates.first else { continue }
                consumedEventIndices.insert(candidate.offset)
                matchedByPair[leftIndex] = (candidate.offset, candidate.element)
                lastMatchedTimestamp = candidate.element.timestamp
            }
        }

        var regions = segments.enumerated().map { index, segment in
            let start = elapsed(segment.startTime)
            let end = elapsed(segmentEnds[index])
            return RoamingChartRegion(
                segmentIndex: index,
                bssid: segment.bssid,
                start: start,
                end: max(start, end),
                startEvidence: .segmentObservation,
                endEvidence: .segmentObservation
            )
        }

        var resolvedTransitions: [RoamingChartTransition] = []
        for (leftIndex, match) in matchedByPair {
            let boundary = elapsed(match.event.timestamp)
            regions[leftIndex].end = boundary
            regions[leftIndex].endEvidence = .confirmedTransition(eventIndex: match.eventIndex)
            regions[leftIndex + 1].start = boundary
            regions[leftIndex + 1].startEvidence = .confirmedTransition(eventIndex: match.eventIndex)
            resolvedTransitions.append(RoamingChartTransition(
                elapsedTime: boundary,
                eventIndex: match.eventIndex,
                fromSegmentIndex: leftIndex,
                toSegmentIndex: leftIndex + 1,
                event: match.event
            ))
        }

        if regions.count > 1 {
            for index in 0..<(regions.count - 1) where matchedByPair[index] == nil {
                if regions[index].end > regions[index + 1].start {
                    regions[index].end = regions[index + 1].start
                }
            }
        }
        self.regions = regions.filter { $0.end >= $0.start }
        self.transitions = resolvedTransitions.sorted { $0.elapsedTime < $1.elapsedTime }

        let signalRuns = segments.enumerated().flatMap { segmentIndex, segment in
            segment.rssiRuns.map { run in
                RoamingSignalRun(segmentIndex: segmentIndex, bssid: segment.bssid, points: run.map { sample in
                    RoamingChartSamplePoint(
                        elapsedTime: elapsed(sample.timestamp),
                        sample: sample
                    )
                })
            }
        }
        self.signalRuns = signalRuns
        self.signalAreaExtensions = resolvedTransitions.flatMap { transition -> [RoamingSignalAreaExtension] in
            let previousPoint = signalRuns
                .filter { $0.segmentIndex == transition.fromSegmentIndex }
                .flatMap(\.points)
                .filter { $0.sample.rssi != nil }
                .max { $0.elapsedTime < $1.elapsedTime }
            let nextPoint = signalRuns
                .filter { $0.segmentIndex == transition.toSegmentIndex }
                .flatMap(\.points)
                .filter { $0.sample.rssi != nil }
                .min { $0.elapsedTime < $1.elapsedTime }

            var extensions: [RoamingSignalAreaExtension] = []
            if let previousPoint, let rssi = previousPoint.sample.rssi,
               previousPoint.elapsedTime < transition.elapsedTime {
                extensions.append(RoamingSignalAreaExtension(
                    segmentIndex: transition.fromSegmentIndex,
                    eventIndex: transition.eventIndex,
                    bssid: transition.event.fromBSSID,
                    start: previousPoint.elapsedTime,
                    end: transition.elapsedTime,
                    anchorRSSI: rssi
                ))
            }
            if let nextPoint, let rssi = nextPoint.sample.rssi,
               nextPoint.elapsedTime > transition.elapsedTime {
                extensions.append(RoamingSignalAreaExtension(
                    segmentIndex: transition.toSegmentIndex,
                    eventIndex: transition.eventIndex,
                    bssid: transition.event.toBSSID,
                    start: transition.elapsedTime,
                    end: nextPoint.elapsedTime,
                    anchorRSSI: rssi
                ))
            }
            return extensions
        }.sorted {
            if $0.start == $1.start { return $0.segmentIndex < $1.segmentIndex }
            return $0.start < $1.start
        }
        self.samples = segments.flatMap(\.samples).map { sample in
            RoamingChartSamplePoint(elapsedTime: elapsed(sample.timestamp), sample: sample)
        }.sorted { $0.elapsedTime < $1.elapsedTime }

        var gaps: [RoamingChartGap] = []
        var cursor: TimeInterval = 0
        var previousSegmentIndex: Int?
        for region in self.regions {
            if region.start > cursor {
                gaps.append(RoamingChartGap(
                    start: cursor,
                    end: region.start,
                    previousSegmentIndex: previousSegmentIndex,
                    nextSegmentIndex: region.segmentIndex
                ))
            }
            cursor = max(cursor, region.end)
            previousSegmentIndex = region.segmentIndex
        }

        let latestEvidence = max(0, timestamps.map(elapsed).max() ?? 0)
        self.duration = max(0, max(requestedDuration, latestEvidence))
        if self.duration > cursor {
            gaps.append(RoamingChartGap(
                start: cursor,
                end: self.duration,
                previousSegmentIndex: previousSegmentIndex,
                nextSegmentIndex: nil
            ))
        }
        self.gaps = gaps
    }
}
