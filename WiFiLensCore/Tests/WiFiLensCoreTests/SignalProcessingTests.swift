import Testing
@testable import WiFiLensCore

// MARK: - ExponentialMovingAverage

struct ExponentialMovingAverageTests {

    @Test func alphaClampedToZero() {
        var ema = ExponentialMovingAverage(alpha: -0.5, initial: 50)
        let result = ema.smooth(60)
        #expect(result == 50)
    }

    @Test func alphaClampedToOne() {
        var ema = ExponentialMovingAverage(alpha: 1.5, initial: 0)
        let result = ema.smooth(100)
        #expect(result == 100)
    }

    @Test func defaultAlphaAndInitial() {
        var ema = ExponentialMovingAverage()
        let result = ema.smooth(100)
        #expect(result == 25)
    }

    @Test func progressiveConvergence() {
        var ema = ExponentialMovingAverage(alpha: 0.5, initial: 0)
        let r1 = ema.smooth(100)
        #expect(r1 == 50)
        let r2 = ema.smooth(100)
        #expect(r2 == 75)
        let r3 = ema.smooth(100)
        #expect(r3 == 87.5)
    }

    @Test func smoothWithConstantInput() {
        var ema = ExponentialMovingAverage(alpha: 0.25, initial: 50)
        let r1 = ema.smooth(50)
        #expect(r1 == 50)
        let r2 = ema.smooth(50)
        #expect(r2 == 50)
    }

    @Test func resetRestoresInitial() {
        var ema = ExponentialMovingAverage(alpha: 0.5, initial: 0)
        _ = ema.smooth(100)
        ema.reset()
        let result = ema.smooth(100)
        #expect(result == 50)
    }

    @Test func alphaPreservedAfterInit() {
        let ema = ExponentialMovingAverage(alpha: 0.3)
        #expect(ema.alpha == 0.3)
    }
}

// MARK: - HysteresisEMA

struct HysteresisEMATests {

    @Test func thresholdBypass_onLargeJump() {
        var hema = HysteresisEMA(alpha: 0.25, threshold: 10, initial: 0)
        let result = hema.smooth(100)
        #expect(result == 100)
    }

    @Test func normalEMA_withinThreshold() {
        var hema = HysteresisEMA(alpha: 0.5, threshold: 10, initial: 0)
        let r1 = hema.smooth(5)
        #expect(r1 == 2.5)
        let r2 = hema.smooth(6)
        #expect(r2 == 4.25)
    }

    @Test func thresholdBoundary_belowUsesEMA() {
        var hema = HysteresisEMA(alpha: 0.5, threshold: 10, initial: 0)
        let result = hema.smooth(9.999)
        #expect(result == 4.9995)
    }

    @Test func thresholdBoundary_aboveUsesBypass() {
        var hema = HysteresisEMA(alpha: 0.5, threshold: 10, initial: 0)
        let result = hema.smooth(10.001)
        #expect(result == 10.001)
    }

    @Test func thresholdBypass_resetThenLargeJump() {
        var hema = HysteresisEMA(alpha: 0.25, threshold: 8, initial: 0)
        _ = hema.smooth(5)
        _ = hema.smooth(6)
        hema.reset()
        let result = hema.smooth(50)
        #expect(result == 50)
    }

    @Test func gradualDriftWithinThreshold() {
        var hema = HysteresisEMA(alpha: 0.5, threshold: 10, initial: 0)
        let r1 = hema.smooth(3)
        #expect(r1 == 1.5)
        let r2 = hema.smooth(6)
        #expect(r2 == 3.75)
        let r3 = hema.smooth(9)
        #expect(r3 == 6.375)
    }

    @Test func alphaClamped() {
        let hema = HysteresisEMA(alpha: 1.5, threshold: 8)
        #expect(hema.alpha == 1.0)
    }
}

// MARK: - KalmanFilter1D

struct KalmanFilter1DTests {

    @Test func convergesToConstantInput() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 2.0, initial: 0)
        var last: Double = 0
        for _ in 0..<20 {
            last = kf.smooth(50)
        }
        #expect(abs(last - 50) < 0.5)
    }

    @Test func initialEstimateIsUsed() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 2.0, initial: 30)
        let first = kf.smooth(50)
        #expect(first > 30 && first < 50)
    }

    @Test func lowMeasurementNoiseTracksClosely() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 0.1, initial: 0)
        for _ in 0..<5 { _ = kf.smooth(100) }
        let r = kf.smooth(100)
        #expect(abs(r - 100) < 1)
    }

    @Test func highMeasurementNoiseSmoothsMore() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 100, initial: 0)
        let r1 = kf.smooth(100)
        #expect(r1 < 50)
    }

    @Test func resetRestoresState() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 2.0, initial: 0)
        _ = kf.smooth(100)
        _ = kf.smooth(100)
        kf.reset()
        let r1 = kf.smooth(50)
        #expect(r1 < 50 && r1 > 0)
    }

    @Test func kalmanGainStartsHighThenDecreases() {
        var kf = KalmanFilter1D(processNoise: 0.5, measurementNoise: 2.0, initial: 0)
        let firstFollow = kf.smooth(100)
        let secondFollow = kf.smooth(100)
        let thirdFollow = kf.smooth(100)
        let diffs = [abs(firstFollow - 100), abs(secondFollow - 100), abs(thirdFollow - 100)]
        #expect(diffs[0] > diffs[1])
    }

    @Test func processNoiseAndMeasurementNoiseAccessible() {
        let kf = KalmanFilter1D(processNoise: 1.5, measurementNoise: 3.0)
        #expect(kf.processNoise == 1.5)
        #expect(kf.measurementNoise == 3.0)
    }

    @Test func differentProcessNoiseProducesDifferentResults() {
        var kfLow = KalmanFilter1D(processNoise: 0.1, measurementNoise: 2.0, initial: 0)
        var kfHigh = KalmanFilter1D(processNoise: 5.0, measurementNoise: 2.0, initial: 0)
        for _ in 0..<5 {
            _ = kfLow.smooth(100)
            _ = kfHigh.smooth(100)
        }
        // Low process noise trusts model more → slower convergence (further from 100)
        #expect(abs(kfLow.smooth(100) - 100) > abs(kfHigh.smooth(100) - 100))
    }
}
