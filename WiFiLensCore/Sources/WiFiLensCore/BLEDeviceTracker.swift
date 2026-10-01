import Foundation

/// Per-device ring buffers and EMA smoothing for BLE RSSI tracking.
/// Analogous to SignalHistoryStore but tuned for BLE advertisement patterns.
@MainActor
final class BLEDeviceTracker {
    private var deviceHistories: [UUID: [BLERSSISample]] = [:]
    private var emaFilters: [UUID: ExponentialMovingAverage] = [:]
    private var firstSeenTimestamps: [UUID: Date] = [:]
    private var lastMetadata: [UUID: DeviceMetadata] = [:]

    private struct DeviceMetadata {
        var localName: String?
        var txPower: Int?
        var isConnectable: Bool = false
        var manufacturerData: Data?
    }

    let maxHistoryCount: Int
    let emaAlpha: Double
    let staleTimeout: TimeInterval
    let maxTrackedDevices: Int

    init(maxHistoryCount: Int = 30, emaAlpha: Double = 0.25, staleTimeout: TimeInterval = 30, maxTrackedDevices: Int = 100) {
        self.maxHistoryCount = maxHistoryCount
        self.emaAlpha = emaAlpha
        self.staleTimeout = staleTimeout
        self.maxTrackedDevices = maxTrackedDevices
    }

    /// Process a batch of raw advertisement events, returning updated snapshots
    /// for ALL known devices (including those not in the current batch).
    func processBatch(
        _ eventsByDevice: [UUID: [BLEAdvertisementEvent]]
    ) -> [BLEDeviceSnapshot] {
        // Update history and metadata for devices in the current batch
        for (identifier, events) in eventsByDevice {
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }),
                  !events.isEmpty else { continue }

            if firstSeenTimestamps[identifier] == nil {
                firstSeenTimestamps[identifier] = latest.timestamp
            }

            // Retain best-known metadata — only overwrite fields when we get new data
            var meta = lastMetadata[identifier] ?? DeviceMetadata()
            if let name = latest.localName { meta.localName = name }
            if let tx = latest.txPower { meta.txPower = tx }
            meta.isConnectable = latest.isConnectable
            if let mfr = latest.manufacturerData { meta.manufacturerData = mfr }
            lastMetadata[identifier] = meta

            // RSSI aggregation: use best (strongest) RSSI from this batch
            let bestRSSI = events.map(\.rssi).max() ?? latest.rssi

            // EMA smoothing
            var ema = emaFilters[identifier]
                ?? ExponentialMovingAverage(alpha: emaAlpha, initial: Double(bestRSSI))
            let smoothed = ema.smooth(Double(bestRSSI))
            emaFilters[identifier] = ema

            // Build sample and append to ring buffer
            let sample = BLERSSISample(
                timestamp: latest.timestamp,
                rawRSSI: bestRSSI,
                smoothedRSSI: smoothed
            )

            var history = deviceHistories[identifier] ?? []
            history.append(sample)
            if history.count > maxHistoryCount {
                history.removeFirst(history.count - maxHistoryCount)
            }
            deviceHistories[identifier] = history
        }

        purgeStale()
        evictOverflow()

        // Build snapshots for ALL known devices, not just the current batch.
        // Devices that didn't appear in this batch are carried over with their
        // last-known RSSI and metadata until they go stale.
        var snapshots: [BLEDeviceSnapshot] = []
        for (identifier, history) in deviceHistories {
            guard let lastSample = history.last,
                  let meta = lastMetadata[identifier] else { continue }

            snapshots.append(BLEDeviceSnapshot(
                peripheralIdentifier: identifier,
                localName: meta.localName,
                rssi: lastSample.rawRSSI,
                smoothedRSSI: lastSample.smoothedRSSI,
                txPower: meta.txPower,
                isConnectable: meta.isConnectable,
                firstSeen: firstSeenTimestamps[identifier] ?? lastSample.timestamp,
                lastSeen: lastSample.timestamp,
                advertisementCount: history.count,
                rssiHistory: history,
                manufacturerData: meta.manufacturerData
            ))
        }

        return snapshots
    }

    /// RSSI history for a specific device (for chart rendering).
    func rssiHistory(for identifier: UUID) -> [BLERSSISample]? {
        guard let history = deviceHistories[identifier], history.count >= 2 else {
            return nil
        }
        return history
    }

    /// Remove devices not seen within the stale timeout.
    func purgeStale() {
        let cutoff = Date().addingTimeInterval(-staleTimeout)
        let stale = deviceHistories.filter { _, samples in
            guard let last = samples.last else { return true }
            return last.timestamp < cutoff
        }
        for (id, _) in stale {
            deviceHistories.removeValue(forKey: id)
            emaFilters.removeValue(forKey: id)
            firstSeenTimestamps.removeValue(forKey: id)
            lastMetadata.removeValue(forKey: id)
        }
    }

    /// Evict weakest/oldest devices when the tracked count exceeds the limit.
    private func evictOverflow() {
        guard deviceHistories.count > maxTrackedDevices else { return }

        let sorted = deviceHistories.compactMap { (id, samples) -> (UUID, Int, Date)? in
            guard let last = samples.last else { return nil }
            return (id, last.rawRSSI, last.timestamp)
        }.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            return a.2 < b.2
        }

        let toEvict = sorted.prefix(deviceHistories.count - maxTrackedDevices)
        for (id, _, _) in toEvict {
            deviceHistories.removeValue(forKey: id)
            emaFilters.removeValue(forKey: id)
            firstSeenTimestamps.removeValue(forKey: id)
            lastMetadata.removeValue(forKey: id)
        }
    }
}
