@testable import WiFiLensCore

import Foundation
import Testing
@testable import WiFi_Lens

@MainActor
final class OnboardingCoordinatorTests {
    private var store: CountingOnboardingStateStore!
    private var detector: StubExistingInstallationDetector!
    private var coordinator: OnboardingCoordinator!

    // MARK: - Clean install and completion gating

    @Test func cleanInstallCanClaimWelcome() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let hostA = UUID()

        #expect(coordinator.claimWelcome(hostID: hostA) == true)
        #expect(coordinator.welcomeHostID == hostA)
    }

    @Test func completedUserCannotClaim() {
        let coordinator = makeCoordinator(
            initial: OnboardingState(hasCompletedWelcome: true),
            existingInstallation: false
        )

        #expect(coordinator.claimWelcome(hostID: UUID()) == false)
        #expect(coordinator.welcomeHostID == nil)
    }

    // MARK: - Multi-window exclusivity

    @Test func onlyOneHostClaimsAtATime() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let hostA = UUID()
        let hostB = UUID()

        #expect(coordinator.claimWelcome(hostID: hostA) == true)
        #expect(coordinator.claimWelcome(hostID: hostB) == false)
        #expect(coordinator.welcomeHostID == hostA)
    }

    @Test func hostDisappearingWithoutUserActionDoesNotComplete() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.releaseWelcome(hostID: host)

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func newHostCanClaimAfterRelease() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let hostA = UUID()
        let hostB = UUID()
        coordinator.claimWelcome(hostID: hostA)
        coordinator.releaseWelcome(hostID: hostA)

        #expect(coordinator.claimWelcome(hostID: hostB) == true)
        #expect(coordinator.welcomeHostID == hostB)
    }

    // MARK: - Completion semantics

    @Test func startMarksCompletedAndRoutesOnce() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        let first = coordinator.completeWelcomeStart(hostID: host, startRoute: .spectrum)
        let second = coordinator.completeWelcomeStart(hostID: host, startRoute: .overview)

        #expect(first == .spectrum)
        #expect(second == nil)
        #expect(coordinator.hasCompletedWelcome == true)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func skipMarksCompleted() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.completeWelcomeWithoutRouting(hostID: host)

        #expect(coordinator.hasCompletedWelcome == true)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func closeMarksCompleted() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.completeWelcomeWithoutRouting(hostID: host)

        #expect(coordinator.hasCompletedWelcome == true)
    }

    @Test func proURLOpenedSuccessfullyCompletes() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.completeWelcomeAfterOpeningProURL(hostID: host, openedSuccessfully: true)

        #expect(coordinator.hasCompletedWelcome == true)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func proURLOpenFailureDoesNotComplete() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.completeWelcomeAfterOpeningProURL(hostID: host, openedSuccessfully: false)

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(coordinator.welcomeHostID == host)
    }

    @Test func staleHostCannotComplete() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let hostA = UUID()
        let hostB = UUID()
        coordinator.claimWelcome(hostID: hostA)

        coordinator.completeWelcomeWithoutRouting(hostID: hostB)

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(coordinator.welcomeHostID == hostA)
    }

    // MARK: - Existing-install migration

    @Test func migrationSkipsWhenKeyAlreadyPresent() {
        let coordinator = makeCoordinator(
            initial: OnboardingState(hasCompletedWelcome: true),
            existingInstallation: true
        )

        coordinator.migrateExistingInstallationIfNeeded()

        #expect(coordinator.hasCompletedWelcome == true)
        #expect(store.saveCount == 0)
    }

    @Test func migrationCompletesForExistingInstall() {
        let coordinator = makeCoordinator(existingInstallation: true)

        coordinator.migrateExistingInstallationIfNeeded()

        #expect(coordinator.hasCompletedWelcome == true)
        #expect(store.saveCount == 1)
    }

    @Test func migrationWritesFalseForCleanInstall() {
        let coordinator = makeCoordinator(existingInstallation: false)

        coordinator.migrateExistingInstallationIfNeeded()

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(store.hasStoredState() == true)
        #expect(store.saveCount == 1)
    }

    @Test func migrationDoesNotRunWhenKeyPresentWithExplicitFalse() {
        let coordinator = makeCoordinator(
            initial: OnboardingState(hasCompletedWelcome: false),
            hasStoredState: true,
            existingInstallation: true
        )

        coordinator.migrateExistingInstallationIfNeeded()

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(store.saveCount == 0)
    }

    @Test func cleanInstallWriteFalseThenSparkleMarkerAppearsKeepsWelcome() {
        let coordinator = makeCoordinator(existingInstallation: false)

        // First launch: clean install writes an explicit false.
        coordinator.migrateExistingInstallationIfNeeded()
        #expect(coordinator.hasCompletedWelcome == false)
        #expect(store.saveCount == 1)

        // Sparkle writes SUEnableAutomaticChecks after first launch. A later
        // launch must not re-classify this install as an existing user.
        detector.evidence = true
        coordinator.migrateExistingInstallationIfNeeded()

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(store.saveCount == 1)
        #expect(coordinator.claimWelcome(hostID: UUID()) == true)
    }

    @Test func migrationRunsOnlyOnce() {
        let coordinator = makeCoordinator(existingInstallation: true)
        coordinator.migrateExistingInstallationIfNeeded()

        coordinator.migrateExistingInstallationIfNeeded()

        #expect(store.saveCount == 1)
    }

    @Test func onboardingDoesNotTouchGuidanceState() {
        let coordinator = makeCoordinator(existingInstallation: true)
        let guidanceStore = InMemoryGuidanceStateStore(initial: GuidanceState(
            meaningfulCompletionCount: 7,
            invitationPresentationCount: 2
        ))

        coordinator.migrateExistingInstallationIfNeeded()
        let host = UUID()
        coordinator.claimWelcome(hostID: host)
        coordinator.completeWelcomeWithoutRouting(hostID: host)

        let guidance = guidanceStore.load()
        #expect(guidance.meaningfulCompletionCount == 7)
        #expect(guidance.invitationPresentationCount == 2)
    }

    // MARK: - welcomeEnabled gating

    @Test func welcomeDisabledNeverClaims() {
        let coordinator = makeCoordinator(
            existingInstallation: false,
            welcomeEnabled: false
        )

        #expect(coordinator.claimWelcome(hostID: UUID()) == false)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func welcomeDisabledDebugShowDoesNotRequest() {
        let coordinator = makeCoordinator(
            existingInstallation: false,
            welcomeEnabled: false
        )

        coordinator.debugRequestShowWelcome()

        #expect(coordinator.consumeDebugShowRequest() == false)
    }

    // MARK: - Debug-only

    @Test func debugResetClearsOnlyOnboarding() {
        let coordinator = makeCoordinator(existingInstallation: false)
        let host = UUID()
        coordinator.claimWelcome(hostID: host)

        coordinator.debugReset()

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(coordinator.welcomeHostID == nil)
    }

    @Test func debugShowWelcomeBypassesCompletionAndMigration() {
        let coordinator = makeCoordinator(
            initial: OnboardingState(hasCompletedWelcome: true),
            existingInstallation: true
        )

        coordinator.debugRequestShowWelcome()

        #expect(coordinator.hasCompletedWelcome == false)
        #expect(coordinator.consumeDebugShowRequest() == true)
        #expect(coordinator.consumeDebugShowRequest() == false)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        initial: OnboardingState = OnboardingState(),
        hasStoredState: Bool? = nil,
        existingInstallation: Bool,
        welcomeEnabled: Bool = true
    ) -> OnboardingCoordinator {
        store = CountingOnboardingStateStore(
            initial: initial,
            hasStoredState: hasStoredState
        )
        detector = StubExistingInstallationDetector(evidence: existingInstallation)
        coordinator = OnboardingCoordinator(
            store: store,
            existingInstallationDetector: detector,
            welcomeEnabled: welcomeEnabled
        )
        return coordinator
    }
}

private final class StubExistingInstallationDetector: ExistingInstallationDetecting, @unchecked Sendable {
    var evidence: Bool

    init(evidence: Bool) {
        self.evidence = evidence
    }

    func hasExistingInstallationEvidence() -> Bool {
        evidence
    }
}

@MainActor
private final class CountingOnboardingStateStore: OnboardingStateStoring {
    private var state: OnboardingState
    private var stored: Bool
    private(set) var saveCount = 0

    init(initial: OnboardingState = OnboardingState(), hasStoredState: Bool? = nil) {
        state = initial
        stored = hasStoredState ?? initial.hasCompletedWelcome
    }

    func load() -> OnboardingState {
        state
    }

    func hasStoredState() -> Bool {
        stored
    }

    func save(_ state: OnboardingState) {
        saveCount += 1
        self.state = state
        stored = true
    }
}
