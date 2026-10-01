import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct SecondaryToolbarDescriptorExpansionTests {

    @Test func interfacesPageProvidesSecondaryToolbarDescriptor() {
        let descriptor = SecondaryToolbarDescriptor.forPage(.interfaces)
        #expect(descriptor != nil)
        #expect(descriptor?.items.map(\.id) == [.interfacesSimple, .interfacesDetails, .interfacesMonitor])
    }

}
