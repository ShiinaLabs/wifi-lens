import Foundation

public enum OverviewVisualStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case globe
    case worldMap

    public static let storageKey = "overviewVisualStyle"

    public var id: String { rawValue }

    public static func fromPersistedValue(_ value: String) -> Self {
        Self(rawValue: value) ?? .system
    }

    public func resolved(reduceMotion: Bool) -> ResolvedStyle {
        switch self {
        case .system:
            reduceMotion ? .worldMap : .globe
        case .globe:
            .globe
        case .worldMap:
            .worldMap
        }
    }

    public enum ResolvedStyle: Equatable, Sendable {
        case globe
        case worldMap
    }
}
