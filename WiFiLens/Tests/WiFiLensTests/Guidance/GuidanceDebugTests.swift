@testable import WiFiLensCore

import Foundation
import Testing
@testable import WiFi_Lens

@MainActor
final class GuidanceDebugTests {
    private var store: InMemoryGuidanceStateStore!
    private var collectedEvents: [GuidanceEvent] = []
    private var coordinator: GuidanceCoordinator!
    private var calendar: Calendar { Self.makeCalendar() }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12))!
    }

    // MARK: - Reset

    @Test func debugResetStateClearsPersistedStateAndPendingTokens() throws {
        let coordinator = makeCoordinator(state: GuidanceState(
            firstLaunchDate: now,
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 4,
            invitationPresentationCount: 2,
            invitationDismissalCount: 1,
            invitationsDisabled: true,
            lastReviewRequestDate: now,
            lastReviewRequestVersion: "2.1.0"
        ))
        // The disabled flag suppresses the policy path, so schedule through
        // the debug API to get a real pending token to reset.
        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)
        #expect(coordinator.pendingInvitation != nil)

        coordinator.debugResetState()

        #expect(coordinator.pendingInvitation == nil)
        #expect(coordinator.pendingReviewRequest == nil)
        #expect(coordinator.exportFeedback == nil)
        let loaded = store.load()
        #expect(loaded.firstLaunchDate == nil)
        #expect(loaded.activeDays.isEmpty)
        #expect(loaded.meaningfulCompletionCount == 0)
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.invitationDismissalCount == 0)
        #expect(loaded.invitationsDisabled == false)
        #expect(loaded.lastInvitationDate == nil)
        #expect(loaded.lastReviewRequestDate == nil)
        #expect(loaded.lastReviewRequestVersion == nil)
        #expect(events(named: "guidance.debug.state_reset").count == 1)
    }

    // MARK: - Eligibility seeding

    @Test func debugPrepareInvitationEligibilitySatisfiesPolicy() {
        let coordinator = makeCoordinator(state: GuidanceState())

        coordinator.debugPrepareInvitationEligibility()

        let loaded = store.load()
        #expect(loaded.meaningfulCompletionCount == 3)
        #expect(loaded.activeDays.count == 2)
        #expect(loaded.invitationsDisabled == false)
        #expect(loaded.lastInvitationDate == nil)
        #expect(events(named: "guidance.debug.invitation_eligibility_prepared").count == 1)

        // The next real value moment goes through the production policy.
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)
    }

    @Test func debugPrepareInvitationEligibilityUsesConfiguration() {
        var config = Self.invitationConfig()
        config.minimumInvitationActiveDays = 5
        let coordinator = makeCoordinator(configuration: config, state: GuidanceState())

        coordinator.debugPrepareInvitationEligibility()

        let loaded = store.load()
        #expect(loaded.activeDays.count == 5)
        #expect(loaded.meaningfulCompletionCount == config.minimumInvitationCompletions)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)
    }

    @Test func diagnosticsStagingIsConsumedAtomically() {
        defer { GuidanceDebugOverrides.clearDiagnosticsStaging() }
        #expect(GuidanceDebugOverrides.consumeDiagnosticsStaging() == false)

        GuidanceDebugOverrides.requestDiagnosticsStaging()

        #expect(GuidanceDebugOverrides.consumeDiagnosticsStaging() == true)
        #expect(GuidanceDebugOverrides.consumeDiagnosticsStaging() == false)
    }

    @Test func debugResetClearsPendingDiagnosticsStaging() {
        defer { GuidanceDebugOverrides.clearDiagnosticsStaging() }
        GuidanceDebugOverrides.requestDiagnosticsStaging()
        let coordinator = makeCoordinator(state: GuidanceState())

        coordinator.debugResetState()

        #expect(GuidanceDebugOverrides.consumeDiagnosticsStaging() == false)
    }

    // MARK: - Invitation scheduling (policy bypass, lifecycle intact)

    @Test func debugScheduleInvitationCreatesDiagnosticsToken() throws {
        let coordinator = makeCoordinator(state: GuidanceState())

        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)

        let invitation = try #require(coordinator.pendingInvitation)
        #expect(invitation.moment == .diagnosticsCompleted)
        // No completion count is written by the debug trigger.
        #expect(store.load().meaningfulCompletionCount == 0)
        #expect(events(named: "guidance.invitation.scheduled").count == 1)
        #expect(events(named: "guidance.debug.invitation_triggered").count == 1)
        // The injected sink still sees the token for lifecycle tests, but the
        // production metadata never carries it.
        let scheduled = try #require(events(named: "guidance.invitation.scheduled").first)
        #expect(scheduled.tokenID == invitation.id)
        #expect(scheduled.metadata["token"] == nil)

        // The card still confirms presentation through the production API.
        coordinator.invitationPresented(id: invitation.id)
        #expect(store.load().invitationPresentationCount == 1)
    }

    @Test func debugScheduleInvitationCreatesExportToken() throws {
        let coordinator = makeCoordinator(state: GuidanceState())

        coordinator.debugScheduleInvitation(for: .exportSucceeded)
        coordinator.debugPublishExportFeedback()

        let invitation = try #require(coordinator.pendingInvitation)
        #expect(invitation.moment == .exportSucceeded)
        #expect(coordinator.exportFeedback != nil)
    }

    @Test func debugScheduleRefusesWhenInvitationPending() throws {
        let coordinator = makeCoordinator(state: GuidanceState())
        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)
        let first = try #require(coordinator.pendingInvitation)

        coordinator.debugScheduleInvitation(for: .exportSucceeded)

        #expect(coordinator.pendingInvitation?.id == first.id)
        #expect(events(named: "guidance.debug.refused").first?.metadata["reason"] == "pending_invitation")
    }

    @Test func staleDebugTokenCannotConsumeNewerInvitation() throws {
        let coordinator = makeCoordinator(state: GuidanceState())
        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)
        let first = try #require(coordinator.pendingInvitation)

        coordinator.openInvitation(id: first.id)
        #expect(coordinator.pendingInvitation == nil)

        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)
        let second = try #require(coordinator.pendingInvitation)
        #expect(second.id != first.id)

        coordinator.invitationPresented(id: first.id)
        coordinator.dismissInvitation(id: first.id)
        coordinator.endInvitationPresentation(id: first.id)

        #expect(coordinator.pendingInvitation?.id == second.id)
        #expect(store.load().invitationPresentationCount == 0)
        #expect(store.load().invitationDismissalCount == 0)
    }

    // MARK: - Pro installation override

    @Test func proInstallationOverrideControlsPolicyAndIsNotPersisted() throws {
        defer { GuidanceDebugOverrides.setProInstallationOverride(.useRealDetection) }
        #expect(GuidanceDebugOverrides.proInstallationOverride == .useRealDetection)

        // Coordinator with the production default detection closure.
        let coordinator = makeCoordinatorWithDefaultDetection(state: GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 2
        ))

        GuidanceDebugOverrides.setProInstallationOverride(.treatAsInstalled)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .none(.proAppInstalled))
        #expect(coordinator.pendingInvitation == nil)

        GuidanceDebugOverrides.setProInstallationOverride(.treatAsNotInstalled)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)
        #expect(coordinator.pendingInvitation != nil)

        // The override never touches persisted state.
        let loaded = store.load()
        #expect(loaded.meaningfulCompletionCount == 4)
        #expect(loaded.activeDays == ["2026-07-01", "2026-07-02"])
        #expect(loaded.invitationPresentationCount == 0)
    }

    // MARK: - State logging

    @Test func debugLogStateEmitsSanitizedSummary() throws {
        let coordinator = makeCoordinator(state: GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 2
        ))
        coordinator.debugScheduleInvitation(for: .diagnosticsCompleted)

        coordinator.debugLogState(edition: "OSS")

        let summary = try #require(events(named: "guidance.debug.state_summary").first)
        let metadata = summary.metadata
        #expect(metadata["edition"] == "OSS")
        #expect(metadata["completionCount"] == "2")
        #expect(metadata["activeDayCount"] == "2")
        #expect(metadata["invitationPresentationCount"] == "0")
        #expect(metadata["invitationDismissalCount"] == "0")
        #expect(metadata["invitationsDisabled"] == "false")
        #expect(metadata["invitationCooldownActive"] == "false")
        #expect(metadata["hasReviewRequestHistory"] == "false")
        #expect(metadata["reviewConsumedForCurrentVersion"] == "false")
        #expect(metadata["hasPendingInvitation"] == "true")
        #expect(metadata["hasPendingReviewRequest"] == "false")
        #expect(metadata["proInstallationOverride"] == "useRealDetection")
        #expect(summary.tokenID == nil)

        // No sensitive or token data anywhere in the summary.
        let serialized = (Array(metadata.keys) + Array(metadata.values)).joined(separator: " ").lowercased()
        for forbidden in ["ssid", "bssid", "ip", "dns", "diagnostic", "uuid", "token"] {
            #expect(!serialized.contains(forbidden), "summary must not contain \(forbidden)")
        }
    }

    // MARK: - Helpers

    private func makeCoordinator(
        configuration: GuidanceConfiguration? = nil,
        state: GuidanceState = GuidanceState()
    ) -> GuidanceCoordinator {
        store = InMemoryGuidanceStateStore(initial: state)
        collectedEvents = []
        var config = configuration ?? Self.invitationConfig()
        if configuration == nil { config.invitationEnabled = true }
        let coordinator = GuidanceCoordinator(
            configuration: config,
            stateStore: store,
            now: { self.now },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )
        self.coordinator = coordinator
        return coordinator
    }

    private func makeCoordinatorWithDefaultDetection(
        configuration: GuidanceConfiguration? = nil,
        state: GuidanceState = GuidanceState()
    ) -> GuidanceCoordinator {
        store = InMemoryGuidanceStateStore(initial: state)
        collectedEvents = []
        var config = configuration ?? Self.invitationConfig()
        if configuration == nil { config.invitationEnabled = true }
        let coordinator = GuidanceCoordinator(
            configuration: config,
            stateStore: store,
            now: { self.now },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: {
                switch GuidanceDebugOverrides.proInstallationOverride {
                case .useRealDetection: return false
                case .treatAsNotInstalled: return false
                case .treatAsInstalled: return true
                }
            },
            eventSink: { self.collectedEvents.append($0) }
        )
        self.coordinator = coordinator
        return coordinator
    }

    private func events(named name: String) -> [GuidanceEvent] {
        collectedEvents.filter { $0.name == name }
    }

    private static func invitationConfig() -> GuidanceConfiguration {
        var config = GuidanceConfiguration()
        config.invitationEnabled = true
        return config
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
