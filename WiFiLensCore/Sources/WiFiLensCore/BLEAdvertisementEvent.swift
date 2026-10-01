import Foundation

/// Raw advertisement event from a single CoreBluetooth `didDiscover` callback.
public struct BLEAdvertisementEvent: Sendable {
    public let timestamp: Date
    public let peripheralIdentifier: UUID
    public let localName: String?
    public let rssi: Int
    public let txPower: Int?
    public let manufacturerData: Data?
    public let serviceUUIDs: [String]?
    public let isConnectable: Bool

    public init(
        timestamp: Date,
        peripheralIdentifier: UUID,
        localName: String?,
        rssi: Int,
        txPower: Int?,
        manufacturerData: Data?,
        serviceUUIDs: [String]?,
        isConnectable: Bool
    ) {
        self.timestamp = timestamp
        self.peripheralIdentifier = peripheralIdentifier
        self.localName = localName
        self.rssi = rssi
        self.txPower = txPower
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.isConnectable = isConnectable
    }
}
