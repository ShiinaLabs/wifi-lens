import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct SecondaryToolbarTests {

    @Test func secondaryToolbarDescriptor_isNilForOverview() {
        #expect(SecondaryToolbarDescriptor.forPage(.overview) == nil)
    }

    @Test func secondaryToolbarDescriptor_channelsContainsTwoItems() {
        let descriptor = SecondaryToolbarDescriptor.forPage(.channels)
        #expect(descriptor != nil)
        #expect(descriptor?.items.map(\.id) == [.channelsSimple, .channelsTable])
        #expect(descriptor?.defaultSelection == .channelsSimple)
    }

    @Test func secondaryToolbarDescriptor_selectionIndexMatchesItemOrder() {
        let descriptor = SecondaryToolbarDescriptor.forPage(.channels)
        #expect(descriptor?.selectionIndex(for: .channelsSimple) == 0)
        #expect(descriptor?.selectionIndex(for: .channelsTable) == 1)
    }
}
