import Foundation
import Testing
@testable import WiFiLensCore

@Suite("ThroughputMonitor")
@MainActor
struct ThroughputMonitorTests {

    /// Deterministic clock whose `now` can be advanced by tests.
    @MainActor
    private final class TestClock {
        var now = Date(timeIntervalSince1970: 1_000_000)

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    // MARK: - Fixtures

    private func makeMonitor(
        clock: TestClock,
        pollInterval: Duration = .seconds(1)
    ) -> ThroughputMonitor {
        ThroughputMonitor(now: { clock.now }, pollInterval: pollInterval)
    }

    private func sample(
        timestamp: Date = Date(timeIntervalSince1970: 0),
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0,
        rateIn: Double = 0,
        rateOut: Double = 0
    ) -> ThroughputSample {
        ThroughputSample(
            timestamp: timestamp,
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            rateIn: rateIn,
            rateOut: rateOut
        )
    }

    // MARK: - Lifecycle

    @Test("start flips isRunning; stop clears all sampled state")
    func startStopLifecycle() {
        let monitor = makeMonitor(clock: TestClock())
        #expect(monitor.isRunning == false)

        monitor.start()
        #expect(monitor.isRunning == true)

        // Repeated start is a no-op while already running.
        monitor.start()
        #expect(monitor.isRunning == true)

        monitor.stop()
        #expect(monitor.isRunning == false)
        #expect(monitor.perInterface.isEmpty)
        #expect(monitor.samples(for: "en0").isEmpty)
    }

    // MARK: - Sample trimming

    @Test("history is trimmed to the newest 90 samples")
    func sampleHistoryTrimmedToNewest90() {
        let monitor = makeMonitor(clock: TestClock())
        #expect(ThroughputMonitor.maxSamples == 90)

        for index in 0..<95 {
            monitor.appendSample(
                sample(timestamp: Date(timeIntervalSince1970: TimeInterval(index)), rateIn: Double(index)),
                for: "en0"
            )
        }

        let samples = monitor.samples(for: "en0")
        #expect(samples.count == 90)
        #expect(samples.first?.rateIn == 5)   // indexes 0...4 dropped as the oldest
        #expect(samples.last?.rateIn == 94)   // newest sample retained
    }

    // MARK: - Stale interface purging

    @Test("purge drops interfaces whose newest sample is older than 2 minutes")
    func purgeStaleInterfacesDropsInactive() {
        let clock = TestClock()
        let monitor = makeMonitor(clock: clock)

        // Active: newest sample is now.
        monitor.appendSample(sample(timestamp: clock.now), for: "en0")
        // Stale: newest sample is 121 s old → interface dropped.
        monitor.appendSample(sample(timestamp: clock.now.addingTimeInterval(-121)), for: "en1")
        // Boundary: 119 s old → still within the 2-minute window.
        monitor.appendSample(sample(timestamp: clock.now.addingTimeInterval(-119)), for: "en2")

        monitor.purgeStaleInterfaces()

        #expect(monitor.samples(for: "en0").count == 1)
        #expect(monitor.samples(for: "en1").isEmpty)
        #expect(monitor.samples(for: "en2").count == 1)
    }

    // MARK: - Active interfaces

    @Test("activeInterfaces only lists interfaces with non-zero rates")
    func activeInterfacesFiltersZeroTraffic() {
        let monitor = makeMonitor(clock: TestClock())
        monitor.appendSample(sample(rateIn: 100, rateOut: 0), for: "en0")
        monitor.appendSample(sample(rateIn: 0, rateOut: 0), for: "en1")

        #expect(monitor.activeInterfaces == ["en0"])
    }
}
