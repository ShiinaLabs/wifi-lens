import Foundation

struct KalmanFilter1D: SignalSmoothing {
    let processNoise: Double
    let measurementNoise: Double
    private var estimate: Double
    private var errorCovariance: Double

    init(processNoise: Double = 0.5, measurementNoise: Double = 2.0, initial: Double = 0) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
        self.estimate = initial
        self.errorCovariance = 1.0
    }

    mutating func smooth(_ value: Double) -> Double {
        // Prediction
        let predictedEstimate = estimate
        let predictedError = errorCovariance + processNoise

        // Update
        let kalmanGain = predictedError / (predictedError + measurementNoise)
        estimate = predictedEstimate + kalmanGain * (value - predictedEstimate)
        errorCovariance = (1 - kalmanGain) * predictedError

        return estimate
    }

    mutating func reset() {
        estimate = 0
        errorCovariance = 1.0
    }
}
