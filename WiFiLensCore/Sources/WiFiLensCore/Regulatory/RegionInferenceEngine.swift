import Foundation
import WiFiLensCoreRust

/// Swift adapter for multi-source region inference in the portable Rust core.
enum RegionInferenceEngine {
    static func infer(
        systemLocale: Locale,
        supportedChannels: [(Int, Int)],
        apCountryCodes: [String],
        userOverride: RegulatoryDomain?
    ) -> RegionInferenceResult {
        let localeCode = systemLocale.region?.identifier
        var strings = Array((localeCode ?? "").utf8)
        var apRanges: [WiFiLensRegulatoryStringRange] = []
        for countryCode in apCountryCodes {
            let bytes = Array(countryCode.utf8)
            apRanges.append(WiFiLensRegulatoryStringRange(offset: strings.count, length: bytes.count))
            strings.append(contentsOf: bytes)
        }
        let channels = supportedChannels.map {
            WiFiLensRegulatorySupportedChannel(band: Int32($0.0), channel: Int32($0.1))
        }
        let localeLength = (localeCode ?? "").utf8.count
        var output = WiFiLensRegulatoryInferenceResult()
        let status = strings.withUnsafeBufferPointer { stringsBuffer in
            apRanges.withUnsafeBufferPointer { apRangesBuffer in
                channels.withUnsafeBufferPointer { channelsBuffer in
                    var input = WiFiLensRegulatoryInferenceInput(
                        locale_region_offset: 0,
                        locale_region_length: localeLength,
                        user_override_domain: userOverride?.rustCode ?? WIFI_LENS_REGULATORY_DOMAIN_UNKNOWN,
                        ap_country_code_count: apRangesBuffer.count,
                        ap_country_codes: apRangesBuffer.baseAddress,
                        supported_channel_count: channelsBuffer.count,
                        supported_channels: channelsBuffer.baseAddress,
                        strings_length: stringsBuffer.count,
                        strings: stringsBuffer.baseAddress
                    )
                    return withUnsafePointer(to: &input) { inputPointer in
                        withUnsafeMutablePointer(to: &output) { outputPointer in
                            wifi_lens_regulatory_infer(inputPointer, outputPointer)
                        }
                    }
                }
            }
        }

        var contributions: [RegionSource] = []
        if let userOverride, userOverride != .unknown {
            contributions.append(
                RegionSource(kind: .userOverride, rawValue: userOverride.rawValue, inferredDomain: userOverride)
            )
        }
        contributions.append(
            RegionSource(
                kind: .systemLocale,
                rawValue: localeCode ?? "nil",
                inferredDomain: RegulatoryDomain(rustCode: output.locale_domain)
            )
        )
        if !apCountryCodes.isEmpty {
            contributions.append(
                RegionSource(
                    kind: .apBeaconCountry,
                    rawValue: apCountryCodes.joined(separator: ","),
                    inferredDomain: RegulatoryDomain(rustCode: output.ap_domain)
                )
            )
        }
        contributions.append(
            RegionSource(
                kind: .supportedChannels,
                rawValue: "\(supportedChannels.count) channels",
                inferredDomain: RegulatoryDomain(rustCode: output.supported_channels_domain)
            )
        )

        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust regulatory inference returned status \(status)")
            return RegionInferenceResult(
                domain: .unknown,
                confidence: .low,
                contributions: contributions,
                conflicts: []
            )
        }

        let conflicts: [RegionConflict] =
            if output.conflict_resolution == WIFI_LENS_REGULATORY_CONFLICT_CHANNELS_DISAGREE_WITH_AP,
                let supportedSource = contributions.first(where: { $0.kind == .supportedChannels }),
                let apSource = contributions.first(where: { $0.kind == .apBeaconCountry })
            {
                [
                    RegionConflict(
                        sourceA: supportedSource,
                        sourceB: apSource,
                        resolution: "AP beacon disagrees with hardware supported channels; trusting hardware"
                    )
                ]
            } else {
                []
            }

        return RegionInferenceResult(
            domain: RegulatoryDomain(rustCode: output.domain),
            confidence: InferenceConfidence(rustCode: output.confidence),
            contributions: contributions,
            conflicts: conflicts
        )
    }
}
