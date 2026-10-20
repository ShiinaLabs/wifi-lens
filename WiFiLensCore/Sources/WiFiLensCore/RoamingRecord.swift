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

public struct RoamingChartHoverSample {
    public let bssid: String
    public let point: RoamingChartSamplePoint
}

public struct RoamingSignalRun {
    public let segmentIndex: Int
    public let bssid: String
    public let points: [RoamingChartSamplePoint]
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
    private static let maximumHandoffCollapseSpan: TimeInterval = 1.5

    public let origin: Date
    public let duration: TimeInterval
    public let regions: [RoamingChartRegion]
    public let signalRuns: [RoamingSignalRun]
    public let transitions: [RoamingChartTransition]
    public let gaps: [RoamingChartGap]
    public let samples: [RoamingChartSamplePoint]

    private struct CollapsedInterval {
        let start: TimeInterval
        let end: TimeInterval
    }

    private static func collapsedIntervals(
        segments: [RoamingSegment],
        transitions: [RoamingChartTransition],
        timeScale: RoamingChartTimeScale
    ) -> [CollapsedInterval] {
        func isWithinSegment(_ timestamp: Date, _ segment: RoamingSegment) -> Bool {
            guard timestamp >= segment.startTime else { return false }
            if let endTime = segment.endTime, timestamp > endTime { return false }
            return true
        }

        func samplesAreStrictlyIncreasing(_ samples: [RoamingSample]) -> Bool {
            zip(samples, samples.dropFirst()).allSatisfy { previous, next in
                previous.timestamp < next.timestamp
            }
        }

        let orderedTransitions = transitions.sorted {
            if $0.event.timestamp == $1.event.timestamp { return $0.eventIndex < $1.eventIndex }
            return $0.event.timestamp < $1.event.timestamp
        }
        var consumedEventIndices = Set<Int>()
        var accepted: [(eventIndex: Int, rawStart: Date, rawEnd: Date, interval: CollapsedInterval)] = []

        for transition in orderedTransitions {
            guard consumedEventIndices.insert(transition.eventIndex).inserted,
                segments.indices.contains(transition.fromSegmentIndex),
                segments.indices.contains(transition.toSegmentIndex)
            else {
                continue
            }

            let previousSegment = segments[transition.fromSegmentIndex]
            let nextSegment = segments[transition.toSegmentIndex]
            let boundary = transition.event.timestamp

            guard samplesAreStrictlyIncreasing(previousSegment.samples),
                samplesAreStrictlyIncreasing(nextSegment.samples),
                let previousSample = previousSegment.samples.last(where: {
                    $0.timestamp <= boundary
                        && $0.rssi != nil
                        && isWithinSegment($0.timestamp, previousSegment)
                }),
                let nextSample = nextSegment.samples.first(where: {
                    $0.timestamp >= boundary
                        && $0.rssi != nil
                        && isWithinSegment($0.timestamp, nextSegment)
                })
            else {
                continue
            }

            let start = previousSample.timestamp
            let end = nextSample.timestamp
            let beforeSpan = boundary.timeIntervalSince(start)
            let afterSpan = end.timeIntervalSince(boundary)
            let totalSpan = end.timeIntervalSince(start)
            guard start < boundary,
                boundary <= end,
                beforeSpan <= maximumHandoffCollapseSpan,
                afterSpan <= maximumHandoffCollapseSpan,
                totalSpan <= maximumHandoffCollapseSpan
            else {
                continue
            }

            let previousEvidence = previousSegment.samples.filter {
                $0.timestamp >= start && $0.timestamp <= boundary
            }
            let nextEvidence = nextSegment.samples.filter {
                $0.timestamp >= boundary && $0.timestamp <= end
            }
            guard !previousEvidence.isEmpty,
                !nextEvidence.isEmpty,
                previousEvidence.allSatisfy({
                    $0.rssi != nil && isWithinSegment($0.timestamp, previousSegment)
                }),
                nextEvidence.allSatisfy({
                    $0.rssi != nil && isWithinSegment($0.timestamp, nextSegment)
                }),
                !nextSegment.samples.contains(where: {
                    $0.timestamp >= start && $0.timestamp < boundary
                }),
                !previousSegment.samples.contains(where: {
                    $0.timestamp > boundary && $0.timestamp <= end
                }),
                !segments.enumerated().contains(where: { index, segment in
                    index != transition.fromSegmentIndex
                        && index != transition.toSegmentIndex
                        && segment.samples.contains(where: { $0.timestamp >= start && $0.timestamp <= end })
                })
            else {
                continue
            }

            let interval = CollapsedInterval(
                start: timeScale.elapsedTime(for: start),
                end: timeScale.elapsedTime(for: boundary)
            )
            guard interval.start < interval.end,
                interval.end - interval.start <= maximumHandoffCollapseSpan,
                accepted.last.map({ start >= $0.rawEnd && interval.start >= $0.interval.end }) ?? true
            else {
                continue
            }
            accepted.append((transition.eventIndex, start, boundary, interval))
        }

        return accepted.map(\.interval)
    }

    /// Returns every real sample at the nearest displayed timestamp so hover
    /// can highlight both sides of a confirmed handoff when their X positions
    /// have been collapsed to the same chart coordinate.
    public func hoverSamples(near elapsedTime: TimeInterval) -> [RoamingChartHoverSample] {
        let measuredSamples = signalRuns.flatMap { run in
            run.points.map { RoamingChartHoverSample(bssid: run.bssid, point: $0) }
        }
        guard
            let nearest = measuredSamples.min(by: {
                abs($0.point.elapsedTime - elapsedTime) < abs($1.point.elapsedTime - elapsedTime)
            })
        else {
            return []
        }

        let sharedXTimeTolerance: TimeInterval = 0.000_001
        return measuredSamples.filter {
            abs($0.point.elapsedTime - nearest.point.elapsedTime) <= sharedXTimeTolerance
        }
    }

    public init(
        segments: [RoamingSegment],
        transitions sourceTransitions: [APTransitionEvent],
        duration requestedDuration: TimeInterval,
        origin requestedOrigin: Date? = nil
    ) {
        let timestamps =
            segments.flatMap { segment in
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
            resolvedTransitions.append(
                RoamingChartTransition(
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
        let signalRuns = segments.enumerated().flatMap { segmentIndex, segment in
            segment.rssiRuns.map { run in
                RoamingSignalRun(
                    segmentIndex: segmentIndex, bssid: segment.bssid,
                    points: run.map { sample in
                        RoamingChartSamplePoint(
                            elapsedTime: elapsed(sample.timestamp),
                            sample: sample
                        )
                    })
            }
        }
        let collapsedIntervals = Self.collapsedIntervals(
            segments: segments,
            transitions: resolvedTransitions,
            timeScale: timeScale
        )

        func displayedTime(_ elapsed: TimeInterval) -> TimeInterval {
            var removedDuration: TimeInterval = 0
            for interval in collapsedIntervals {
                if elapsed <= interval.start { break }
                if elapsed < interval.end {
                    removedDuration += elapsed - interval.start
                    break
                }
                removedDuration += interval.end - interval.start
            }
            return max(0, elapsed - removedDuration)
        }

        self.regions = regions.compactMap { region in
            var displayed = region
            displayed.start = displayedTime(region.start)
            displayed.end = displayedTime(region.end)
            return displayed.end >= displayed.start ? displayed : nil
        }
        self.transitions = resolvedTransitions.map { transition in
            RoamingChartTransition(
                elapsedTime: displayedTime(transition.elapsedTime),
                eventIndex: transition.eventIndex,
                fromSegmentIndex: transition.fromSegmentIndex,
                toSegmentIndex: transition.toSegmentIndex,
                event: transition.event
            )
        }.sorted {
            if $0.elapsedTime == $1.elapsedTime {
                if $0.event.timestamp == $1.event.timestamp { return $0.eventIndex < $1.eventIndex }
                return $0.event.timestamp < $1.event.timestamp
            }
            return $0.elapsedTime < $1.elapsedTime
        }
        self.signalRuns = signalRuns.map { run in
            RoamingSignalRun(
                segmentIndex: run.segmentIndex,
                bssid: run.bssid,
                points: run.points.map { point in
                    RoamingChartSamplePoint(elapsedTime: displayedTime(point.elapsedTime), sample: point.sample)
                }
            )
        }
        self.samples = segments.flatMap(\.samples).map { sample in
            RoamingChartSamplePoint(elapsedTime: displayedTime(elapsed(sample.timestamp)), sample: sample)
        }.sorted {
            if $0.elapsedTime == $1.elapsedTime { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.elapsedTime < $1.elapsedTime
        }

        var gaps: [RoamingChartGap] = []
        var cursor: TimeInterval = 0
        var previousSegmentIndex: Int?
        for region in self.regions {
            if region.start > cursor {
                gaps.append(
                    RoamingChartGap(
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
        self.duration = max(0, displayedTime(max(requestedDuration, latestEvidence)))
        if self.duration > cursor {
            gaps.append(
                RoamingChartGap(
                    start: cursor,
                    end: self.duration,
                    previousSegmentIndex: previousSegmentIndex,
                    nextSegmentIndex: nil
                ))
        }
        self.gaps = gaps
    }
}
