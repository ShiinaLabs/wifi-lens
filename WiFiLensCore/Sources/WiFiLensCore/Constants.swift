import Foundation
import SwiftUI

/// Runtime settings injected by the host app's build configuration.
/// An unconfigured host keeps the historical WiFi Lens defaults.
public struct AppEnvironment: Equatable, Sendable {
    public static let productionMCPPort = 19840

    public enum Kind: String, Sendable {
        case development
        case production
        case capture
    }

    public let kind: Kind
    public let bundleIdentity: String?
    public let displayName: String
    public let storageNamespace: String
    public let defaultMCPPort: Int
    public let mcpServerName: String
    public let isConfigured: Bool
    public let hasValidKind: Bool

    public var isDevelopment: Bool { kind == .development }
    public var isNonProduction: Bool { kind != .production }
    public func allowsMCPPort(_ port: Int) -> Bool {
        !isNonProduction || port != Self.productionMCPPort
    }
    public var loggingSubsystem: String {
        bundleIdentity ?? "com.kaoru.wifi-lens"
    }

    public init(
        environmentValue: String?,
        bundleIdentity: String?,
        displayName: String?,
        storageNamespace: String?,
        defaultMCPPort: Int?,
        mcpServerName: String?
    ) {
        let resolvedKind = environmentValue.flatMap(Kind.init(rawValue:))
        self.kind = resolvedKind ?? .production
        self.bundleIdentity = bundleIdentity
        self.displayName = displayName ?? "WiFi Lens"
        self.storageNamespace = storageNamespace ?? "WiFiLens"
        self.defaultMCPPort = defaultMCPPort ?? Self.productionMCPPort
        self.mcpServerName = mcpServerName ?? "wifi-lens"
        self.isConfigured = environmentValue != nil
        self.hasValidKind = environmentValue == nil || resolvedKind != nil
    }

    public static let current: AppEnvironment = {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppEnvironment(
            environmentValue: info["APP_ENVIRONMENT"] as? String,
            bundleIdentity: Bundle.main.bundleIdentifier,
            displayName: info["APP_DISPLAY_NAME"] as? String
                ?? info["CFBundleDisplayName"] as? String,
            storageNamespace: info["APP_STORAGE_NAMESPACE"] as? String,
            defaultMCPPort: integerValue(info["DEFAULT_MCP_PORT"]),
            mcpServerName: info["MCP_SERVER_NAME"] as? String
        )
    }()

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

public enum Constants {
    static let scanInterval: Duration = .seconds(3)
    static let uiUpdateInterval: Duration = .milliseconds(300)

    /// Visually distinct palette — each color is clearly separable at a glance.
    static let palette: [Color] = [
        Color(hex: "#3366CC"),  // blue
        Color(hex: "#DC3912"),  // red
        Color(hex: "#FF9900"),  // orange
        Color(hex: "#109618"),  // green
        Color(hex: "#990099"),  // purple
        Color(hex: "#0099C6"),  // cyan
        Color(hex: "#DD4477"),  // pink
        Color(hex: "#66AA00"),  // lime
        Color(hex: "#B82E2E"),  // brick
        Color(hex: "#316395"),  // steel
        Color(hex: "#994499"),  // mauve
        Color(hex: "#22AA99"),  // teal
        Color(hex: "#AAAA11"),  // olive
        Color(hex: "#6633CC"),  // indigo
        Color(hex: "#E67300"),  // amber
        Color(hex: "#329262"),  // forest
    ]

    static let graySSIDColor: Color = Color(hex: "#888888")
    static let filteredOutOpacity: Double = 0.15
    static let minZoomRange: Int = 2
    public static let rssiNoiseFloor: Int = -100
}
