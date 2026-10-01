import Foundation

protocol SignalSmoothing {
    mutating func smooth(_ value: Double) -> Double
    mutating func reset()
}
