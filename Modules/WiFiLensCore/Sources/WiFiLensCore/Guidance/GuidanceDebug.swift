#if DEBUG
import Foundation

/// Debug-only, in-memory override of the Pro installation detection used by
/// the OSS invitation flow. Exists only for the current process: never
/// persisted, never uploaded, never included in Release builds.
public enum ProInstallationOverride: String, Equatable, Sendable {
    case useRealDetection
    case treatAsNotInstalled
    case treatAsInstalled
}

/// Debug-only holder for lifecycle-guidance manual-testing overrides.
/// The production installation checker is unchanged; the coordinator's
/// default detection closure consults this holder only in Debug builds.
@MainActor
public enum GuidanceDebugOverrides {
    public private(set) static var proInstallationOverride: ProInstallationOverride = .useRealDetection

    /// Debug-only request flag consumed atomically by the real diagnostics
    /// host. The Debug menu only sets the flag and navigates; the host that
    /// is actually on screen consumes it and stages its synthetic result.
    /// Never holds a reference to a view model or window.
    private static var pendingDiagnosticsStaging = false

    public static func setProInstallationOverride(_ override: ProInstallationOverride) {
        proInstallationOverride = override
    }

    public static func requestDiagnosticsStaging() {
        pendingDiagnosticsStaging = true
    }

    /// Consumed by the real `NetworkDiagnosticsView` host. Returns true at
    /// most once per request; a fresh window can consume a request that an
    /// older, closed window never did.
    public static func consumeDiagnosticsStaging() -> Bool {
        guard pendingDiagnosticsStaging else { return false }
        pendingDiagnosticsStaging = false
        return true
    }

    /// Cleared by `debugResetState()` so a stale request cannot stage into a
    /// future diagnostics host after a reset.
    public static func clearDiagnosticsStaging() {
        pendingDiagnosticsStaging = false
    }
}
#endif
