import Foundation

enum RegulatoryDomainResolver {
    static func resolve(
        userOverride: RegulatoryDomain?,
        userDefaultsOverride: RegulatoryDomain?,
        systemLocale: Locale = .current,
        supportedChannelsRaw: [(Int, Int)],
        apCountryCodes: [String]
    ) -> RegionInferenceResult {
        RegionInferenceEngine.infer(
            systemLocale: systemLocale,
            supportedChannels: supportedChannelsRaw,
            apCountryCodes: apCountryCodes,
            userOverride: userOverride ?? userDefaultsOverride
        )
    }
}
