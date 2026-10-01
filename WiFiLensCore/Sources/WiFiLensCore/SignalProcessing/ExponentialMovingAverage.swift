import Foundation

struct ExponentialMovingAverage: SignalSmoothing {
    let alpha: Double
    private var current: Double

    init(alpha: Double = 0.25, initial: Double = 0) {
        self.alpha = max(0, min(1, alpha))
        self.current = initial
    }

    mutating func smooth(_ value: Double) -> Double {
        current = alpha * value + (1 - alpha) * current
        return current
    }

    mutating func reset() {
        current = 0
    }
}
