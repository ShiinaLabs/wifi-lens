import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct ChannelQualityViewModeTests {

    @Test func channelsToolbarSelectionMapsToSimpleMode() {
        #expect(ChannelViewMode.fromToolbarSelection(.channelsSimple) == .simple)
    }

    @Test func channelsToolbarSelectionMapsToTableMode() {
        #expect(ChannelViewMode.fromToolbarSelection(.channelsTable) == .table)
    }
}
