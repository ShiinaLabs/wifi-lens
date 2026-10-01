import Foundation

/// Single timestamped RSSI reading, stored in per-device ring buffers.
public struct BLERSSISample: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let rawRSSI: Int
    public let smoothedRSSI: Double

    public init(id: UUID = UUID(), timestamp: Date, rawRSSI: Int, smoothedRSSI: Double) {
        self.id = id
        self.timestamp = timestamp
        self.rawRSSI = rawRSSI
        self.smoothedRSSI = smoothedRSSI
    }
}
