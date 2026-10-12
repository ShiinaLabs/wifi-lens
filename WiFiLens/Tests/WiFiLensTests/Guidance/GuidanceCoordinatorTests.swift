@testable import WiFiLensCore

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import WiFi_Lens

@MainActor
final class GuidanceCoordinatorTests {
    private var store: InMemoryGuidanceStateStore!
    private var collectedEvents: [GuidanceEvent] = []
    private var coordinator: GuidanceCoordinator!
    private var calendar: Calendar { Self.makeCalendar() }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12))!
    }

    // MARK: - Scheduling vs consumption

    @Test func schedulingInvitationPersistsOnlyCompletionCount() {
        let coordinator = makeCoordinator(state: invitationState())

        let decision = coordinator.recordAndReturnDecision(.diagnosticsCompleted)

        #expect(decision == .showProInvitation)
        #expect(coordinator.pendingInvitation != nil)
        let loaded = store.load()
        #expect(loaded.meaningfulCompletionCount == 3)
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.lastInvitationDate == nil)
    }

    @Test("value moments route to their App Store campaigns")
    func valueMomentsRouteToAppStoreCampaigns() throws {
        let coordinator = EditionAssemblyProvider.configuration.guidanceCoordinator
        let routings: [(moment: GuidanceValueMoment, campaign: String)] = [
            (.diagnosticsCompleted, "oss_diagnosis"),
            (.analysisLoaded, "oss_diagnosis"),
            (.roamingCompleted, "oss_diagnosis"),
            (.exportSucceeded, "oss_export"),
        ]

        for routing in routings {
            let url = try #require(coordinator.appStoreCampaignURL(for: routing.moment))
            let campaign = try #require(
                URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first { $0.name == "ct" }?
                    .value
            )
            #expect(campaign == routing.campaign)
        }
        let returnURL = try #require(coordinator.appStoreCampaignURL(for: .appReturnedAfterUse))
        #expect(URLComponents(url: returnURL, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ct" } == nil)
    }

    @Test func presentationConsumesCountAndDateIdempotently() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!

        coordinator.invitationPresented(id: invitation.id)
        coordinator.invitationPresented(id: invitation.id)

        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 1)
        #expect(loaded.lastInvitationDate == now)
        #expect(events(named: "guidance.invitation.presented").count == 1)
    }

    @Test func realClockPresentationStoresOneIdenticalTimestamp() {
        store = InMemoryGuidanceStateStore(initial: invitationState())
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!

        coordinator.invitationPresented(id: invitation.id)

        let loaded = store.load()
        #expect(loaded.invitationPresentationDates.count == 1)
        #expect(loaded.lastInvitationDate == loaded.invitationPresentationDates[0])
    }

    @Test func returnInvitationConsumesCooldownOnlyWhenMeaningfullyInsideScrollViewport() {
        #expect(GuidanceInvitationVisibility.isGenuinelyVisible(
            card: CGRect(x: 20, y: 100, width: 300, height: 100),
            viewport: CGRect(x: 0, y: 0, width: 400, height: 600)
        ))
        #expect(!GuidanceInvitationVisibility.isGenuinelyVisible(
            card: CGRect(x: 20, y: 610, width: 300, height: 100),
            viewport: CGRect(x: 0, y: 0, width: 400, height: 600)
        ))
        #expect(!GuidanceInvitationVisibility.isGenuinelyVisible(
            card: CGRect(x: 20, y: 580, width: 300, height: 100),
            viewport: CGRect(x: 0, y: 0, width: 400, height: 600)
        ))
        #expect(!GuidanceInvitationVisibility.isGenuinelyVisible(
            card: CGRect(x: 390, y: 100, width: 300, height: 100),
            viewport: CGRect(x: 0, y: 0, width: 400, height: 600)
        ))
    }

    // MARK: - Token gates (reachable state sequences)

    @Test func staleInvitationTokenCannotAffectNewerInvitation() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let a = coordinator.pendingInvitation!

        coordinator.openInvitation(id: a.id)
        #expect(coordinator.pendingInvitation == nil)

        // The next eligible moment schedules B — the only real path to a new
        // pending invitation while a host may still hold a stale rendered token.
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let b = coordinator.pendingInvitation!
        #expect(b.id != a.id)

        coordinator.invitationPresented(id: a.id)
        coordinator.dismissInvitation(id: a.id)
        coordinator.disableInvitations(id: a.id)
        coordinator.openInvitation(id: a.id)
        coordinator.endInvitationPresentation(id: a.id)

        #expect(coordinator.pendingInvitation?.id == b.id)
        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.invitationDismissalCount == 0)
        #expect(loaded.invitationsDisabled == false)
        #expect(loaded.lastInvitationDate == nil)
        #expect(events(named: "guidance.invitation.view_selected").map(\.tokenID) == [a.id])

        coordinator.dismissInvitation(id: b.id)
        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == 1)
    }

    @Test func dismissWithStaleOrNilPendingNeverCounts() {
        let coordinator = makeCoordinator(state: invitationState())

        coordinator.dismissInvitation(id: UUID())

        #expect(store.load().invitationDismissalCount == 0)
        #expect(events(named: "guidance.invitation.dismissed").isEmpty)
    }

    // MARK: - Host lifecycle

    @Test func unpresentedInvitationCancelsWithoutTrace() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!

        coordinator.endInvitationPresentation(id: invitation.id)

        #expect(coordinator.pendingInvitation == nil)
        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.invitationDismissalCount == 0)
        #expect(loaded.lastInvitationDate == nil)
        #expect(events(named: "guidance.invitation.cancelled").count == 1)
    }

    @Test func presentedInvitationWithoutChoiceConsumesAsLater() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!
        coordinator.invitationPresented(id: invitation.id)

        coordinator.endInvitationPresentation(id: invitation.id)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == 1)
        #expect(events(named: "guidance.invitation.dismissed").count == 1)
        #expect(events(named: "guidance.invitation.cancelled").isEmpty)
    }

    @Test func endingPresentedInvitationForOwningWindowRecordsLaterOnce() {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!
        coordinator.invitationPresented(id: invitation.id, ownerWindowID: owner)

        coordinator.endInvitation(forHostID: owner)
        coordinator.endInvitation(forHostID: owner)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationPresentationCount == 1)
        #expect(store.load().invitationDismissalCount == 1)
        #expect(store.load().lastInvitationDate == now)
        #expect(store.load().lastInvitationLaterDate == now)
        #expect(events(named: "guidance.invitation.dismissed").count == 1)
    }

    @Test(arguments: [false, true])
    func hostEndAfterUserChoiceDoesNotApplyChoiceTwice(openedPro: Bool) {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!

        if openedPro {
            coordinator.openInvitation(id: invitation.id, ownerWindowID: owner)
        } else {
            coordinator.dismissInvitation(id: invitation.id, ownerWindowID: owner)
        }
        coordinator.endInvitation(forHostID: owner)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == (openedPro ? 0 : 1))
        #expect(events(named: "guidance.invitation.dismissed").count == (openedPro ? 0 : 1))
        #expect(events(named: "guidance.invitation.view_selected").count == (openedPro ? 1 : 0))
    }

    @Test func endingUnseenInvitationForOwningWindowDoesNotRecordShowOrCooldown() {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.appReturnedAfterUse, ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!

        coordinator.endInvitation(forHostID: owner)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationPresentationCount == 0)
        #expect(store.load().invitationDismissalCount == 0)
        #expect(store.load().lastInvitationDate == nil)
        #expect(store.load().lastInvitationLaterDate == nil)
        #expect(events(named: "guidance.invitation.cancelled").map(\.tokenID) == [invitation.id])
    }

    @Test func nonOwningWindowCannotConfirmDismissOpenOrEndInvitation() {
        let owner = UUID()
        let otherWindow = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!

        coordinator.invitationPresented(id: invitation.id, ownerWindowID: otherWindow)
        coordinator.dismissInvitation(id: invitation.id, ownerWindowID: otherWindow)
        coordinator.openInvitation(id: invitation.id, ownerWindowID: otherWindow)
        coordinator.endInvitationPresentation(id: invitation.id, ownerWindowID: otherWindow)
        coordinator.endInvitation(forHostID: otherWindow)

        #expect(coordinator.pendingInvitation?.id == invitation.id)
        #expect(store.load().invitationPresentationCount == 0)
        #expect(store.load().invitationDismissalCount == 0)
        #expect(store.load().lastPurchaseExplorationDate == nil)

        coordinator.endInvitation(forHostID: owner)
        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == 0)
    }

    @Test func activatingDifferentWindowEndsOldOwnerInvitationWithoutStaleSlot() {
        let owner = UUID()
        let activeWindow = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!
        coordinator.invitationPresented(id: invitation.id, ownerWindowID: owner)

        coordinator.endInvitationOwnedByOtherHost(activeHostID: activeWindow)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == 1)
        #expect(events(named: "guidance.invitation.dismissed").count == 1)
        coordinator.endInvitationOwnedByOtherHost(activeHostID: activeWindow)
        #expect(store.load().invitationDismissalCount == 1)
    }

    @Test func closingOwnerWindowClearsInvitationAndExportFeedback() {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState())
        coordinator.handleExportSucceeded(ownerWindowID: owner)
        let invitation = coordinator.pendingInvitation!
        coordinator.invitationPresented(id: invitation.id, ownerWindowID: owner)

        coordinator.closeInvitationHost(forHostID: owner)

        #expect(coordinator.pendingInvitation == nil)
        #expect(coordinator.exportFeedback == nil)
        #expect(store.load().invitationDismissalCount == 1)
        coordinator.closeInvitationHost(forHostID: owner)
        #expect(store.load().invitationDismissalCount == 1)
    }

    @Test func inactiveOrClosedWindowCannotScheduleLateInvitation() {
        let owner = UUID()
        let otherWindow = UUID()
        let coordinator = makeCoordinator(state: invitationState())

        coordinator.endInvitationOwnedByOtherHost(activeHostID: otherWindow)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
                == .none(.invitationHostInactive))
        #expect(coordinator.pendingInvitation == nil)

        coordinator.closeInvitationHost(forHostID: owner)
        #expect(coordinator.recordAndReturnDecision(.exportSucceeded, ownerWindowID: owner)
                == .none(.invitationHostInactive))
        #expect(coordinator.pendingInvitation == nil)
        #expect(coordinator.exportFeedback == nil)
    }

    @Test(arguments: [GuidanceValueMoment.diagnosticsCompleted, .exportSucceeded])
    func endedReturnInvitationDoesNotBlockOwnedDiagnosticOrExportInvitation(_ moment: GuidanceValueMoment) {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState(completionCount: 0))
        _ = coordinator.recordAndReturnDecision(.appReturnedAfterUse, ownerWindowID: owner)
        coordinator.endInvitation(forHostID: owner)

        #expect(coordinator.recordAndReturnDecision(moment, ownerWindowID: owner) == .showProInvitation)
        #expect(coordinator.pendingInvitation?.moment == moment)
        #expect(coordinator.pendingInvitation?.ownerWindowID == owner)
    }

    @Test func historicalPermanentInvitationDisableStillBlocksLifecycleScheduling() {
        let owner = UUID()
        let coordinator = makeCoordinator(state: invitationState(invitationsDisabled: true))

        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner)
                == .none(.invitationsDisabledByUser))
        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationsDisabled)
    }

    @Test func disabledMarketingConfigurationKeepsSharedLifecycleInvitationInert() {
        var configuration = invitationConfig()
        configuration.localMarketingPolicyEnabled = false
        configuration.invitationEnabled = false
        let coordinator = makeCoordinator(configuration: configuration, state: invitationState())

        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: UUID())
                == .none(.editionInvitationDisabled))
        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationPresentationCount == 0)
    }

    // MARK: - Pending gates

    @Test func pendingInvitationBlocksNewInvitationScheduling() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)

        let decision = coordinator.recordAndReturnDecision(.diagnosticsCompleted)

        #expect(decision == .none(.invitationAlreadyPending))
        #expect(store.load().meaningfulCompletionCount == 4)
        #expect(coordinator.pendingInvitation != nil)
    }

    @Test func pendingReviewRequestBlocksNewReviewScheduling() {
        let coordinator = makeCoordinator(configuration: reviewConfig(), state: reviewState())
        _ = coordinator.recordAndReturnDecision(.analysisLoaded)

        let decision = coordinator.recordAndReturnDecision(.analysisLoaded)

        #expect(decision == .none(.reviewRequestPending))
        #expect(store.load().meaningfulCompletionCount == 6)
        #expect(coordinator.pendingReviewRequest != nil)
    }

    // MARK: - Review persistence timing and token

    @Test func reviewPersistenceHappensOnlyOnInvocation() {
        let coordinator = makeCoordinator(configuration: reviewConfig(), state: reviewState())
        _ = coordinator.recordAndReturnDecision(.analysisLoaded)
        let request = coordinator.pendingReviewRequest!

        var loaded = store.load()
        #expect(loaded.lastReviewRequestDate == nil)
        #expect(loaded.lastReviewRequestVersion == nil)

        coordinator.reviewRequestPresented(id: request.id)
        coordinator.reviewRequestPresented(id: request.id)

        loaded = store.load()
        #expect(loaded.lastReviewRequestDate == now)
        #expect(loaded.lastReviewRequestVersion == "2.1.0")
        #expect(events(named: "guidance.review.request_invoked").count == 1)

        let decision = coordinator.recordAndReturnDecision(.analysisLoaded)
        #expect(decision == .none(.reviewAlreadyRequestedForVersion))
        #expect(coordinator.pendingReviewRequest == nil)
    }

    @Test func staleReviewTokenIsNoOp() {
        let coordinator = makeCoordinator(configuration: reviewConfig(), state: reviewState())
        _ = coordinator.recordAndReturnDecision(.analysisLoaded)
        let request = coordinator.pendingReviewRequest!

        coordinator.reviewRequestPresented(id: UUID())

        #expect(coordinator.pendingReviewRequest?.id == request.id)
        let loaded = store.load()
        #expect(loaded.lastReviewRequestDate == nil)
        #expect(loaded.lastReviewRequestVersion == nil)
    }

    // MARK: - Quit before consumption

    @Test func quitBeforeConsumptionLeavesNoPersistedTrace() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)

        let fresh = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            now: { self.now },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { _ in }
        )

        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.lastInvitationDate == nil)

        let decision = fresh.recordAndReturnDecision(.diagnosticsCompleted)
        #expect(decision == .showProInvitation)
        #expect(fresh.pendingInvitation != nil)
    }

    // MARK: - Export feedback

    @Test func recordAppActiveIsIdempotentPerLocalDay() {
        let dayStart = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 8, minute: 30))!
        let dayEnd = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 23, minute: 30))!
        var current = dayStart
        store = InMemoryGuidanceStateStore()
        collectedEvents = []
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            now: { current },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )

        coordinator.recordAppActive()
        current = dayEnd
        coordinator.recordAppActive()

        let loaded = store.load()
        #expect(loaded.activeDays == ["2026-08-05"])
        #expect(loaded.firstLaunchDate == dayStart)
    }

    @Test func recordAppActiveDayBoundaryFollowsInjectedCalendar() {
        let dayOneLate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 23, minute: 59))!
        let dayTwoEarly = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 0, minute: 1))!
        var current = dayOneLate
        store = InMemoryGuidanceStateStore()
        collectedEvents = []
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            now: { current },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )

        coordinator.recordAppActive()
        current = dayTwoEarly
        coordinator.recordAppActive()

        #expect(store.load().activeDays == ["2026-08-05", "2026-08-06"])
    }

    @Test func handleExportSucceededPublishesFeedbackAndRecordsMoment() {
        let coordinator = makeCoordinator(state: invitationState(completionCount: 3))

        coordinator.handleExportSucceeded()

        #expect(coordinator.exportFeedback != nil)
        #expect(store.load().meaningfulCompletionCount == 4)
        #expect(coordinator.pendingInvitation != nil)
    }

    @Test func recordExportSucceededAloneNeverPublishesFeedback() {
        let coordinator = makeCoordinator(configuration: reviewConfig(), state: reviewState())

        _ = coordinator.recordAndReturnDecision(.exportSucceeded)

        #expect(coordinator.exportFeedback == nil)
        #expect(store.load().meaningfulCompletionCount == 5)
    }

    @Test func dismissExportFeedbackConsumesAttachedInvitationAsLater() throws {
        let coordinator = makeCoordinator(state: invitationState())
        coordinator.handleExportSucceeded()
        let invitation = try #require(coordinator.pendingInvitation)
        coordinator.invitationPresented(id: invitation.id)

        coordinator.dismissExportFeedback()

        #expect(coordinator.exportFeedback == nil)
        #expect(coordinator.pendingInvitation == nil)
        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 1)
        #expect(loaded.invitationDismissalCount == 1)
        #expect(loaded.lastInvitationDate == now)

        // A user choice prevents another invitation in the same active session.
        let decision = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        #expect(decision == .none(.invitationAlreadyShownThisSession))
    }

    @Test func dismissExportFeedbackBeforePresentationCancelsWithoutTrace() throws {
        let coordinator = makeCoordinator(state: invitationState())
        coordinator.handleExportSucceeded()
        _ = try #require(coordinator.pendingInvitation)

        coordinator.dismissExportFeedback()

        #expect(coordinator.exportFeedback == nil)
        #expect(coordinator.pendingInvitation == nil)
        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 0)
        #expect(loaded.invitationDismissalCount == 0)
        #expect(loaded.lastInvitationDate == nil)
        #expect(events(named: "guidance.invitation.cancelled").count == 1)
        #expect(events(named: "guidance.invitation.dismissed").isEmpty)
    }

    @Test func dismissExportFeedbackWithoutInvitationClearsFeedbackOnly() {
        let coordinator = makeCoordinator(configuration: GuidanceConfiguration(), state: invitationState(completionCount: 0))
        coordinator.handleExportSucceeded()
        #expect(coordinator.exportFeedback != nil)
        #expect(coordinator.pendingInvitation == nil)

        coordinator.dismissExportFeedback()

        #expect(coordinator.exportFeedback == nil)
        #expect(store.load().invitationDismissalCount == 0)
    }

    // MARK: - Invitation actions

    @Test func openInvitationEmitsViewSelectedAndClearsWithoutCount() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!

        coordinator.openInvitation(id: invitation.id)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationDismissalCount == 0)
        #expect(events(named: "guidance.invitation.view_selected").count == 1)
    }

    @Test func disableInvitationsPersistsAndClears() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!

        coordinator.disableInvitations(id: invitation.id)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationsDisabled == true)
        #expect(events(named: "guidance.invitation.disabled").count == 1)
    }

    // MARK: - Invitation card copy

    @Test func invitationCardCopySelectsPerMoment() {
        #expect(ProInvitationCard.messageKey(for: .diagnosticsCompleted) == "guidance.invitation.message.diagnostics")
        #expect(ProInvitationCard.messageKey(for: .exportSucceeded) == "guidance.invitation.message.export")
        #expect(ProInvitationCard.messageKey(for: .analysisLoaded) == "guidance.invitation.message.general")
        #expect(ProInvitationCard.messageKey(for: .roamingCompleted) == "guidance.invitation.message.general")
        #expect(ProInvitationCard.messageKey(for: .appReturnedAfterUse) == "guidance.invitation.message.general")
    }

    @Test func firstDiagnosticsCompletionCanInviteWithTwoActiveDays() {
        let coordinator = makeCoordinator(state: GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 0
        ))

        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)

        let invitation = coordinator.pendingInvitation
        #expect(invitation?.moment == .diagnosticsCompleted)
        let loaded = store.load()
        #expect(loaded.meaningfulCompletionCount == 1)
        #expect(loaded.invitationPresentationCount == 0)

        if let id = invitation?.id {
            coordinator.invitationPresented(id: id)
        }
        #expect(store.load().invitationPresentationCount == 1)
    }

    // MARK: - Events

    @Test func eventSinkCapturesValueMomentScheduledPresentedDismissed() {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = coordinator.pendingInvitation!
        coordinator.invitationPresented(id: invitation.id)
        coordinator.dismissInvitation(id: invitation.id)

        #expect(events(named: "guidance.value_moment").count == 1)
        #expect(events(named: "guidance.invitation.scheduled").count == 1)
        #expect(events(named: "guidance.invitation.presented").count == 1)
        #expect(events(named: "guidance.invitation.dismissed").count == 1)
    }

    @Test func eventSinkEmitsNoActionWithSuppressionReason() {
        let coordinator = makeCoordinator(state: invitationState(invitationsDisabled: true))

        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)

        let noAction = events(named: "guidance.no_action").first
        #expect(noAction?.suppressionReason == .invitationsDisabledByUser)
        #expect(noAction?.moment == .diagnosticsCompleted)
    }

    @Test func roamingRecordsValueMomentWithoutCompletion() {
        let coordinator = makeCoordinator(state: invitationState())

        _ = coordinator.recordAndReturnDecision(.roamingCompleted)

        #expect(store.load().meaningfulCompletionCount == 2)
        #expect(events(named: "guidance.no_action").first?.suppressionReason == .roamingPolicyNotEnabled)
        #expect(coordinator.pendingInvitation == nil)
    }

    @Test func roamingDoesNotCountButInvitationsDoNotNeedThreeCompletions() {
        let coordinator = makeCoordinator(state: invitationState(completionCount: 0))
        _ = coordinator.recordAndReturnDecision(.roamingCompleted)
        _ = coordinator.recordAndReturnDecision(.roamingCompleted)

        #expect(store.load().meaningfulCompletionCount == 0)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)
    }

    @Test func distinctStoreEntriesShareOnePendingInvitation() {
        let coordinator = makeCoordinator(state: invitationState())
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted) == .showProInvitation)
        #expect(coordinator.recordAndReturnDecision(.exportSucceeded) == .none(.invitationAlreadyPending))
    }

    @Test func effectiveForegroundTimeSchedulesReturnInvitationAtThirtySeconds() {
        var current = now
        store = InMemoryGuidanceStateStore(initial: invitationState(completionCount: 0))
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            now: { current },
            calendar: calendar,
            appVersion: { "2.0.1" },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )

        coordinator.recordForegroundUsageTick(isEligible: true)
        for _ in 0..<29 {
            current.addTimeInterval(1)
            coordinator.recordForegroundUsageTick(isEligible: true)
        }
        #expect(coordinator.pendingInvitation == nil)

        current.addTimeInterval(1)
        coordinator.recordForegroundUsageTick(isEligible: true)
        #expect(coordinator.pendingInvitation?.moment == .appReturnedAfterUse)
    }

    @Test func ineligibleTimeDoesNotContributeToReturnEvaluation() {
        var current = now
        store = InMemoryGuidanceStateStore(initial: invitationState(completionCount: 0))
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(),
            stateStore: store,
            now: { current },
            calendar: calendar,
            appVersion: { "2.0.1" },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )
        coordinator.recordForegroundUsageTick(isEligible: true)
        current.addTimeInterval(20)
        coordinator.recordForegroundUsageTick(isEligible: false)
        coordinator.recordForegroundUsageTick(isEligible: true)
        #expect(coordinator.pendingInvitation == nil)
        for _ in 0..<30 {
            current.addTimeInterval(1)
            coordinator.recordForegroundUsageTick(isEligible: true)
        }
        #expect(coordinator.pendingInvitation?.moment == .appReturnedAfterUse)
    }

    @Test func returnEvaluationWaitsForOverviewAndCanRetryOnLaterDays() {
        var current = now
        store = InMemoryGuidanceStateStore(initial: GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 0,
            invitationPresentationDates: [daysAgo(1), now]
        ))
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(), stateStore: store, now: { current }, calendar: calendar,
            appVersion: { "2.0.1" }, isProAppInstalled: { false }, eventSink: { _ in }
        )
        coordinator.recordForegroundUsageTick(isEligible: true, isOverviewSelected: false)
        for _ in 0..<30 {
            current.addTimeInterval(1)
            coordinator.recordForegroundUsageTick(isEligible: true, isOverviewSelected: false)
        }
        #expect(coordinator.pendingInvitation == nil)

        coordinator.recordForegroundUsageTick(isEligible: true, isOverviewSelected: true)
        #expect(coordinator.pendingInvitation == nil) // Weekly cap suppresses today's return.

        current = calendar.date(byAdding: .day, value: 7, to: current)!
        coordinator.recordForegroundUsageTick(isEligible: true, isOverviewSelected: true)
        #expect(coordinator.pendingInvitation?.moment == .appReturnedAfterUse)
    }

    @Test func cancelledUnseenReturnCanRescheduleOnceWithoutConsumingOpportunity() {
        var current = now
        store = InMemoryGuidanceStateStore(initial: invitationState(completionCount: 0))
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(), stateStore: store, now: { current }, calendar: calendar,
            appVersion: { "2.0.1" }, isProAppInstalled: { false }, eventSink: { self.collectedEvents.append($0) }
        )
        coordinator.recordForegroundUsageTick(isEligible: true)
        for _ in 0..<30 {
            current.addTimeInterval(1)
            coordinator.recordForegroundUsageTick(isEligible: true)
        }
        let first = coordinator.pendingInvitation!
        coordinator.endInvitationPresentation(id: first.id)
        #expect(store.load().invitationPresentationCount == 0)
        #expect(store.load().lastInvitationDate == nil)

        coordinator.recordForegroundUsageTick(isEligible: true)
        let retry = coordinator.pendingInvitation!
        #expect(retry.id != first.id)
        coordinator.endInvitationPresentation(id: retry.id)
        coordinator.recordForegroundUsageTick(isEligible: true)

        #expect(coordinator.pendingInvitation == nil)
        #expect(store.load().invitationPresentationCount == 0)
        #expect(events(named: "guidance.invitation.scheduled").count == 2)
    }

    @Test func onlySchedulingWindowCanCancelItsUnseenReturnInvitation() {
        var current = now
        store = InMemoryGuidanceStateStore(initial: invitationState(completionCount: 0))
        let coordinator = GuidanceCoordinator(
            configuration: invitationConfig(), stateStore: store, now: { current }, calendar: calendar,
            appVersion: { "2.0.1" }, isProAppInstalled: { false }, eventSink: { _ in }
        )
        let owner = UUID()
        coordinator.recordForegroundUsageTick(isEligible: true, hostID: owner)
        for _ in 0..<30 {
            current.addTimeInterval(1)
            coordinator.recordForegroundUsageTick(isEligible: true, hostID: owner)
        }
        let invitationID = coordinator.pendingInvitation?.id

        coordinator.endInvitation(forHostID: UUID())
        #expect(coordinator.pendingInvitation?.id == invitationID)
        coordinator.endInvitation(forHostID: owner)
        #expect(coordinator.pendingInvitation == nil)
    }

    @Test func leavingOverviewReleasesUnpresentedReturnInvitationSlot() {
        let coordinator = makeCoordinator(state: invitationState(completionCount: 0))
        let owner = UUID()
        _ = coordinator.recordAndReturnDecision(.appReturnedAfterUse, ownerWindowID: owner)
        let returnID = coordinator.pendingInvitation!.id
        coordinator.endInvitation(forHostID: owner)
        #expect(coordinator.pendingInvitation == nil)
        #expect(coordinator.recordAndReturnDecision(.diagnosticsCompleted, ownerWindowID: owner) == .showProInvitation)
        coordinator.invitationPresented(id: returnID)
        #expect(store.load().invitationPresentationCount == 0)
    }

    @Test(arguments: [GuidanceValueMoment.diagnosticsCompleted, .exportSucceeded])
    func unseenReturnInvitationDoesNotBlockHigherPriorityEntry(_ moment: GuidanceValueMoment) {
        let coordinator = makeCoordinator(state: invitationState(completionCount: 0))
        let owner = UUID()
        _ = coordinator.recordAndReturnDecision(.appReturnedAfterUse, ownerWindowID: owner)
        let returnID = coordinator.pendingInvitation!.id

        #expect(coordinator.recordAndReturnDecision(moment, ownerWindowID: owner) == .showProInvitation)
        #expect(coordinator.pendingInvitation?.moment == moment)
        coordinator.invitationPresented(id: returnID)
        #expect(store.load().invitationPresentationCount == 0)
    }

    @Test func previewAndSuccessfulStoreOpenPersistOnlyLocalInterestData() {
        let coordinator = makeCoordinator(state: invitationState())
        coordinator.recordProPreviewVisit(.spectrumRecording)
        coordinator.recordProPreviewVisit(.spectrumRecording)
        #expect(store.load().proInterestVisits.count == 1)
        #expect(store.load().lastPurchaseExplorationDate == nil)
        coordinator.recordSuccessfulStoreOpen()
        #expect(store.load().lastPurchaseExplorationDate == now)
        #expect(store.load().proInterestVisits.first?.category == .spectrumRecording)
    }

    @Test func successfulStoreHandoffRecordsIntentOnlyForOssMarketing() {
        let ossCoordinator = makeCoordinator(
            configuration: invitationConfig(),
            state: invitationState(invitationsDisabled: true)
        )
        ossCoordinator.recordSuccessfulStoreOpenIfMarketingEnabled()
        #expect(store.load().lastPurchaseExplorationDate == now)
        #expect(store.load().invitationsDisabled)

        var proConfiguration = invitationConfig()
        proConfiguration.localMarketingPolicyEnabled = false
        let proCoordinator = makeCoordinator(configuration: proConfiguration, state: invitationState())
        proCoordinator.recordSuccessfulStoreOpenIfMarketingEnabled()
        #expect(store.load().lastPurchaseExplorationDate == nil)
    }

    @Test func reviewEventsOncePerToken() {
        let coordinator = makeCoordinator(configuration: reviewConfig(), state: reviewState())
        _ = coordinator.recordAndReturnDecision(.analysisLoaded)
        let request = coordinator.pendingReviewRequest!
        coordinator.reviewRequestPresented(id: request.id)

        #expect(events(named: "guidance.review.scheduled").count == 1)
        #expect(events(named: "guidance.review.request_invoked").count == 1)
    }

    // MARK: - Export banner view

    @Test func exportBannerDoesNotConfirmWhileHostIsNotActuallyForeground() throws {
        let coordinator = makeCoordinator(state: invitationState(completionCount: 3))
        coordinator.handleExportSucceeded()
        let invitation = try #require(coordinator.pendingInvitation)
        #expect(invitation.moment == .exportSucceeded)

        let host = BannerHost { window in
            ExportSuccessBanner(guidance: coordinator, isInvitationHostActive: true, hostWindow: window)
        }
        host.flushLayout()

        #expect(store.load().invitationPresentationCount == 0)
        #expect(events(named: "guidance.invitation.presented").isEmpty)
    }

    @Test func exportBannerWithoutInvitationShowsFeedbackOnly() throws {
        let coordinator = makeCoordinator(configuration: GuidanceConfiguration(), state: invitationState(completionCount: 0))
        coordinator.handleExportSucceeded()
        #expect(coordinator.pendingInvitation == nil)

        let host = BannerHost { window in
            ExportSuccessBanner(guidance: coordinator, isInvitationHostActive: true, hostWindow: window)
        }
        host.flushLayout()

        #expect(events(named: "guidance.invitation.presented").isEmpty)
        #expect(store.load().invitationPresentationCount == 0)
    }

    @Test func exportBannerDisappearAfterPresentationConsumesAsLater() throws {
        let coordinator = makeCoordinator(state: invitationState())
        coordinator.handleExportSucceeded()
        let invitation = try #require(coordinator.pendingInvitation)
        coordinator.invitationPresented(id: invitation.id)

        let host = BannerHost { window in
            ExportSuccessBanner(guidance: coordinator, isInvitationHostActive: true, hostWindow: window)
        }
        host.flushLayout()
        #expect(store.load().invitationPresentationCount == 1)
        #expect(invitation.id == coordinator.pendingInvitation?.id)

        host.replace(with: EmptyView())

        #expect(coordinator.pendingInvitation == nil)
        let loaded = store.load()
        #expect(loaded.invitationPresentationCount == 1)
        #expect(loaded.invitationDismissalCount == 1)
        #expect(events(named: "guidance.invitation.dismissed").count == 1)
        #expect(events(named: "guidance.invitation.cancelled").isEmpty)
    }

    @Test func exportBannerNeverTouchesNonExportInvitation() throws {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = try #require(coordinator.pendingInvitation)
        coordinator.handleExportSucceeded()
        #expect(coordinator.pendingInvitation?.id == invitation.id)

        let host = BannerHost { window in
            ExportSuccessBanner(guidance: coordinator, isInvitationHostActive: true, hostWindow: window)
        }
        host.flushLayout()
        #expect(store.load().invitationPresentationCount == 0)

        host.replace(with: EmptyView())

        #expect(coordinator.pendingInvitation?.id == invitation.id)
        #expect(store.load().invitationDismissalCount == 0)
        #expect(events(named: "guidance.invitation.presented").isEmpty)
    }

    @Test func transparentInvitationHostDoesNotConfirmPresentation() throws {
        let coordinator = makeCoordinator(state: invitationState())
        _ = coordinator.recordAndReturnDecision(.diagnosticsCompleted)
        let invitation = try #require(coordinator.pendingInvitation)

        let host = BannerHost { window in
            ProInvitationCard(
                invitation: invitation,
                guidance: coordinator,
                isHostVisible: false,
                hostWindow: window
            )
            .onDisappear { coordinator.endInvitationPresentation(id: invitation.id) }
        }
        host.flushLayout()

        #expect(store.load().invitationPresentationCount == 0)
        #expect(events(named: "guidance.invitation.presented").isEmpty)
        host.replace(with: EmptyView())
        #expect(coordinator.pendingInvitation == nil)
        #expect(events(named: "guidance.invitation.cancelled").count == 1)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        configuration: GuidanceConfiguration? = nil,
        state: GuidanceState = GuidanceState(),
        appVersion: String = "2.1.0"
    ) -> GuidanceCoordinator {
        store = InMemoryGuidanceStateStore(initial: state)
        collectedEvents = []
        let coordinator = GuidanceCoordinator(
            configuration: configuration ?? invitationConfig(),
            stateStore: store,
            now: { self.now },
            calendar: calendar,
            appVersion: { appVersion },
            isProAppInstalled: { false },
            eventSink: { self.collectedEvents.append($0) }
        )
        self.coordinator = coordinator
        return coordinator
    }

    private func events(named name: String) -> [GuidanceEvent] {
        collectedEvents.filter { $0.name == name }
    }

    private func invitationConfig() -> GuidanceConfiguration {
        var config = GuidanceConfiguration()
        config.invitationEnabled = true
        config.minimumInvitationCompletions = 0
        config.minimumInvitationActiveDays = 2
        config.invitationCooldownDays = 7
        config.maxAutomaticInvitations = .max
        config.localMarketingPolicyEnabled = true
        return config
    }

    private func reviewConfig() -> GuidanceConfiguration {
        var config = GuidanceConfiguration()
        config.reviewEnabled = true
        return config
    }

    private func invitationState(completionCount: Int = 2, invitationsDisabled: Bool = false) -> GuidanceState {
        GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: completionCount,
            invitationsDisabled: invitationsDisabled
        )
    }

    private func reviewState(completionCount: Int = 4) -> GuidanceState {
        GuidanceState(
            firstLaunchDate: daysAgo(7),
            activeDays: ["2026-07-01", "2026-07-02", "2026-07-03"],
            meaningfulCompletionCount: completionCount
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

/// Hosts a SwiftUI view in a real window so `onAppear`/`onDisappear` fire the
/// way they do in the shipping app.
@MainActor
private final class BannerHost {
    private let window: NSWindow
    private let controller: NSHostingController<AnyView>

    init<Content: View>(content: (NSWindow) -> Content) {
        controller = NSHostingController(rootView: AnyView(EmptyView()))
        window = NSWindow(contentViewController: controller)
        controller.rootView = AnyView(content(window))
    }

    func flushLayout() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    func replace<Content: View>(with content: Content) {
        controller.rootView = AnyView(content)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
}
