import Testing

@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct GuidanceEditionTests {
    @Test func ossGuidanceConfigurationEnablesInvitationsOnly() {
        let config = EditionAssemblyProvider.configuration.guidanceConfiguration

        #expect(config.invitationEnabled == true)
        #expect(config.reviewEnabled == false)
        #expect(config.minimumInvitationCompletions == 0)
        #expect(config.minimumInvitationActiveDays == 2)
        #expect(config.invitationCooldownDays == 7)
        #expect(config.localMarketingPolicyEnabled)
        #expect(!GuidanceConfiguration().localMarketingPolicyEnabled)
    }

    @Test func ossExportSuccessPresentationIsBanner() {
        #expect(EditionAssemblyProvider.configuration.exportSuccessPresentation == .banner)
    }
}
