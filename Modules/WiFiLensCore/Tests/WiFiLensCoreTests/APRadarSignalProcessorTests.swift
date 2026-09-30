import Foundation
import Testing
@testable import WiFiLensCore

// MARK: - RSSI smoothing

@Suite("APRadarSignalProcessor RSSI smoothing")
struct APRadarSignalProcessorSmoothingTests {

    @Test("first valid sample becomes the smoothed value directly")
    func firstSampleBecomesBaseline() {
        var processor = APRadarSignalProcessor()
        let date = Date(timeIntervalSince1970: 100)

        let result = processor.ingest(rawRSSI: -60, at: date)

        #expect(result == -60)
        #expect(processor.smoothedRSSI == -60)
        #expect(processor.rawRSSI == -60)
        #expect(processor.sampleCount == 1)
    }

    @Test("subsequent samples update with alpha 0.30")
    func emaUsesAlphaPointThree() {
        var processor = APRadarSignalProcessor()
        let date = Date(timeIntervalSince1970: 100)

        _ = processor.ingest(rawRSSI: -60, at: date)
        let result = processor.ingest(rawRSSI: -50, at: date.addingTimeInterval(1))

        // 0.30 * (-50) + 0.70 * (-60) = -57
        #expect(abs((result ?? .nan) - (-57)) < 0.0001)
        #expect(abs((processor.smoothedRSSI ?? .nan) - (-57)) < 0.0001)
    }

    @Test("invalid RSSI values are ignored")
    func invalidSamplesAreIgnored() {
        var processor = APRadarSignalProcessor()
        let date = Date(timeIntervalSince1970: 100)

        #expect(processor.ingest(rawRSSI: 5, at: date) == nil)
        #expect(processor.ingest(rawRSSI: -101, at: date) == nil)
        #expect(processor.ingest(rawRSSI: -1000, at: date) == nil)
        #expect(processor.rawRSSI == nil)
        #expect(processor.smoothedRSSI == nil)
        #expect(processor.sampleCount == 0)

        _ = processor.ingest(rawRSSI: -70, at: date)
        let invalidFollowUp = processor.ingest(rawRSSI: 5, at: date.addingTimeInterval(1))
        #expect(invalidFollowUp == nil)
        // State unchanged after the rejected sample.
        #expect(processor.smoothedRSSI == -70)
        #expect(processor.sampleCount == 1)
    }

    @Test("reset clears state so the next sample does not inherit the old value")
    func resetDoesNotInherit() {
        var processor = APRadarSignalProcessor()
        let date = Date(timeIntervalSince1970: 100)

        _ = processor.ingest(rawRSSI: -60, at: date)
        _ = processor.ingest(rawRSSI: -50, at: date.addingTimeInterval(1))

        processor.reset()

        #expect(processor.smoothedRSSI == nil)
        #expect(processor.rawRSSI == nil)
        #expect(processor.sampleCount == 0)

        let firstAfterReset = processor.ingest(rawRSSI: -80, at: date.addingTimeInterval(2))
        #expect(firstAfterReset == -80)
    }
}

// MARK: - Interval mapping

@Suite("APRadarPulseInterval mapping")
struct APRadarPulseIntervalTests {

    @Test("all anchor points map to their specified intervals")
    func anchorPoints() {
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -42) == 0.35)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -50) == 0.55)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -60) == 0.90)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -70) == 1.40)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -80) == 2.00)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -90) == 2.60)
    }

    @Test("midpoints interpolate linearly between anchors")
    func interpolation() {
        #expect(abs(APRadarPulseInterval.intervalSeconds(forRSSI: -55) - 0.725) < 0.0001)
        #expect(abs(APRadarPulseInterval.intervalSeconds(forRSSI: -65) - 1.15) < 0.0001)
        #expect(abs(APRadarPulseInterval.intervalSeconds(forRSSI: -75) - 1.70) < 0.0001)
        // Quarter points.
        #expect(abs(APRadarPulseInterval.intervalSeconds(forRSSI: -52.5) - 0.6375) < 0.0001)
        #expect(abs(APRadarPulseInterval.intervalSeconds(forRSSI: -87) - 2.42) < 0.0001)
    }

    @Test("values beyond the anchors are clamped to the endpoints")
    func clamping() {
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -20) == 0.35)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: 10) == 0.35)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -95) == 2.60)
        #expect(APRadarPulseInterval.intervalSeconds(forRSSI: -200) == 2.60)
    }

    @Test("non-finite input never produces NaN or infinity")
    func nonFiniteInput() {
        let nanResult = APRadarPulseInterval.intervalSeconds(forRSSI: .nan)
        #expect(nanResult.isFinite)
        #expect(nanResult == 2.60)

        let plusInfinity = APRadarPulseInterval.intervalSeconds(forRSSI: .infinity)
        #expect(plusInfinity == 0.35)
        let minusInfinity = APRadarPulseInterval.intervalSeconds(forRSSI: -.infinity)
        #expect(minusInfinity == 2.60)
    }

    @Test("duration form matches seconds form")
    func durationForm() {
        let duration = APRadarPulseInterval.pulseInterval(forRSSI: -55)
        #expect(duration.components.seconds == 0)
        #expect(abs(Double(duration.components.attoseconds) / 1e18 - 0.725) < 0.0001)
    }
}

// MARK: - Signal trend

@Suite("APRadarSignalProcessor trend")
struct APRadarSignalProcessorTrendTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test("getting closer when smoothed signal gains at least 3 dB over 3 seconds")
    func gettingCloser() {
        var processor = APRadarSignalProcessor()
        _ = processor.ingest(rawRSSI: -60, at: t0)
        _ = processor.ingest(rawRSSI: -40, at: t0.addingTimeInterval(3))

        // Smoothed: -60 -> 0.3*(-40) + 0.7*(-60) = -54, delta +6.
        #expect(processor.trend(at: t0.addingTimeInterval(3)) == .gettingCloser)
    }

    @Test("moving away when smoothed signal drops at least 3 dB over 3 seconds")
    func movingAway() {
        var processor = APRadarSignalProcessor()
        _ = processor.ingest(rawRSSI: -50, at: t0)
        _ = processor.ingest(rawRSSI: -70, at: t0.addingTimeInterval(3))

        // Smoothed: -50 -> -56, delta -6.
        #expect(processor.trend(at: t0.addingTimeInterval(3)) == .movingAway)
    }

    @Test("stable when smoothed change is smaller than 3 dB")
    func stable() {
        var processor = APRadarSignalProcessor()
        _ = processor.ingest(rawRSSI: -60, at: t0)
        _ = processor.ingest(rawRSSI: -58, at: t0.addingTimeInterval(3))

        // Smoothed: -60 -> -59.4, delta +0.6.
        #expect(processor.trend(at: t0.addingTimeInterval(3)) == .stable)
    }

    @Test("measuring while history is younger than 2 seconds or absent")
    func measuring() {
        var empty = APRadarSignalProcessor()
        #expect(empty.trend(at: t0) == .measuring)

        var fresh = APRadarSignalProcessor()
        _ = fresh.ingest(rawRSSI: -60, at: t0)
        _ = fresh.ingest(rawRSSI: -50, at: t0.addingTimeInterval(1))
        #expect(fresh.trend(at: t0.addingTimeInterval(1)) == .measuring)
    }

    @Test("trend uses smoothed values, not single raw samples")
    func trendUsesSmoothedValues() {
        var processor = APRadarSignalProcessor()
        _ = processor.ingest(rawRSSI: -60, at: t0)
        // A raw jump of +4 dB would be "getting closer" if raw values were
        // used, but the smoothed delta (+1.2 dB) keeps the trend stable.
        _ = processor.ingest(rawRSSI: -56, at: t0.addingTimeInterval(3))

        let smoothed = processor.smoothedRSSI ?? .nan
        #expect(abs(smoothed - (-58.8)) < 0.0001)
        #expect(processor.trend(at: t0.addingTimeInterval(3)) == .stable)
    }
}

// MARK: - Stochastic Geiger interval

/// Deterministic RNG so the statistical tests are reproducible.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("APRadarPulseInterval stochastic Geiger")
struct APRadarPulseIntervalStochasticTests {

    @Test("draws are finite and clamped to safe bounds")
    func drawsAreFiniteAndClamped() {
        var rng = SeededRandomNumberGenerator(seed: 42)
        for mean in [0.35, 1.0, 2.6] {
            let maximum = max(APRadarPulseInterval.minimumStochasticInterval, mean * 4)
            for _ in 0..<5_000 {
                let draw = APRadarPulseInterval.nextExponentialInterval(mean: mean, using: &rng)
                #expect(draw.isFinite)
                #expect(draw >= APRadarPulseInterval.minimumStochasticInterval)
                #expect(draw <= maximum)
            }
        }
    }

    @Test("sample mean tracks the requested mean within 10 percent")
    func sampleMeanTracksRequestedMean() {
        var rng = SeededRandomNumberGenerator(seed: 7)
        let count = 20_000
        var total = 0.0
        for _ in 0..<count {
            total += APRadarPulseInterval.nextExponentialInterval(mean: 1.0, using: &rng)
        }
        let sampleMean = total / Double(count)
        #expect(abs(sampleMean - 1.0) < 0.1)
    }

    @Test("stronger signals produce a faster average click rate")
    func strongerSignalIsFasterOnAverage() {
        var strongRNG = SeededRandomNumberGenerator(seed: 99)
        var weakRNG = SeededRandomNumberGenerator(seed: 99)
        let count = 8_000

        var strongTotal = 0.0
        var weakTotal = 0.0
        for _ in 0..<count {
            strongTotal += APRadarPulseInterval.nextExponentialInterval(mean: 0.5, using: &strongRNG)
            weakTotal += APRadarPulseInterval.nextExponentialInterval(mean: 2.0, using: &weakRNG)
        }
        let strongMean = strongTotal / Double(count)
        let weakMean = weakTotal / Double(count)
        #expect(strongMean < weakMean)
        // Sanity: each rate is still close to its own mean.
        #expect(abs(strongMean - 0.5) < 0.1)
        #expect(abs(weakMean - 2.0) < 0.25)
    }

    @Test("invalid or non-finite means fall back to the minimum interval")
    func invalidMeanFallsBack() {
        for mean in [Double.nan, Double.infinity, -Double.infinity, 0, -1] {
            let draw = APRadarPulseInterval.nextExponentialInterval(mean: mean)
            #expect(draw == APRadarPulseInterval.minimumStochasticInterval)
        }
    }

    @Test("duration seconds helper matches the duration components")
    func durationSecondsHelper() {
        let duration = Duration.seconds(1) + .nanoseconds(250_000_000) // 1.25 s
        let seconds = APRadarPulseInterval.seconds(from: duration)
        #expect(abs(seconds - 1.25) < 0.0001)
    }
}
