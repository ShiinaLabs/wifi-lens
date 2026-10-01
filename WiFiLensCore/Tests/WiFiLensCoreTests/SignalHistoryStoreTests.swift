import Foundation
import Testing
@testable import WiFiLensCore
@Suite @MainActor struct SignalHistoryStoreTests {
    private func makeSnapshot(timestamp: Date, rssi: Int) -> NetworkSnapshot {
        NetworkSnapshot(
            timestamp: timestamp,
            bssid: "aa:bb:cc:dd:ee:01",
            ssid: "TestNet",
            rssi: rssi,
            channel: 6,
            band: "24",
            phyMode: "ax",
            channelWidth: "20",
            mcs: "",
            nss: "",
            security: "",
            country: "",
            supportsK: false,
            supportsR: false,
            supportsV: false,
            supportsWPA3: false,
            isHiddenSSID: false
        )
    }

    @Test func perBSSIDRSSIHistoryRemainsBounded() {
        let store = SignalHistoryStore(maxCount: 2)
        store.record(bssid: "aa:bb:cc:dd:ee:01", rssi: -80)
        store.record(bssid: "aa:bb:cc:dd:ee:01", rssi: -70)
        store.record(bssid: "aa:bb:cc:dd:ee:01", rssi: -60)

        #expect(store.rssiHistory(for: "aa:bb:cc:dd:ee:01") == [-70, -60])
    }

    @Test func perBSSIDSnapshotsRemainAvailableForTrendHistory() {
        let store = SignalHistoryStore(maxCount: 2)
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 101)
        store.record(bssid: "aa:bb:cc:dd:ee:01", rssi: -70, snapshot: makeSnapshot(timestamp: first, rssi: -70))
        store.record(bssid: "aa:bb:cc:dd:ee:01", rssi: -60, snapshot: makeSnapshot(timestamp: second, rssi: -60))

        #expect(store.snapshotHistory(for: "aa:bb:cc:dd:ee:01")?.map(\.timestamp) == [first, second])
        #expect(store.allSnapshots["aa:bb:cc:dd:ee:01"]?.map(\.rssi) == [-70, -60])
    }
}
