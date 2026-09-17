import Foundation

enum OverviewVisualStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case globe
    case worldMap

    static let storageKey = "overviewVisualStyle"

    var id: String { rawValue }

    static func fromPersistedValue(_ value: String) -> Self {
        Self(rawValue: value) ?? .system
    }

    func resolved(reduceMotion: Bool) -> ResolvedStyle {
        switch self {
        case .system:
            reduceMotion ? .worldMap : .globe
        case .globe:
            .globe
        case .worldMap:
            .worldMap
        }
    }

    enum ResolvedStyle: Equatable, Sendable {
        case globe
        case worldMap
    }
}
