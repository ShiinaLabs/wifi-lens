import Foundation

struct HysteresisEMA: SignalSmoothing {
    let alpha: Double
    let threshold: Double
    private var current: Double

    init(alpha: Double = 0.25, threshold: Double = 8, initial: Double = 0) {
        self.alpha = max(0, min(1, alpha))
        self.threshold = threshold
        self.current = initial
    }

    mutating func smooth(_ value: Double) -> Double {
        if abs(value - current) > threshold {
            current = value
        } else {
            current = alpha * value + (1 - alpha) * current
        }
        return current
    }

    mutating func reset() {
        current = 0
    }
}
