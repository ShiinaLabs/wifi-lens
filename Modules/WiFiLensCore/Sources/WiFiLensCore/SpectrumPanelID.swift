import Foundation

public struct SpectrumPanelID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: String { rawValue }

    public static let primary = SpectrumPanelID(rawValue: "primary")
    public static let secondary = SpectrumPanelID(rawValue: "secondary")
    public static let tertiary = SpectrumPanelID(rawValue: "tertiary")
}
