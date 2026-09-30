import Foundation

/// BLE advertising channels with their physical frequencies.
public enum BLEChannel: Int, Sendable, CaseIterable {
    case channel37 = 37  // 2402 MHz
    case channel38 = 38  // 2426 MHz
    case channel39 = 39  // 2480 MHz

    public var frequencyMHz: Int {
        switch self {
        case .channel37: 2402
        case .channel38: 2426
        case .channel39: 2480
        }
    }

    public var displayName: String { "Ch \(rawValue) (\(frequencyMHz) MHz)" }
}
