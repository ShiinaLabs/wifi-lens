import Testing
import SwiftUI
import AppKit
@testable import WiFi_Lens

@MainActor
struct NetworkTableRowTests {

    private func makeRow(
        id: String = "aa:bb:cc:dd:ee:ff-6-1",
        rssi: Int = -50,
        ssid: String = "TestWiFi",
        vendor: String = "Example Networks",
        qualityScore: Int = 80,
        phyMode: String = "ax",
        channelWidth: String = "80",
        isVisible: Bool = true,
        isFilteredOut: Bool = false,
        security: String = "WPA3",
        mcs: String = "9",
        isHiddenSSID: Bool = false
    ) -> NetworkTableRow {
        NetworkTableRow(
            id: id,
            bandID: "5",
            bandLabel: "5 GHz",
            channel: 44,
            rssi: rssi,
            ssid: ssid,
            vendor: vendor,
            bssid: "aa:bb:cc:dd:ee:ff",
            color: .blue,
            isFilteredOut: isFilteredOut,
            phyMode: phyMode,
            channelWidth: channelWidth,
            supportsK: true,
            supportsR: false,
            supportsV: true,
            isHiddenSSID: isHiddenSSID,
            security: security,
            mcs: mcs,
            nss: "2",
            country: "US",
            trendArrow: "▲",
            trendDelta: 3,
            isVisible: isVisible,
            visibilityLocked: false,
            qualityScore: qualityScore,
            lastSeen: ""
        )
    }

    // MARK: - Equality

    @Test func identicalRowsAreEqual() async throws {
        #expect(makeRow() == makeRow())
        #expect(makeRow().hashValue == makeRow().hashValue)
    }

    @Test func differentRSSINotEqual() async throws {
        #expect(makeRow(rssi: -50) != makeRow(rssi: -60))
    }

    @Test func differentSSIDNotEqual() async throws {
        #expect(makeRow(ssid: "WiFi-A") != makeRow(ssid: "WiFi-B"))
    }

    @Test func differentVendorNotEqual() async throws {
        #expect(makeRow(vendor: "Vendor A") != makeRow(vendor: "Vendor B"))
    }

    @Test func differentQualityScoreNotEqual() async throws {
        #expect(makeRow(qualityScore: 80) != makeRow(qualityScore: 60))
    }

    @Test func differentPhyModeNotEqual() async throws {
        #expect(makeRow(phyMode: "ax") != makeRow(phyMode: "ac"))
    }

    @Test func differentVisibilityNotEqual() async throws {
        #expect(makeRow(isVisible: true) != makeRow(isVisible: false))
    }

    @Test func differentFilterNotEqual() async throws {
        #expect(makeRow(isFilteredOut: false) != makeRow(isFilteredOut: true))
    }

    @Test func differentChannelWidthNotEqual() async throws {
        #expect(makeRow(channelWidth: "80") != makeRow(channelWidth: "160"))
    }

    @Test func differentSecurityNotEqual() async throws {
        #expect(makeRow(security: "WPA3") != makeRow(security: "WPA2"))
    }

    @Test func differentMCSNotEqual() async throws {
        #expect(makeRow(mcs: "9") != makeRow(mcs: "7"))
    }

    @Test func differentHiddenSSIDNotEqual() async throws {
        #expect(makeRow(isHiddenSSID: false) != makeRow(isHiddenSSID: true))
    }

    // MARK: - Array comparison (the pattern used in NativeTableView)

    @Test func arrayOfRowsDetectsSingleChange() async throws {
        let rows1 = [makeRow(id: "id1", rssi: -50), makeRow(id: "id2", rssi: -60)]
        let rows2 = [makeRow(id: "id1", rssi: -50), makeRow(id: "id2", rssi: -55)]
        #expect(rows1 != rows2)
    }

    @Test func arrayOfRowsDetectsNoChange() async throws {
        let rows1 = [makeRow(id: "id1"), makeRow(id: "id2")]
        let rows2 = [makeRow(id: "id1"), makeRow(id: "id2")]
        #expect(rows1 == rows2)
    }

    @Test func tableCoordinatorUsesStableRowIDForVisibilityCallbacks() {
        let row = makeRow(id: "series-id-1")
        var visibilityID: String?
        var lockID: String?

        let coordinator = NativeTableView.Coordinator(
            rows: [row],
            selectedID: .constant(nil),
            sortOrder: .constant([]),
            hiddenColumns: .constant([]),
            onToggleVisibility: { visibilityID = $0 },
            onToggleVisibilityLocked: { lockID = $0 }
        )

        let visibilityButton = NSButton()
        visibilityButton.tag = 0
        coordinator.visibilityToggled(visibilityButton)

        let lockButton = NSButton()
        lockButton.tag = 0
        coordinator.lockToggled(lockButton)

        #expect(visibilityID == row.id)
        #expect(lockID == row.id)
    }

}
