import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct GuidanceEditionTests {
    @Test func ossGuidanceConfigurationEnablesInvitationsOnly() {
        let config = EditionAssemblyProvider.configuration.guidanceConfiguration

        #expect(config.invitationEnabled == true)
        #expect(config.reviewEnabled == false)
    }

    @Test func ossExportSuccessPresentationIsBanner() {
        #expect(EditionAssemblyProvider.configuration.exportSuccessPresentation == .banner)
    }
}
