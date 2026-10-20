import Foundation
import Logging
import Observation

/// One structured guidance event. `tokenID` is a process-memory UUID used by
/// tests to assert once-per-token behavior; the production log line never
/// carries the UUID or any derived prefix.
struct GuidanceEvent: Equatable, Sendable {
    public let name: String
    public let moment: GuidanceValueMoment?
    let tokenID: UUID?
    let suppressionReason: GuidanceSuppressionReason?
    public let metadata: [String: String]
}

/// Records value moments, schedules presentations in memory only, consumes
/// persisted counts only on real UI/system interaction via token-gated APIs,
/// publishes observable state, and emits structured events through an injected
/// sink. It never executes StoreKit and never presents UI.
@MainActor @Observable
public final class GuidanceCoordinator {
    struct InvitationPresentation: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let moment: GuidanceValueMoment
        public let scheduledAt: Date
        let acceleratedFollowUpExplorationDate: Date?
        let ownerWindowID: UUID?
    }

    public struct ReviewRequestPresentation: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let moment: GuidanceValueMoment
        public let scheduledAt: Date
    }

    struct ExportFeedback: Equatable {
        public let occurredAt: Date
        let ownerWindowID: UUID?
    }

    private(set) var pendingInvitation: InvitationPresentation?
    public private(set) var pendingReviewRequest: ReviewRequestPresentation?
    private(set) var exportFeedback: ExportFeedback?

    func appStoreCampaignURL(for moment: GuidanceValueMoment) -> URL? { campaignURL(moment) }

    private let configuration: GuidanceConfiguration
    private let stateStore: any GuidanceStateStoring
    private let now: () -> Date
    private let calendar: Calendar
    private let appVersion: () -> String
    private let isProAppInstalled: () -> Bool
    private let eventSink: (GuidanceEvent) -> Void
    private let campaignURL: (GuidanceValueMoment) -> URL?

    /// Invitation tokens whose first real `onAppear` was confirmed. Memory-only,
    /// used to make `invitationPresented(id:)` and `endInvitationPresentation(id:)`
    /// idempotent per token and to distinguish "cancelled unpresented" from
    /// "dismissed as Later".
    private var confirmedPresentedInvitationIDs: Set<UUID> = []
    private var lastPresentedInvitationUsageDay: Date?
    private var lastReturnEvaluationDate: Date?
    private var lastReturnCancellationRetryDate: Date?
    private var lastEligibleForegroundTick: Date?
    private var eligibleForegroundSeconds: TimeInterval = 0
    private var activeHostWindowID: UUID?
    private var closedHostWindowIDs: Set<UUID> = []

    public convenience init(
        configuration: GuidanceConfiguration,
        stateStore: UserDefaultsGuidanceStateStore,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        },
        isProAppInstalled: @escaping () -> Bool = { false },
        campaignURL: @escaping (GuidanceValueMoment) -> URL? = { _ in nil }
    ) {
        self.init(
            configuration: configuration,
            stateStore: stateStore as any GuidanceStateStoring,
            now: now,
            calendar: calendar,
            appVersion: appVersion,
            isProAppInstalled: isProAppInstalled,
            campaignURL: campaignURL
        )
    }

    init(
        configuration: GuidanceConfiguration,
        stateStore: any GuidanceStateStoring,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        },
        isProAppInstalled: @escaping () -> Bool = { false },
        campaignURL: @escaping (GuidanceValueMoment) -> URL? = { _ in nil },
        eventSink: @escaping (GuidanceEvent) -> Void = { event in
            var metadata = Logging.Logger.Metadata()
            for (key, value) in event.metadata {
                metadata[key] = .string(value)
            }
            Logging.Logger(label: "guidance").info("\(event.name)", metadata: metadata)
        }
    ) {
        self.configuration = configuration
        self.stateStore = stateStore
        self.now = now
        self.calendar = calendar
        self.appVersion = appVersion
        self.isProAppInstalled = isProAppInstalled
        self.campaignURL = campaignURL
        self.eventSink = eventSink
    }

    // MARK: - Recording

    public func record(
        _ moment: GuidanceValueMoment,
        ownerWindowID: UUID? = nil,
        invitationHostEligible: Bool = true
    ) {
        _ = recordAndReturnDecision(
            moment,
            ownerWindowID: ownerWindowID,
            invitationHostEligible: invitationHostEligible
        )
    }

    @discardableResult
    func recordAndReturnDecision(
        _ moment: GuidanceValueMoment,
        ownerWindowID: UUID? = nil,
        invitationHostEligible: Bool = true
    ) -> GuidanceDecision {
        var state = stateStore.load()

        if moment == .diagnosticsCompleted || moment == .exportSucceeded,
           let invitation = pendingInvitation,
           invitation.moment == .appReturnedAfterUse,
           !confirmedPresentedInvitationIDs.contains(invitation.id) {
            // A passive return prompt may wait below the Overview viewport. A
            // completed diagnostic/export has higher priority and must not be
            // blocked by a prompt the user has not actually seen. The pending
            // slot is global, so pre-empt regardless of which window owns the
            // prompt; otherwise a second window's diagnostic would be dropped
            // as `.invitationAlreadyPending` for as long as the unseen prompt
            // stays pending. Routing through the cancel path also grants the
            // one-retry-per-day allowance the cancellation semantics promise.
            endInvitationPresentation(id: invitation.id, ownerWindowID: invitation.ownerWindowID)
        }

        switch moment {
        case .diagnosticsCompleted, .exportSucceeded, .analysisLoaded:
            state.meaningfulCompletionCount += 1
        case .roamingCompleted, .appReturnedAfterUse:
            break
        }

        state.pruneLocalMarketingState(now: now(), calendar: calendar)
        let canInvite = moment == .diagnosticsCompleted || moment == .exportSucceeded || moment == .appReturnedAfterUse
        let canReview = moment == .diagnosticsCompleted || moment == .exportSucceeded || moment == .analysisLoaded

        let decision: GuidanceDecision
        if canInvite, pendingInvitation != nil {
            decision = .none(.invitationAlreadyPending)
        } else if canInvite, configuration.localMarketingPolicyEnabled,
                  lastPresentedInvitationUsageDay.map({ calendar.isDate($0, inSameDayAs: now()) }) == true {
            decision = .none(.invitationAlreadyShownThisSession)
        } else if canReview, pendingReviewRequest != nil {
            decision = .none(.reviewRequestPending)
        } else {
            let policyDecision = GuidancePolicy.decide(
                for: moment,
                state: state,
                config: configuration,
                now: now(),
                calendar: calendar,
                appVersion: appVersion(),
                isProAppInstalled: canInvite && configuration.invitationEnabled ? isProAppInstalled() : false
            )
            let ownerIsCurrent = ownerWindowID.map { ownerWindowID in
                !closedHostWindowIDs.contains(ownerWindowID)
                    && (activeHostWindowID.map { $0 == ownerWindowID } ?? true)
            } ?? true
            if case .showProInvitation = policyDecision,
               configuration.localMarketingPolicyEnabled,
               (!invitationHostEligible || !ownerIsCurrent) {
                decision = .none(.invitationHostInactive)
            } else {
                decision = policyDecision
            }
        }

        switch decision {
        case .showProInvitation:
            let invitation = InvitationPresentation(
                id: UUID(),
                moment: moment,
                scheduledAt: now(),
                acceleratedFollowUpExplorationDate: configuration.localMarketingPolicyEnabled && GuidanceInterestPolicy.canScheduleAcceleratedFollowUp(
                    state: state,
                    now: now(),
                    calendar: calendar
                ) ? state.lastPurchaseExplorationDate : nil,
                ownerWindowID: ownerWindowID
            )
            pendingInvitation = invitation
            emit("guidance.invitation.scheduled", moment: moment, tokenID: invitation.id)
        case .requestReview:
            let request = ReviewRequestPresentation(id: UUID(), moment: moment, scheduledAt: now())
            pendingReviewRequest = request
            emit("guidance.review.scheduled", moment: moment, tokenID: request.id)
        case let .none(reason):
            emit("guidance.no_action", moment: moment, suppressionReason: reason)
        }

        stateStore.save(state)
        emit(
            "guidance.value_moment",
            moment: moment,
            metadata: ["completionCount": String(state.meaningfulCompletionCount)]
        )
        return decision
    }

    /// Records a lightweight, privacy-safe Insight feedback signal through the
    /// same local event sink as other guidance events. Metadata carries only
    /// the rating and rule identifier; never network identity or device data.
    public func recordInsightFeedback(rating: String, ruleID: String) {
        emit(
            "analysis.insight_feedback",
            metadata: [
                "rating": rating,
                "rule": ruleID,
            ]
        )
    }

    public func recordAppActive() {
        var state = stateStore.load()
        if state.firstLaunchDate == nil {
            state.firstLaunchDate = now()
        }
        state.recordActiveDay(at: now(), calendar: calendar)
        if configuration.localMarketingPolicyEnabled {
            state.pruneLocalMarketingState(now: now(), calendar: calendar)
        }
        stateStore.save(state)
    }

    /// Receives one-second eligibility ticks from the OSS main-window host.
    /// Only time with an active, visible, uncovered main window is accumulated.
    public func recordForegroundUsageTick(
        isEligible: Bool,
        isOverviewSelected: Bool = true,
        hostID: UUID? = nil
    ) {
        guard isEligible else {
            lastEligibleForegroundTick = nil
            return
        }
        if let hostID { activeHostWindowID = hostID }
        let current = now()
        if let lastEligibleForegroundTick {
            eligibleForegroundSeconds += min(max(current.timeIntervalSince(lastEligibleForegroundTick), 0), 1.5)
        }
        lastEligibleForegroundTick = current
        guard eligibleForegroundSeconds >= 30, isOverviewSelected else { return }
        let today = calendar.startOfDay(for: current)
        guard lastReturnEvaluationDate.map({ calendar.startOfDay(for: $0) != today }) ?? true else { return }
        lastReturnEvaluationDate = current
        _ = recordAndReturnDecision(.appReturnedAfterUse, ownerWindowID: hostID)
    }

    /// Ends the invitation owned by a window when that window leaves its host
    /// lifecycle. Unseen invitations are cancelled without consuming a show;
    /// confirmed invitations are recorded as Later exactly once.
    public func endInvitation(forHostID hostID: UUID) {
        guard let invitation = pendingInvitation,
              invitation.ownerWindowID == hostID else { return }
        endInvitationPresentation(id: invitation.id, ownerWindowID: hostID)
    }

    /// A single global slot cannot remain attached to an inactive window after
    /// another main window becomes active. Only the new active host may trigger
    /// this cleanup; the old window cannot end another host's invitation.
    public func endInvitationOwnedByOtherHost(activeHostID: UUID) {
        self.activeHostWindowID = activeHostID
        if let invitation = pendingInvitation,
           let ownerWindowID = invitation.ownerWindowID,
           ownerWindowID != activeHostID {
            endInvitationPresentation(id: invitation.id, ownerWindowID: ownerWindowID)
        }
        if let ownerWindowID = exportFeedback?.ownerWindowID,
           ownerWindowID != activeHostID {
            exportFeedback = nil
        }
    }

    public func closeInvitationHost(forHostID hostID: UUID) {
        endInvitation(forHostID: hostID)
        if exportFeedback?.ownerWindowID == hostID {
            exportFeedback = nil
        }
        if activeHostWindowID == hostID {
            activeHostWindowID = nil
        }
        closedHostWindowIDs.insert(hostID)
    }

    private func allowOneReturnRetryAfterCancellation(at date: Date) {
        let today = calendar.startOfDay(for: date)
        guard lastReturnCancellationRetryDate.map({ calendar.startOfDay(for: $0) != today }) ?? true else { return }
        lastReturnCancellationRetryDate = date
        lastReturnEvaluationDate = nil
    }

    /// Records only a feature category and local calendar date after a preview
    /// has remained visible long enough to count as an intentional visit.
    public func recordProPreviewVisit(_ category: ProInterestCategory) {
        var state = stateStore.load()
        state.pruneLocalMarketingState(now: now(), calendar: calendar)
        state.recordProInterest(category, at: now(), calendar: calendar)
        stateStore.save(state)
    }

    /// Called only after the operating system accepts a Store request.
    public func recordSuccessfulStoreOpen() {
        var state = stateStore.load()
        state.lastPurchaseExplorationDate = now()
        stateStore.save(state)
    }

    /// Records a successful Store handoff for editions that enable local OSS
    /// marketing. Shared welcome/settings surfaces can call this safely in Pro,
    /// where the policy remains disabled.
    public func recordSuccessfulStoreOpenIfMarketingEnabled() {
        guard configuration.localMarketingPolicyEnabled else { return }
        recordSuccessfulStoreOpen()
    }

    func invitationMessageKey(for moment: GuidanceValueMoment) -> String {
        var state = stateStore.load()
        state.pruneLocalMarketingState(now: now(), calendar: calendar)
        return GuidanceContentSelector.messageKey(for: moment, state: state, now: now(), calendar: calendar)
    }

    // MARK: - Export feedback

    /// Feedback published without a resolved owning window belongs to whichever
    /// window renders the banner. Without this, an export that completed while
    /// no window could be resolved would publish feedback that no host can ever
    /// match, silently dropping the success confirmation.
    private func feedbackOwnerMatches(_ owner: UUID?, _ windowID: UUID?) -> Bool {
        guard let owner else { return true }
        return owner == windowID
    }

    func matchingExportFeedback(ownerWindowID: UUID?) -> ExportFeedback? {
        guard let exportFeedback,
              feedbackOwnerMatches(exportFeedback.ownerWindowID, ownerWindowID) else { return nil }
        return exportFeedback
    }

    func handleExportSucceeded(ownerWindowID: UUID? = nil) {
        let ownerIsOpen = ownerWindowID.map { !closedHostWindowIDs.contains($0) } ?? true
        record(
            .exportSucceeded,
            ownerWindowID: ownerWindowID,
            invitationHostEligible: ownerIsOpen
        )
        guard ownerIsOpen else { return }
        exportFeedback = ExportFeedback(occurredAt: now(), ownerWindowID: ownerWindowID)
    }

    func dismissExportFeedback(ownerWindowID: UUID? = nil) {
        guard let exportFeedback,
              feedbackOwnerMatches(exportFeedback.ownerWindowID, ownerWindowID) else { return }
        self.exportFeedback = nil
        // Only the invitation published alongside this feedback may be ended,
        // so a window cannot end another window's export invitation.
        if let invitation = pendingInvitation,
           invitation.moment == .exportSucceeded,
           invitation.ownerWindowID == exportFeedback.ownerWindowID {
            endInvitationPresentation(id: invitation.id, ownerWindowID: invitation.ownerWindowID)
        }
    }

    // MARK: - Invitation consumption (token-gated)

    func invitationPresented(id: UUID, ownerWindowID: UUID? = nil) {
        guard let invitation = pendingInvitation,
              invitation.id == id,
              invitation.ownerWindowID == ownerWindowID else { return }
        guard !confirmedPresentedInvitationIDs.contains(id) else { return }
        confirmedPresentedInvitationIDs.insert(id)
        var state = stateStore.load()
        state.invitationPresentationCount += 1
        let presentedAt = now()
        state.lastInvitationDate = presentedAt
        state.recordInvitationPresentation(at: presentedAt)
        lastPresentedInvitationUsageDay = presentedAt
        if let explorationDate = invitation.acceleratedFollowUpExplorationDate {
            state.lastAcceleratedFollowUpDate = presentedAt
            state.lastAcceleratedFollowUpExplorationDate = explorationDate
        }
        stateStore.save(state)
        emit("guidance.invitation.presented", moment: invitation.moment, tokenID: id)
    }

    func dismissInvitation(id: UUID, ownerWindowID: UUID? = nil) {
        guard let invitation = pendingInvitation,
              invitation.id == id,
              invitation.ownerWindowID == ownerWindowID else { return }
        pendingInvitation = nil
        var state = stateStore.load()
        state.invitationDismissalCount += 1
        state.lastInvitationLaterDate = now()
        stateStore.save(state)
        emit("guidance.invitation.dismissed", moment: invitation.moment, tokenID: id)
    }

    func disableInvitations(id: UUID, ownerWindowID: UUID? = nil) {
        guard let invitation = pendingInvitation,
              invitation.id == id,
              invitation.ownerWindowID == ownerWindowID else { return }
        pendingInvitation = nil
        var state = stateStore.load()
        state.invitationsDisabled = true
        stateStore.save(state)
        emit("guidance.invitation.disabled", moment: invitation.moment, tokenID: id)
    }

    func openInvitation(id: UUID, ownerWindowID: UUID? = nil) {
        guard let invitation = pendingInvitation,
              invitation.id == id,
              invitation.ownerWindowID == ownerWindowID else { return }
        pendingInvitation = nil
        var state = stateStore.load()
        state.lastPurchaseExplorationDate = now()
        stateStore.save(state)
        emit("guidance.invitation.view_selected", moment: invitation.moment, tokenID: id)
    }

    /// Host-lifecycle end. An unpresented invitation is cancelled without any
    /// count or cooldown; a presented one without a user choice is consumed as
    /// Later. Both token and owner must match, so another window cannot act on it.
    func endInvitationPresentation(id: UUID, ownerWindowID: UUID? = nil) {
        guard let invitation = pendingInvitation,
              invitation.id == id,
              invitation.ownerWindowID == ownerWindowID else { return }
        pendingInvitation = nil
        if confirmedPresentedInvitationIDs.contains(id) {
            var state = stateStore.load()
            state.invitationDismissalCount += 1
            state.lastInvitationLaterDate = now()
            stateStore.save(state)
            emit("guidance.invitation.dismissed", moment: invitation.moment, tokenID: id)
        } else {
            if invitation.moment == .appReturnedAfterUse {
                allowOneReturnRetryAfterCancellation(at: now())
            }
            emit("guidance.invitation.cancelled", moment: invitation.moment, tokenID: id)
        }
    }

    // MARK: - Review consumption (token-gated)

    public func reviewRequestPresented(id: UUID) {
        guard let request = pendingReviewRequest, request.id == id else { return }
        pendingReviewRequest = nil
        var state = stateStore.load()
        state.lastReviewRequestDate = now()
        state.lastReviewRequestVersion = appVersion()
        stateStore.save(state)
        emit("guidance.review.request_invoked", moment: request.moment, tokenID: id)
    }

    // MARK: - Events

    private func emit(
        _ name: String,
        moment: GuidanceValueMoment? = nil,
        tokenID: UUID? = nil,
        suppressionReason: GuidanceSuppressionReason? = nil,
        metadata: [String: String] = [:]
    ) {
        var metadata = metadata
        if let moment {
            metadata["moment"] = moment.rawValue
        }
        if let suppressionReason {
            metadata["reason"] = suppressionReason.rawValue
        }
        eventSink(
            GuidanceEvent(
                name: name,
                moment: moment,
                tokenID: tokenID,
                suppressionReason: suppressionReason,
                metadata: metadata
            )
        )
    }
}

#if DEBUG
extension GuidanceCoordinator {
    // MARK: - Debug-only manual test entry points
    //
    // These APIs exist only in Debug builds. They may bypass the eligibility
    // policy for manual testing, but they never bypass the token lifecycle:
    // every schedule creates a fresh UUID token, respects the pending gate,
    // and is consumed only through the existing presentation/consume/cancel
    // APIs. Nothing here is persisted, uploaded, or included in Release.

    /// Clears every persisted guidance field and every pending in-memory
    /// presentation.
    public func debugResetState() {
        pendingInvitation = nil
        pendingReviewRequest = nil
        confirmedPresentedInvitationIDs.removeAll()
        exportFeedback = nil
        GuidanceDebugOverrides.clearDiagnosticsStaging()
        stateStore.save(GuidanceState())
        emit("guidance.debug.state_reset")
    }

    /// Clears review-eligibility state (persisted review fields, completion
    /// count, active days, first-launch age) and the pending review request,
    /// preserving the (inert in Pro) invitation fields.
    public func debugResetReviewState() {
        pendingReviewRequest = nil
        let current = stateStore.load()
        stateStore.save(GuidanceState(
            firstLaunchDate: nil,
            activeDays: [],
            meaningfulCompletionCount: 0,
            lastInvitationDate: current.lastInvitationDate,
            invitationPresentationCount: current.invitationPresentationCount,
            invitationDismissalCount: current.invitationDismissalCount,
            invitationsDisabled: current.invitationsDisabled
        ))
        emit("guidance.debug.review_state_reset")
    }

    /// Seeds persisted state to exactly meet the invitation policy, so the
    /// next real value moment schedules an invitation through the production
    /// policy path. Refuses while an invitation is already pending.
    public func debugPrepareInvitationEligibility() {
        guard pendingInvitation == nil else {
            emit("guidance.debug.refused", metadata: ["reason": "pending_invitation"])
            return
        }
        var state = GuidanceState()
        let now = now()
        for daysAgo in 0..<configuration.minimumInvitationActiveDays {
            if let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) {
                state.recordActiveDay(at: day, calendar: calendar)
            }
        }
        state.meaningfulCompletionCount = configuration.minimumInvitationCompletions
        stateStore.save(state)
        emit("guidance.debug.invitation_eligibility_prepared")
    }

    /// Seeds persisted state to exactly meet the review policy, so the next
    /// real value moment schedules a review request through the production
    /// policy path. Refuses while a review request is already pending.
    public func debugPrepareReviewEligibility() {
        guard pendingReviewRequest == nil else {
            emit("guidance.debug.refused", metadata: ["reason": "pending_review"])
            return
        }
        var state = GuidanceState()
        let now = now()
        state.firstLaunchDate = calendar.date(
            byAdding: .day,
            value: -configuration.minimumReviewAgeDays,
            to: now
        )
        for daysAgo in 0..<configuration.minimumReviewActiveDays {
            if let day = calendar.date(byAdding: .day, value: -daysAgo, to: now) {
                state.recordActiveDay(at: day, calendar: calendar)
            }
        }
        state.meaningfulCompletionCount = configuration.minimumReviewCompletions
        stateStore.save(state)
        emit("guidance.debug.review_eligibility_prepared")
    }

    /// Force-schedules an invitation for a supported moment, bypassing the
    /// policy but keeping the pending gate and token lifecycle intact.
    public func debugScheduleInvitation(for moment: GuidanceValueMoment, ownerWindowID: UUID? = nil) {
        guard moment == .diagnosticsCompleted || moment == .exportSucceeded else {
            emit("guidance.debug.refused", metadata: ["reason": "unsupported_moment"])
            return
        }
        guard pendingInvitation == nil else {
            emit("guidance.debug.refused", metadata: ["reason": "pending_invitation"])
            return
        }
        let resolvedOwnerWindowID = ownerWindowID ?? activeHostWindowID
        let invitation = InvitationPresentation(
            id: UUID(),
            moment: moment,
            scheduledAt: now(),
            acceleratedFollowUpExplorationDate: nil,
            ownerWindowID: resolvedOwnerWindowID
        )
        pendingInvitation = invitation
        emit("guidance.invitation.scheduled", moment: moment, tokenID: invitation.id)
        emit("guidance.debug.invitation_triggered", moment: moment, tokenID: invitation.id)
    }

    /// Force-schedules a review request, bypassing the policy but keeping the
    /// pending gate and token lifecycle intact. Consumed only by the real
    /// Pro-only bridge; never by direct StoreKit calls.
    public func debugScheduleReview(for moment: GuidanceValueMoment) {
        guard moment != .roamingCompleted else {
            emit("guidance.debug.refused", metadata: ["reason": "unsupported_moment"])
            return
        }
        guard pendingReviewRequest == nil else {
            emit("guidance.debug.refused", metadata: ["reason": "pending_review"])
            return
        }
        let request = ReviewRequestPresentation(id: UUID(), moment: moment, scheduledAt: now())
        pendingReviewRequest = request
        emit("guidance.review.scheduled", moment: moment, tokenID: request.id)
        emit("guidance.debug.review_triggered", moment: moment, tokenID: request.id)
    }

    /// Publishes export feedback so the real OSS banner host renders, without
    /// running a real file save.
    public func debugPublishExportFeedback(ownerWindowID: UUID? = nil) {
        let resolvedOwnerWindowID = ownerWindowID ?? pendingInvitation?.ownerWindowID ?? activeHostWindowID
        exportFeedback = ExportFeedback(occurredAt: now(), ownerWindowID: resolvedOwnerWindowID)
        emit("guidance.debug.export_feedback_published")
    }

    /// Emits a sanitized state summary for local Debug logs. Contains no
    /// UUIDs, SSIDs, BSSIDs, IPs, DNS data, or diagnostic results.
    public func debugLogState(edition: String) {
        let state = stateStore.load()
        var metadata: [String: String] = [
            "edition": edition,
            "completionCount": String(state.meaningfulCompletionCount),
            "activeDayCount": String(state.activeDays.count),
            "invitationPresentationCount": String(state.invitationPresentationCount),
            "invitationDismissalCount": String(state.invitationDismissalCount),
            "invitationsDisabled": String(state.invitationsDisabled),
            "hasReviewRequestHistory": String(state.lastReviewRequestDate != nil),
            "reviewConsumedForCurrentVersion": String(state.lastReviewRequestVersion == appVersion()),
            "hasPendingInvitation": String(pendingInvitation != nil),
            "hasPendingReviewRequest": String(pendingReviewRequest != nil),
            "proInstallationOverride": GuidanceDebugOverrides.proInstallationOverride.rawValue,
        ]
        if let lastInvitationDate = state.lastInvitationDate {
            metadata["invitationCooldownActive"] = String(
                debugWholeDaysSince(lastInvitationDate) < configuration.invitationCooldownDays
            )
        } else {
            metadata["invitationCooldownActive"] = "false"
        }
        if let lastReviewRequestDate = state.lastReviewRequestDate {
            metadata["reviewCooldownActive"] = String(
                debugWholeDaysSince(lastReviewRequestDate) < configuration.reviewCooldownDays
            )
        } else {
            metadata["reviewCooldownActive"] = "false"
        }
        emit("guidance.debug.state_summary", metadata: metadata)
    }

    private func debugWholeDaysSince(_ date: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let startNow = calendar.startOfDay(for: now())
        return calendar.dateComponents([.day], from: start, to: startNow).day ?? 0
    }
}
#endif
