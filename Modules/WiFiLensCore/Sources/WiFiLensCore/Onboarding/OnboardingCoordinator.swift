import Foundation
import Logging
import Observation

/// Process-wide owner of first-run welcome state. Manages the persisted
/// completion flag, the one-time existing-install migration, and the
/// single-host presentation claim so at most one main window can show the
/// welcome at a time. Never touches `GuidanceState`, `GuidanceCoordinator`,
/// Timeline, or any permission API.
@MainActor @Observable
public final class OnboardingCoordinator {
    /// The main window currently hosting the welcome, if any. Process-memory
    /// only; never persisted.
    public private(set) var welcomeHostID: UUID?

    /// Debug-only force-show request. Process-memory only.
    #if DEBUG
    public private(set) var debugShowRequested = false
    #endif

    private let store: any OnboardingStateStoring
    private let existingInstallationDetector: any ExistingInstallationDetecting
    private let welcomeEnabled: Bool

    public init(
        store: any OnboardingStateStoring,
        existingInstallationDetector: any ExistingInstallationDetecting,
        welcomeEnabled: Bool = true
    ) {
        self.store = store
        self.existingInstallationDetector = existingInstallationDetector
        self.welcomeEnabled = welcomeEnabled
    }

    public var hasCompletedWelcome: Bool {
        store.load().hasCompletedWelcome
    }

    // MARK: - Existing-install migration

    /// One-time migration that only runs while the onboarding key is absent,
    /// and always writes a result: `true` for a detected existing install,
    /// `false` for a clean install. Writing the key on the first launch
    /// permanently locks the classification, so a marker that appears later
    /// (e.g. Sparkle writing `SUEnableAutomaticChecks` after first launch)
    /// can never re-migrate an incomplete clean install into "completed".
    public func migrateExistingInstallationIfNeeded() {
        guard !store.hasStoredState() else { return }
        store.save(OnboardingState(
            hasCompletedWelcome: existingInstallationDetector.hasExistingInstallationEvidence()
        ))
    }

    // MARK: - Host claim (multi-window exclusivity)

    /// A host window claims the welcome. Only one host succeeds at a time;
    /// a later host is refused until the current host releases or completes.
    @discardableResult
    public func claimWelcome(hostID: UUID) -> Bool {
        guard welcomeEnabled else { return false }
        guard !hasCompletedWelcome else { return false }
        guard welcomeHostID == nil || welcomeHostID == hostID else { return false }
        welcomeHostID = hostID
        return true
    }

    /// Host disappeared without any explicit user action. Does not mark
    /// completion; a later host may claim again.
    public func releaseWelcome(hostID: UUID) {
        guard welcomeHostID == hostID else { return }
        welcomeHostID = nil
    }

    // MARK: - Completion

    /// `Start Analyzing`: marks complete and returns the route to navigate
    /// to exactly once.
    public func completeWelcomeStart(hostID: UUID, startRoute: SidebarPage?) -> SidebarPage? {
        guard welcomeHostID == hostID else { return nil }
        markCompleted()
        return startRoute
    }

    /// `Skip` or the explicit close button: marks complete without routing.
    public func completeWelcomeWithoutRouting(hostID: UUID) {
        guard welcomeHostID == hostID else { return }
        markCompleted()
    }

    /// OSS `Learn about WiFi Lens Pro`: completes only when the system
    /// accepted opening the campaign URL. On failure the welcome stays up
    /// and nothing is persisted.
    public func completeWelcomeAfterOpeningProURL(hostID: UUID, openedSuccessfully: Bool) {
        guard welcomeHostID == hostID else { return }
        guard openedSuccessfully else { return }
        markCompleted()
    }

    private func markCompleted() {
        var state = store.load()
        state.hasCompletedWelcome = true
        store.save(state)
        welcomeHostID = nil
    }

    // MARK: - Debug-only manual test entry points

    #if DEBUG
    /// Clears only onboarding state: the completion flag, any in-memory host
    /// claim, and any force-show request. Never touches guidance, Timeline,
    /// or user settings.
    public func debugReset() {
        store.save(OnboardingState())
        welcomeHostID = nil
        debugShowRequested = false
    }

    /// Requests the welcome regardless of completion or clean-install state.
    /// The actual sheet still goes through the real host claim and the real
    /// `WelcomeView`; the first visible main window consumes the request.
    public func debugRequestShowWelcome() {
        guard welcomeEnabled else { return }
        store.save(OnboardingState())
        welcomeHostID = nil
        debugShowRequested = true
    }

    public func consumeDebugShowRequest() -> Bool {
        guard debugShowRequested else { return false }
        debugShowRequested = false
        return true
    }

    /// Emits a sanitized state summary. No UUIDs, tokens, SSIDs, URLs, or
    /// user identity.
    public func debugLogState(edition: String) {
        let state = store.load()
        let hasHost = welcomeHostID != nil
        let hasExistingInstallation = existingInstallationDetector.hasExistingInstallationEvidence()
        var metadata = Logging.Logger.Metadata()
        metadata["edition"] = .string(edition)
        metadata["completed"] = .string(String(state.hasCompletedWelcome))
        metadata["pending"] = .string(String(hasHost))
        metadata["hasHost"] = .string(String(hasHost))
        metadata["existingInstallation"] = .string(String(hasExistingInstallation))
        Logging.Logger(label: "guidance").info("onboarding.debug.state_summary", metadata: metadata)
    }
    #endif
}
