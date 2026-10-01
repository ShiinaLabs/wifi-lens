import Foundation
import Darwin
import Logging

private let throughputLogger = Logger(label: "throughput")

public struct ThroughputSample: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let rateIn: Double   // bytes/sec
    public let rateOut: Double  // bytes/sec

    public init(id: UUID = UUID(), timestamp: Date, bytesIn: UInt64, bytesOut: UInt64, rateIn: Double, rateOut: Double) {
        self.id = id
        self.timestamp = timestamp
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.rateIn = rateIn
        self.rateOut = rateOut
    }
}

@MainActor
@Observable
public final class ThroughputMonitor {
    public private(set) var perInterface: [String: [ThroughputSample]] = [:]
    public private(set) var isRunning = false
    private var lastCounters: [String: (in: UInt64, out: UInt64, ts: Date)] = [:]
    private var pollTask: Task<Void, Never>?
    private let now: () -> Date
    private let pollInterval: Duration

    static let maxSamples = 90          // retain 90 s
    private static let cleanupInterval = 60  // purge stale ifaces every 60 polls
    private var pollCount = 0

    /// Creates a throughput monitor.
    /// - Parameters:
    ///   - now: Clock used for sample timestamps and staleness checks. Defaults to `Date()`.
    ///   - pollInterval: Delay between polling loop iterations. Defaults to 1 second.
    public init(now: @escaping () -> Date = { Date() }, pollInterval: Duration = .seconds(1)) {
        self.now = now
        self.pollInterval = pollInterval
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        pollCount = 0
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                sample()
                pollCount += 1
                if pollCount % Self.cleanupInterval == 0 {
                    purgeStaleInterfaces()
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
        throughputLogger.info("started")
    }

    public func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        lastCounters.removeAll()
        perInterface.removeAll()
        throughputLogger.info("stopped")
    }

    public func samples(for name: String) -> [ThroughputSample] {
        perInterface[name] ?? []
    }

    /// Drops interfaces whose newest sample is older than 2 minutes.
    /// Internal so tests can invoke staleness purging deterministically.
    func purgeStaleInterfaces() {
        let now = self.now()
        perInterface = perInterface.filter { _, history in
            guard let last = history.last else { return false }
            return now.timeIntervalSince(last.timestamp) < 120  // gone for 2 min → drop
        }
    }

    /// Interfaces that have generated non-zero traffic
    public var activeInterfaces: [String] {
        perInterface.compactMap { name, samples in
            samples.contains(where: { $0.rateIn > 0 || $0.rateOut > 0 }) ? name : nil
        }
    }

    private func sample() {
        var addrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPtr) == 0, let first = addrPtr else { return }
        defer { freeifaddrs(first) }

        let now = self.now()

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let namePtr = ptr.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)

            // Only capture real hardware interfaces with byte counters
            guard let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let bytesIn = UInt64(data.pointee.ifi_ibytes)
            let bytesOut = UInt64(data.pointee.ifi_obytes)

            let prev = lastCounters[name]
            let elapsed = prev.map { now.timeIntervalSince($0.ts) } ?? 1.0
            let deltaIn  = prev.map { max(0, Double(Int64(bytesIn) - Int64($0.in)))   / max(0.1, elapsed) } ?? 0
            let deltaOut = prev.map { max(0, Double(Int64(bytesOut) - Int64($0.out))) / max(0.1, elapsed) } ?? 0

            lastCounters[name] = (in: bytesIn, out: bytesOut, ts: now)

            let sample = ThroughputSample(
                timestamp: now,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                rateIn: max(0, deltaIn),
                rateOut: max(0, deltaOut)
            )

            appendSample(sample, for: name)
        }
    }

    /// Appends a sample to an interface's history, trimming the oldest entries
    /// once the retained window exceeds `maxSamples`. Internal for tests.
    func appendSample(_ sample: ThroughputSample, for name: String) {
        var history = perInterface[name] ?? []
        history.append(sample)
        if history.count > Self.maxSamples {
            history = Array(history.suffix(Self.maxSamples))
        }
        perInterface[name] = history
    }
}
