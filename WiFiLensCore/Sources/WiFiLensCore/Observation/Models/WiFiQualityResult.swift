import Foundation

public struct WiFiQualityResult: Equatable, Sendable {
    public init(level: WiFiQualityLevel, signalLabel: String, latencyLabel: String, summary: String) {
        self.level = level; self.signalLabel = signalLabel; self.latencyLabel = latencyLabel; self.summary = summary
    }
    public var level: WiFiQualityLevel
    public var signalLabel: String
    public var latencyLabel: String
    public var summary: String
}

public enum WiFiQualityLevel: String, Sendable, CaseIterable {
    case good, fair, poor, unknown

    public var displayName: String {
        switch self {
        case .good:    String(localized: "observation.quality.good", comment: "Good quality level")
        case .fair:    String(localized: "observation.quality.fair", comment: "Fair quality level")
        case .poor:    String(localized: "observation.quality.poor", comment: "Poor quality level")
        case .unknown: String(localized: "observation.quality.unknown", comment: "Unknown quality level")
        }
    }
}
