import SwiftUI

public struct DiagnosticResult: Equatable, Sendable {
    public init(icon: String, title: String, message: String, severity: DiagnosticSeverity) {
        self.icon = icon; self.title = title; self.message = message; self.severity = severity
    }
    public var icon: String
    public var title: String
    public var message: String
    public var severity: DiagnosticSeverity

    public static let unknown = DiagnosticResult(
        icon: "questionmark.circle",
        title: String(localized: "observation.diagnosis.unknown.title", comment: "Unknown diagnosis title"),
        message: String(localized: "observation.diagnosis.unknown.message", comment: "Unknown diagnosis message"),
        severity: .unknown
    )
}

public enum DiagnosticSeverity: String, Sendable, CaseIterable {
    case excellent, warning, critical, ok, unknown

    public var color: Color {
        switch self {
        case .excellent: return .green
        case .warning: return .orange
        case .critical: return .red
        case .ok: return .mint
        case .unknown: return .secondary
        }
    }
}
