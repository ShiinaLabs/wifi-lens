import Foundation

/// Processed device state emitted each batch window. Used directly by the UI.
public struct BLEDeviceSnapshot: Sendable, Identifiable {
    public var id: String { peripheralIdentifier.uuidString }

    public let peripheralIdentifier: UUID
    public let localName: String?
    public let rssi: Int
    public let smoothedRSSI: Double
    public let txPower: Int?
    public let isConnectable: Bool
    public let firstSeen: Date
    public let lastSeen: Date
    public let advertisementCount: Int
    public let rssiHistory: [BLERSSISample]
    public let manufacturerData: Data?

    public init(
        peripheralIdentifier: UUID,
        localName: String?,
        rssi: Int,
        smoothedRSSI: Double,
        txPower: Int?,
        isConnectable: Bool,
        firstSeen: Date,
        lastSeen: Date,
        advertisementCount: Int,
        rssiHistory: [BLERSSISample],
        manufacturerData: Data?
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.localName = localName
        self.rssi = rssi
        self.smoothedRSSI = smoothedRSSI
        self.txPower = txPower
        self.isConnectable = isConnectable
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.advertisementCount = advertisementCount
        self.rssiHistory = rssiHistory
        self.manufacturerData = manufacturerData
    }

    public var displayName: String {
        localName ?? peripheralIdentifier.uuidString
    }

    /// Shortened identifier for compact display (first 8 chars of UUID).
    public var shortIdentifier: String {
        let uuid = peripheralIdentifier.uuidString
        return String(uuid.prefix(8))
    }
}
