import Foundation
import WiFiLensCoreRust

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
        let bytes = Array((localeRegionCode ?? "").utf8)
        let code = bytes.withUnsafeBufferPointer {
            wifi_lens_regulatory_domain_from_country_code($0.baseAddress, $0.count)
        }
        return Self(rustCode: code)
    }

    var rustCode: Int32 {
        switch self {
        case .unknown: WIFI_LENS_REGULATORY_DOMAIN_UNKNOWN
        case .US: WIFI_LENS_REGULATORY_DOMAIN_US
        case .JP: WIFI_LENS_REGULATORY_DOMAIN_JP
        case .CN: WIFI_LENS_REGULATORY_DOMAIN_CN
        case .EU: WIFI_LENS_REGULATORY_DOMAIN_EU
        }
    }

    init(rustCode: Int32) {
        self =
            switch rustCode {
            case WIFI_LENS_REGULATORY_DOMAIN_US: .US
            case WIFI_LENS_REGULATORY_DOMAIN_JP: .JP
            case WIFI_LENS_REGULATORY_DOMAIN_CN: .CN
            case WIFI_LENS_REGULATORY_DOMAIN_EU: .EU
            default: .unknown
            }
    }
}

// MARK: - Inference Confidence

enum InferenceConfidence: Comparable, Sendable {
    case high
    case medium
    case low

    var rustCode: Int32 {
        switch self {
        case .low: WIFI_LENS_REGULATORY_CONFIDENCE_LOW
        case .medium: WIFI_LENS_REGULATORY_CONFIDENCE_MEDIUM
        case .high: WIFI_LENS_REGULATORY_CONFIDENCE_HIGH
        }
    }

    init(rustCode: Int32) {
        self =
            switch rustCode {
            case WIFI_LENS_REGULATORY_CONFIDENCE_MEDIUM: .medium
            case WIFI_LENS_REGULATORY_CONFIDENCE_HIGH: .high
            default: .low
            }
    }

    public var label: String {
        switch self {
        case .high:
            String(localized: "wifi.inference.high_confidence", comment: "High confidence regulatory domain inference")
        case .medium:
            String(
                localized: "wifi.inference.medium_confidence", comment: "Medium confidence regulatory domain inference")
        case .low:
            String(localized: "wifi.inference.low_confidence", comment: "Low confidence regulatory domain inference")
        }
    }
}

// MARK: - Region Source

struct RegionSource: Sendable {
    enum Kind: String, Sendable {
        case systemLocale
        case supportedChannels
        case apBeaconCountry
        case userOverride
    }

    public let kind: Kind
    public let rawValue: String
    let inferredDomain: RegulatoryDomain?

    public var description: String {
        let domainStr = inferredDomain?.rawValue ?? "unknown"
        return "[\(kind.rawValue)] raw=\(rawValue) → \(domainStr)"
    }
}

// MARK: - Region Conflict

struct RegionConflict: Sendable {
    let sourceA: RegionSource
    let sourceB: RegionSource
    public let resolution: String
}

// MARK: - Inference Result

struct RegionInferenceResult: Sendable {
    public init(
        domain: RegulatoryDomain, confidence: InferenceConfidence, contributions: [RegionSource],
        conflicts: [RegionConflict]
    ) {
        self.domain = domain
        self.confidence = confidence
        self.contributions = contributions
        self.conflicts = conflicts
    }
    public let domain: RegulatoryDomain
    public let confidence: InferenceConfidence
    let contributions: [RegionSource]
    let conflicts: [RegionConflict]

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
    public init(
        supportsAX: Bool, supportsAC: Bool, supportsN: Bool, supportsBE: Bool, supports6GHz: Bool, supportsDFS: Bool,
        supports160MHz: Bool
    ) {
        self.supportsAX = supportsAX
        self.supportsAC = supportsAC
        self.supportsN = supportsN
        self.supportsBE = supportsBE
        self.supports6GHz = supports6GHz
        self.supportsDFS = supportsDFS
        self.supports160MHz = supports160MHz
    }
    let supportsAX: Bool
    let supportsAC: Bool
    let supportsN: Bool
    let supportsBE: Bool
    let supports6GHz: Bool
    let supportsDFS: Bool
    let supports160MHz: Bool

    public static let `default` = DevicePHYCapabilities(
        supportsAX: false,
        supportsAC: true,
        supportsN: true,
        supportsBE: false,
        supports6GHz: false,
        supportsDFS: true,
        supports160MHz: false
    )

    var phySummary: String {
        var parts: [String] = []
        if supportsBE { parts.append("be") }
        if supportsAX { parts.append("ax") }
        if supportsAC { parts.append("ac") }
        if supportsN { parts.append("n") }
        return parts.isEmpty ? "unknown" : parts.joined(separator: "/")
    }
}

extension RegulatoryDomain {
    public func allowedChannels(forBand band: String) -> Set<Int>? {
        RegulatoryDatabase.allowedChannels(for: self, band: band)
    }
}
