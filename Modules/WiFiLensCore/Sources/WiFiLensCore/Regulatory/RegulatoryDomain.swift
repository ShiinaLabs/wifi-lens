import Foundation

// MARK: - Regulatory Domain

public enum RegulatoryDomain: String, CaseIterable, Codable, Sendable {
    case US
    case JP
    case CN
    case EU
    case unknown

    public var displayName: String {
        switch self {
        case .US: "United States (FCC)"
        case .JP: "Japan (MIC)"
        case .CN: "China (SRRC)"
        case .EU: "European Union (ETSI)"
        case .unknown: String(localized: "common.label.unknown", comment: "Generic unknown value label")
        }
    }

    /// Map a locale region identifier (ISO 3166-1 alpha-2) onto a regulatory domain.
    public static func from(localeRegionCode: String?) -> Self {
        guard let code = localeRegionCode?.uppercased() else { return .unknown }
        switch code {
        case "US", "CA", "MX": return .US
        case "JP": return .JP
        case "CN": return .CN
        case "GB", "DE", "FR", "IT", "ES", "NL", "BE", "SE", "DK", "FI",
             "PT", "IE", "AT", "PL", "CZ", "SK", "HU", "RO", "BG", "HR",
             "SI", "LT", "LV", "EE", "LU", "MT", "CY", "GR", "NO", "CH",
             "IS", "LI": return .EU
        default: return .unknown
        }
    }
}

// MARK: - Inference Confidence

public enum InferenceConfidence: Comparable, Sendable {
    case high
    case medium
    case low

    public var label: String {
        switch self {
        case .high: String(localized: "wifi.inference.high_confidence", comment: "High confidence regulatory domain inference")
        case .medium: String(localized: "wifi.inference.medium_confidence", comment: "Medium confidence regulatory domain inference")
        case .low: String(localized: "wifi.inference.low_confidence", comment: "Low confidence regulatory domain inference")
        }
    }
}

// MARK: - Region Source

public struct RegionSource: Sendable {
    public enum Kind: String, Sendable {
        case systemLocale
        case supportedChannels
        case apBeaconCountry
        case userOverride
    }

    public let kind: Kind
    public let rawValue: String
    public let inferredDomain: RegulatoryDomain?

    public var description: String {
        let domainStr = inferredDomain?.rawValue ?? "unknown"
        return "[\(kind.rawValue)] raw=\(rawValue) → \(domainStr)"
    }
}

// MARK: - Region Conflict

public struct RegionConflict: Sendable {
    public let sourceA: RegionSource
    public let sourceB: RegionSource
    public let resolution: String
}

// MARK: - Inference Result

public struct RegionInferenceResult: Sendable {
    public init(domain: RegulatoryDomain, confidence: InferenceConfidence, contributions: [RegionSource], conflicts: [RegionConflict]) {
        self.domain = domain
        self.confidence = confidence
        self.contributions = contributions
        self.conflicts = conflicts
    }
    public let domain: RegulatoryDomain
    public let confidence: InferenceConfidence
    public let contributions: [RegionSource]
    public let conflicts: [RegionConflict]

    public var summary: String {
        var lines = ["Region: \(domain.rawValue) (\(confidence.label))"]
        for c in contributions {
            lines.append("  ← \(c.description)")
        }
        for conflict in conflicts {
            lines.append("  ⚠ \(conflict.resolution)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Device PHY Capabilities

public struct DevicePHYCapabilities: Sendable {
    public init(supportsAX: Bool, supportsAC: Bool, supportsN: Bool, supportsBE: Bool, supports6GHz: Bool, supportsDFS: Bool, supports160MHz: Bool) {
        self.supportsAX = supportsAX
        self.supportsAC = supportsAC
        self.supportsN = supportsN
        self.supportsBE = supportsBE
        self.supports6GHz = supports6GHz
        self.supportsDFS = supportsDFS
        self.supports160MHz = supports160MHz
    }
    public let supportsAX: Bool
    public let supportsAC: Bool
    public let supportsN: Bool
    public let supportsBE: Bool
    public let supports6GHz: Bool
    public let supportsDFS: Bool
    public let supports160MHz: Bool

    public static let `default` = DevicePHYCapabilities(
        supportsAX: false,
        supportsAC: true,
        supportsN: true,
        supportsBE: false,
        supports6GHz: false,
        supportsDFS: true,
        supports160MHz: false
    )

    public var phySummary: String {
        var parts: [String] = []
        if supportsBE { parts.append("be") }
        if supportsAX { parts.append("ax") }
        if supportsAC { parts.append("ac") }
        if supportsN { parts.append("n") }
        return parts.isEmpty ? "unknown" : parts.joined(separator: "/")
    }
}

public extension RegulatoryDomain {
    func allowedChannels(forBand band: String) -> Set<Int>? {
        RegulatoryDatabase.allowedChannels(for: self, band: band)
    }
}
