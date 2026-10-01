import Foundation
import Observation
import Logging

/// Manages What's New version-gated presentation. Tracks whether the current
/// version has been shown, and coordinates with Onboarding to avoid double-presentation
/// on first install.
@MainActor @Observable
public final class WhatsNewCoordinator {
    public static let shared = WhatsNewCoordinator(
        store: UserDefaultsWhatsNewStateStore(),
        bundle: .main
    )

    /// Whether the What's New sheet should be presented on launch.
    public private(set) var shouldShowSheet = false

    /// Manual re-view trigger from the Overview badge.
    public var showSheetFromBadge = false

    private let store: any WhatsNewStateStoring
    private let currentVersion: String

    init(
        store: any WhatsNewStateStoring,
        bundle: Bundle = .main
    ) {
        self.store = store
        self.currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Test-only initializer that accepts a version string directly.
    init(store: any WhatsNewStateStoring, currentVersion: String) {
        self.store = store
        self.currentVersion = currentVersion
    }

    /// Call on app launch, after Onboarding has had a chance to run.
    /// If the version differs from what was last seen, sets `shouldShowSheet`.
    public func checkForUpdate() {
        let stored = store.load().lastSeenVersion
        if stored != currentVersion {
            shouldShowSheet = true
        }
    }

    /// Called when the Onboarding Welcome flow completes on first install.
    /// Marks the current version as seen so What's New does not also appear.
    func markVersionSeenForOnboarding() {
        var state = store.load()
        state.lastSeenVersion = currentVersion
        store.save(state)
        shouldShowSheet = false
    }

    /// Called when the user dismisses the What's New sheet (either auto or manual).
    func markSeen() {
        var state = store.load()
        state.lastSeenVersion = currentVersion
        store.save(state)
        shouldShowSheet = false
        showSheetFromBadge = false
    }

    /// Dismiss without marking seen (e.g., sheet dismissed by system).
    public func dismiss() {
        shouldShowSheet = false
        showSheetFromBadge = false
    }

    /// The app version string displayed in the sheet.
    public var versionString: String {
        "WiFi Lens \(currentVersion)"
    }

    #if DEBUG
    private var debugForceShow = false

    public func debugRequestShow() {
        shouldShowSheet = true
    }

    public func debugReset() {
        store.save(WhatsNewState())
        shouldShowSheet = false
        showSheetFromBadge = false
    }
    #endif
}
