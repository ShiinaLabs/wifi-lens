import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
final class OnboardingEditionTests {
    @Test func ossEnablesWelcomeWithProLink() {
        let config = EditionAssemblyProvider.configuration.onboardingConfiguration

        #expect(config.welcomeEnabled == true)
        #expect(config.showsProLink == true)
        #expect(config.startRoute == .overview)
        #expect(config.startToolbarSelection == nil)
        #expect(config.primaryActionKey == "onboarding.welcome.start")
        #expect(config.highlights.map(\.titleKey) == [
            "onboarding.welcome.highlight.live",
            "onboarding.welcome.highlight.diagnostics",
            "onboarding.welcome.highlight.export"
        ])
        #expect(config.proURL?.absoluteString == "https://apps.apple.com/app/apple-store/id6776590746?pt=128979395&ct=oss_welcome&mt=8")
    }

    @Test func ossMigrationUsesSparkleMarker() {
        let suiteName = "OSSOnboardingEdition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let detector = SparkleAutomaticCheckExistingInstallationDetector(defaults: defaults)

        #expect(detector.hasExistingInstallationEvidence() == false)

        defaults.set(true, forKey: SparkleAutomaticCheckExistingInstallationDetector.defaultsKey)

        #expect(detector.hasExistingInstallationEvidence() == true)
    }
}
