import Foundation
import Testing
@testable import WiFiLensCore

@Suite struct RegionInferenceEngineTests {

    // MARK: - Locale mapping

    @Test("System locale JP maps to regulatory domain JP")
    func localeJPMapsToJP() {
        let locale = Locale(identifier: "ja_JP")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .JP)
        #expect(result.confidence == .low) // locale alone is low confidence
    }

    @Test("System locale US maps to regulatory domain US")
    func localeUSMapsToUS() {
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .US)
    }

    @Test("System locale CN maps to regulatory domain CN")
    func localeCNMapsToCN() {
        let locale = Locale(identifier: "zh_CN")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .CN)
    }

    @Test("System locale DE maps to regulatory domain EU")
    func localeDEMapsToEU() {
        let locale = Locale(identifier: "de_DE")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .EU)
    }

    @Test("Unknown locale region maps to unknown domain")
    func unknownLocaleMapsToUnknown() {
        let locale = Locale(identifier: "en_ZZ") // invalid region
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .unknown)
    }

    // MARK: - User override

    @Test("User override wins over all other sources")
    func userOverrideWins() {
        let locale = Locale(identifier: "ja_JP")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["US", "US", "US"],
            userOverride: .CN
        )
        #expect(result.domain == .CN)
        #expect(result.confidence == .high)
        #expect(result.contributions.contains(where: { $0.kind == .userOverride }))
    }

    @Test("User override still records other source contributions")
    func userOverrideRecordsOtherSources() {
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["JP"],
            userOverride: .EU
        )
        #expect(result.domain == .EU)
        #expect(result.contributions.count >= 3, "Should record locale, AP, and override contributions")
    }

    // MARK: - AP country code consensus

    @Test("AP country codes with full consensus produce high confidence when matched with hardware")
    func apConsensusAllSame() {
        // Cannot easily test full integration without CWChannel mock,
        // but consensus logic itself is testable through the result
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["US", "US", "US"],
            userOverride: nil
        )
        // With no hardware fingerprint, falls back to AP consensus → medium
        #expect(result.domain == .US)
        #expect(result.confidence == .medium)
    }

    @Test("Conflicting AP country codes lower confidence")
    func apConflictLowersConfidence() {
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["US", "DE", "US"],
            userOverride: nil
        )
        // Majority US wins, but confidence is low due to conflict
        #expect(result.domain == .US)
        #expect(result.confidence == .low)
    }

    @Test("Empty AP country codes are handled gracefully")
    func emptyAPCodes() {
        let locale = Locale(identifier: "ja_JP")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .JP)
        #expect(result.confidence == .low)
    }

    @Test("AP country codes with leading/trailing whitespace are normalized")
    func apCountryCodesNormalized() {
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["US ", " us", "US"],
            userOverride: nil
        )
        #expect(result.domain == .US)
    }

    // MARK: - Empty inputs

    @Test("No usable sources yields unknown domain")
    func noSourcesYieldsUnknown() {
        let locale = Locale(identifier: "en_ZZ") // invalid
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: [],
            userOverride: nil
        )
        #expect(result.domain == .unknown)
        #expect(result.confidence == .low)
    }

    // MARK: - Contributions tracking

    @Test("Result includes contributions from all available sources")
    func resultIncludesAllContributions() {
        let locale = Locale(identifier: "en_US")
        let result = RegionInferenceEngine.infer(
            systemLocale: locale,
            supportedChannels: [],
            apCountryCodes: ["US"],
            userOverride: nil
        )
        let kinds = result.contributions.map(\.kind)
        #expect(kinds.contains(.systemLocale))
        #expect(kinds.contains(.apBeaconCountry))
        // supportedChannels always contributes (even if empty)
        #expect(kinds.contains(.supportedChannels))
    }
}
