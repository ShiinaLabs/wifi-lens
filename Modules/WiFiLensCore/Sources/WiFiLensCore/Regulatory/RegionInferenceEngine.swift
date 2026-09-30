import Foundation

/// Multi-source region inference with confidence scoring.
/// Resolves conflicts between system locale, hardware supported channels,
/// AP beacon country IEs, and user override.
enum RegionInferenceEngine {

    /// Fingerprint a set of supported channels against each known regulatory
    /// domain. Returns the domain whose allowed channel set most closely
    /// matches what the hardware reports.
    static func infer(
        systemLocale: Locale,
        supportedChannels: [(Int, Int)],  // (band raw value, channel number) — Sendable
        apCountryCodes: [String],
        userOverride: RegulatoryDomain?
    ) -> RegionInferenceResult {
        var contributions: [RegionSource] = []
        var conflicts: [RegionConflict] = []

        // 1. User override — always wins
        if let override = userOverride, override != .unknown {
            let source = RegionSource(kind: .userOverride, rawValue: override.rawValue, inferredDomain: override)
            contributions.append(source)
            // Still record what other sources would say
            let localeDomain = localeDomain(systemLocale)
            contributions.append(RegionSource(kind: .systemLocale, rawValue: systemLocale.region?.identifier ?? "nil", inferredDomain: localeDomain))
            if !apCountryCodes.isEmpty {
                let apDomain = apConsensus(apCountryCodes)
                contributions.append(RegionSource(kind: .apBeaconCountry, rawValue: apCountryCodes.joined(separator: ","), inferredDomain: apDomain.domain))
            }
            let chanDomain = channelFingerprint(supportedChannels)
            contributions.append(RegionSource(kind: .supportedChannels, rawValue: "\(supportedChannels.count) channels", inferredDomain: chanDomain))
            return RegionInferenceResult(domain: override, confidence: .high, contributions: contributions, conflicts: [])
        }

        // 2. Collect source candidates
        let localeCandidate = localeDomain(systemLocale)
        contributions.append(RegionSource(kind: .systemLocale, rawValue: systemLocale.region?.identifier ?? "nil", inferredDomain: localeCandidate))

        let apResult = apConsensus(apCountryCodes)
        if !apCountryCodes.isEmpty {
            contributions.append(RegionSource(kind: .apBeaconCountry, rawValue: apCountryCodes.joined(separator: ","), inferredDomain: apResult.domain))
        }

        let channelCandidate = channelFingerprint(supportedChannels)
        contributions.append(RegionSource(kind: .supportedChannels, rawValue: "\(supportedChannels.count) channels", inferredDomain: channelCandidate))

        // 3. Resolve
        let channelValid = channelCandidate != .unknown
        let apValid = apResult.domain != .unknown && !apCountryCodes.isEmpty
        let localeValid = localeCandidate != .unknown

        // Both strong signals agree → high confidence
        if channelValid && apValid && channelCandidate == apResult.domain {
            return RegionInferenceResult(
                domain: channelCandidate,
                confidence: .high,
                contributions: contributions,
                conflicts: conflicts
            )
        }

        // Channel fingerprint alone → medium (hardware/driver is authoritative)
        if channelValid {
            if apValid && channelCandidate != apResult.domain,
               let chanSource = contributions.first(where: { $0.kind == .supportedChannels }),
               let apSource = contributions.first(where: { $0.kind == .apBeaconCountry }) {
                conflicts.append(RegionConflict(
                    sourceA: chanSource,
                    sourceB: apSource,
                    resolution: "AP beacon disagrees with hardware supported channels; trusting hardware"
                ))
            }
            return RegionInferenceResult(
                domain: channelCandidate,
                confidence: .medium,
                contributions: contributions,
                conflicts: conflicts
            )
        }

        // AP consensus alone → medium (may be wrong — flashed routers, etc.)
        if apValid {
            return RegionInferenceResult(
                domain: apResult.domain,
                confidence: apResult.consensus ? .medium : .low,
                contributions: contributions,
                conflicts: apResult.conflict.map {
                    [RegionConflict(sourceA: $0.0, sourceB: $0.1, resolution: "AP country codes disagree")]
                } ?? []
            )
        }

        // Locale alone → low
        if localeValid {
            return RegionInferenceResult(
                domain: localeCandidate,
                confidence: .low,
                contributions: contributions,
                conflicts: []
            )
        }

        // Nothing useful
        return RegionInferenceResult(
            domain: .unknown,
            confidence: .low,
            contributions: contributions,
            conflicts: []
        )
    }

    // MARK: - Individual Sources

    private static func localeDomain(_ locale: Locale) -> RegulatoryDomain {
        RegulatoryDomain.from(localeRegionCode: locale.region?.identifier)
    }

    private static func apConsensus(_ codes: [String]) -> (domain: RegulatoryDomain, consensus: Bool, conflict: (RegionSource, RegionSource)?) {
        let normalized = codes.map { String($0.prefix(2)).uppercased() }
        let domains = normalized.compactMap { code -> RegulatoryDomain? in
            let d = RegulatoryDomain.from(localeRegionCode: code)
            return d == .unknown ? nil : d
        }
        guard !domains.isEmpty else { return (.unknown, false, nil) }

        let unique = Set(domains)
        if unique.count == 1 {
            return (unique.first!, true, nil)
        }

        // Conflict: take majority, or first if tie
        var counts: [RegulatoryDomain: Int] = [:]
        for d in domains { counts[d, default: 0] += 1 }
        guard let winner = counts.max(by: { $0.value < $1.value }) else {
            return (domains.first ?? .unknown, false, nil)
        }
        return (winner.key, false, nil)
    }

    /// Determine regulatory domain by comparing hardware-supported channels
    /// against each known region's allowed channel set to find the best match.
    private static func channelFingerprint(_ channels: [(Int, Int)]) -> RegulatoryDomain {
        guard !channels.isEmpty else { return .unknown }

        // Build set of "bandRaw-channelNumber" strings from hardware
        var hardwareChannels = Set<String>()
        for (bandRaw, ch) in channels {
            hardwareChannels.insert("\(bandRaw)-\(ch)")
        }

        var bestDomain: RegulatoryDomain = .unknown
        var bestScore: Double = 0

        for domain in [RegulatoryDomain.US, .JP, .CN, .EU] {
            guard let bandRules = RegulatoryDatabase.rules[domain] else { continue }

            // Build expected set from regulatory database
            var expectedChannels = Set<String>()
            for (bandID, rules) in bandRules {
                guard let bandRaw = bandToRaw(bandID) else { continue }
                for ch in rules.allowedChannels {
                    expectedChannels.insert("\(bandRaw)-\(ch)")
                }
            }

            guard !expectedChannels.isEmpty else { continue }

            // Jaccard-like: size of intersection / size of smaller set
            let intersection = expectedChannels.intersection(hardwareChannels)
            let score = Double(intersection.count) / Double(min(expectedChannels.count, hardwareChannels.count))

            // Bonus for uniquely-identifying channels
            // JP: channel 14 in 2.4 GHz
            if domain == .JP && hardwareChannels.contains("1-14") {
                bestScore = score + 0.15
                bestDomain = domain
            }

            if score > bestScore {
                bestScore = score
                bestDomain = domain
            }
        }

        // Also check for strong negative signals
        // CN: no DFS channels present → strong CN signal
        if bestDomain != .CN {
            let hasDFSChannels = hardwareChannels.contains { key in
                let parts = key.split(separator: "-")
                guard parts.count == 2, let ch = Int(parts[1]) else { return false }
                return (52...64).contains(ch) || (100...144).contains(ch)
            }
            if !hasDFSChannels && bestScore < 0.5 {
                // Could be CN (no DFS allocation); check CN match explicitly
                if let cnRules = RegulatoryDatabase.rules[.CN] {
                    var cnExpected = Set<String>()
                    for (bandID, rules) in cnRules {
                        guard let bandRaw = bandToRaw(bandID) else { continue }
                        for ch in rules.allowedChannels {
                            cnExpected.insert("\(bandRaw)-\(ch)")
                        }
                    }
                    let cnIntersection = cnExpected.intersection(hardwareChannels)
                    let cnScore = Double(cnIntersection.count) / Double(min(cnExpected.count, hardwareChannels.count))
                    if cnScore > bestScore {
                        bestScore = cnScore
                        bestDomain = .CN
                    }
                }
            }
        }

        return bestScore > 0.3 ? bestDomain : .unknown
    }

    private static func bandToRaw(_ id: String) -> Int? {
        switch id {
        case "24": return 1
        case "5":  return 2
        case "6":  return 3
        default:   return nil
        }
    }
}
