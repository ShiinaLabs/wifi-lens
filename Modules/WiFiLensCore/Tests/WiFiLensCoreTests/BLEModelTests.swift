import Testing
import Foundation
@testable import WiFiLensCore

// MARK: - BLEChannel

struct BLEChannelTests {

    @Test func allCasesCount() {
        #expect(BLEChannel.allCases.count == 3)
    }

    @Test func channel37() {
        #expect(BLEChannel.channel37.rawValue == 37)
        #expect(BLEChannel.channel37.frequencyMHz == 2402)
        #expect(BLEChannel.channel37.displayName == "Ch 37 (2402 MHz)")
    }

    @Test func channel38() {
        #expect(BLEChannel.channel38.rawValue == 38)
        #expect(BLEChannel.channel38.frequencyMHz == 2426)
        #expect(BLEChannel.channel38.displayName == "Ch 38 (2426 MHz)")
    }

    @Test func channel39() {
        #expect(BLEChannel.channel39.rawValue == 39)
        #expect(BLEChannel.channel39.frequencyMHz == 2480)
        #expect(BLEChannel.channel39.displayName == "Ch 39 (2480 MHz)")
    }
}

// MARK: - BLERSSISample

struct BLERSSISampleTests {

    @Test func basicProperties() {
        let now = Date()
        let sample = BLERSSISample(timestamp: now, rawRSSI: -75, smoothedRSSI: -72.5)
        #expect(sample.timestamp == now)
        #expect(sample.rawRSSI == -75)
        #expect(sample.smoothedRSSI == -72.5)
    }

    @Test func uniqueID() {
        let now = Date()
        let s1 = BLERSSISample(timestamp: now, rawRSSI: -50, smoothedRSSI: -50)
        let s2 = BLERSSISample(timestamp: now, rawRSSI: -60, smoothedRSSI: -60)
        #expect(s1.id != s2.id)
    }

    @Test func negativeRSSIValues() {
        let now = Date()
        let sample = BLERSSISample(timestamp: now, rawRSSI: -100, smoothedRSSI: -95.0)
        #expect(sample.rawRSSI == -100)
    }
}

// MARK: - BLEAdvertisementEvent

struct BLEAdvertisementEventTests {

    @Test func basicProperties() {
        let now = Date()
        let id = UUID()
        let event = BLEAdvertisementEvent(
            timestamp: now,
            peripheralIdentifier: id,
            localName: "TestDevice",
            rssi: -60,
            txPower: 4,
            manufacturerData: nil,
            serviceUUIDs: ["180D", "180F"],
            isConnectable: true
        )
        #expect(event.timestamp == now)
        #expect(event.peripheralIdentifier == id)
        #expect(event.localName == "TestDevice")
        #expect(event.rssi == -60)
        #expect(event.txPower == 4)
        #expect(event.manufacturerData == nil)
        #expect(event.serviceUUIDs == ["180D", "180F"])
        #expect(event.isConnectable == true)
    }

    @Test func nilOptionals() {
        let event = BLEAdvertisementEvent(
            timestamp: Date(),
            peripheralIdentifier: UUID(),
            localName: nil,
            rssi: -80,
            txPower: nil,
            manufacturerData: nil,
            serviceUUIDs: nil,
            isConnectable: false
        )
        #expect(event.localName == nil)
        #expect(event.txPower == nil)
        #expect(event.manufacturerData == nil)
        #expect(event.serviceUUIDs == nil)
        #expect(event.isConnectable == false)
    }

    @Test func manufacturerDataPreserved() {
        let data = Data([0x01, 0xFF, 0xBE, 0xEF])
        let event = BLEAdvertisementEvent(
            timestamp: Date(),
            peripheralIdentifier: UUID(),
            localName: nil,
            rssi: -70,
            txPower: nil,
            manufacturerData: data,
            serviceUUIDs: nil,
            isConnectable: true
        )
        #expect(event.manufacturerData == data)
    }
}

// MARK: - BLEDeviceSnapshot

struct BLEDeviceSnapshotTests {

    @Test func computedID() {
        let id = UUID()
        let now = Date()
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: id,
            localName: "Device",
            rssi: -50,
            smoothedRSSI: -48.5,
            txPower: 4,
            isConnectable: true,
            firstSeen: now,
            lastSeen: now,
            advertisementCount: 10,
            rssiHistory: [],
            manufacturerData: nil
        )
        #expect(snapshot.id == id.uuidString)
    }

    @Test func displayNameWithLocalName() {
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            localName: "MyBluetooth",
            rssi: -60,
            smoothedRSSI: -58.0,
            txPower: nil,
            isConnectable: false,
            firstSeen: Date(),
            lastSeen: Date(),
            advertisementCount: 5,
            rssiHistory: [],
            manufacturerData: nil
        )
        #expect(snapshot.displayName == "MyBluetooth")
    }

    @Test func displayNameWithoutLocalName() {
        let id = UUID()
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: id,
            localName: nil,
            rssi: -60,
            smoothedRSSI: -58.0,
            txPower: nil,
            isConnectable: false,
            firstSeen: Date(),
            lastSeen: Date(),
            advertisementCount: 5,
            rssiHistory: [],
            manufacturerData: nil
        )
        #expect(snapshot.displayName == id.uuidString)
    }

    @Test func shortIdentifierLength() {
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            localName: nil,
            rssi: -70,
            smoothedRSSI: -68.0,
            txPower: nil,
            isConnectable: false,
            firstSeen: Date(),
            lastSeen: Date(),
            advertisementCount: 3,
            rssiHistory: [],
            manufacturerData: nil
        )
        #expect(snapshot.shortIdentifier.count == 8)
    }
}

// MARK: - BLEDeviceTracker

@Suite @MainActor struct BLEDeviceTrackerTests {

    private func makeEvent(deviceID: UUID, rssi: Int = -50, name: String? = nil, timestamp: Date = Date()) -> BLEAdvertisementEvent {
        BLEAdvertisementEvent(
            timestamp: timestamp,
            peripheralIdentifier: deviceID,
            localName: name,
            rssi: rssi,
            txPower: nil,
            manufacturerData: nil,
            serviceUUIDs: nil,
            isConnectable: true
        )
    }

    @Test func processSingleDeviceBatch() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id = UUID()
        let events = [makeEvent(deviceID: id, rssi: -60, name: "Device1")]
        let snapshots = tracker.processBatch([id: events])

        #expect(snapshots.count == 1)
        #expect(snapshots[0].peripheralIdentifier == id)
        #expect(snapshots[0].localName == "Device1")
        #expect(snapshots[0].rssi == -60)
        #expect(snapshots[0].advertisementCount == 1)
    }

    @Test func processMultipleDevices() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id1 = UUID(), id2 = UUID()
        let snapshots = tracker.processBatch([
            id1: [makeEvent(deviceID: id1, rssi: -50, name: "A")],
            id2: [makeEvent(deviceID: id2, rssi: -70, name: "B")],
        ])

        #expect(snapshots.count == 2)
    }

    @Test func usesStrongestRSSIFromBatch() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id = UUID()
        let now = Date()
        let weak = makeEvent(deviceID: id, rssi: -90, timestamp: now)
        let strong = makeEvent(deviceID: id, rssi: -40, timestamp: now.addingTimeInterval(0.1))
        let snapshots = tracker.processBatch([id: [weak, strong]])

        #expect(snapshots[0].rssi == -40)
    }

    @Test func emptyBatchReturnsOnlyKnownDevices() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id = UUID()
        _ = tracker.processBatch([id: [makeEvent(deviceID: id)]])
        let snapshots = tracker.processBatch([:])

        #expect(snapshots.count == 1)
        #expect(snapshots[0].peripheralIdentifier == id)
    }

    @Test func ringBufferLimit() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 3, staleTimeout: 60)
        let id = UUID()
        let now = Date()
        for i in 0..<5 {
            let ts = now.addingTimeInterval(Double(i))
            _ = tracker.processBatch([id: [makeEvent(deviceID: id, rssi: -50, timestamp: ts)]])
        }

        let snapshots = tracker.processBatch([:])
        #expect(snapshots[0].rssiHistory.count == 3)
    }

    @Test func rssiHistoryRequiresAtLeastTwoSamples() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id = UUID()
        _ = tracker.processBatch([id: [makeEvent(deviceID: id)]])
        let history = tracker.rssiHistory(for: id)
        #expect(history == nil)
    }

    @Test func rssiHistoryReturnsAfterMultipleBatches() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 10, staleTimeout: 60)
        let id = UUID()
        let now = Date()
        _ = tracker.processBatch([id: [makeEvent(deviceID: id, timestamp: now)]])
        _ = tracker.processBatch([id: [makeEvent(deviceID: id, timestamp: now.addingTimeInterval(1))]])
        let history = tracker.rssiHistory(for: id)
        #expect(history != nil)
        #expect(history!.count >= 2)
    }

    @Test func evictExcessDevices() {
        let tracker = BLEDeviceTracker(maxHistoryCount: 5, staleTimeout: 60, maxTrackedDevices: 2)
        let now = Date()
        for i in 0..<3 {
            let id = UUID()
            _ = tracker.processBatch([id: [makeEvent(deviceID: id, rssi: -50 - i, timestamp: now.addingTimeInterval(Double(i)))]])
        }

        let snapshots = tracker.processBatch([:])
        #expect(snapshots.count <= 2)
    }

    @Test func emptyDeviceBatchProducesEmptySnapshots() {
        let tracker = BLEDeviceTracker()
        let snapshots = tracker.processBatch([:])
        #expect(snapshots.isEmpty)
    }
}
