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
    }

    public struct ReviewRequestPresentation: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let moment: GuidanceValueMoment
        public let scheduledAt: Date
    }

    struct ExportFeedback: Equatable {
        public let occurredAt: Date
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

    public func record(_ moment: GuidanceValueMoment) {
        _ = recordAndReturnDecision(moment)
    }

    @discardableResult
    func recordAndReturnDecision(_ moment: GuidanceValueMoment) -> GuidanceDecision {
        var state = stateStore.load()

        switch moment {
        case .diagnosticsCompleted, .exportSucceeded, .analysisLoaded:
            state.meaningfulCompletionCount += 1
        case .roamingCompleted:
            break
        }

        let canInvite = moment == .diagnosticsCompleted || moment == .exportSucceeded
        let canReview = moment == .diagnosticsCompleted || moment == .exportSucceeded || moment == .analysisLoaded

        let decision: GuidanceDecision
        if canInvite, pendingInvitation != nil {
            decision = .none(.invitationAlreadyPending)
        } else if canReview, pendingReviewRequest != nil {
            decision = .none(.reviewRequestPending)
        } else {
            decision = GuidancePolicy.decide(
                for: moment,
                state: state,
                config: configuration,
                now: now(),
                calendar: calendar,
                appVersion: appVersion(),
                isProAppInstalled: canInvite && configuration.invitationEnabled ? isProAppInstalled() : false
            )
        }

        switch decision {
        case .showProInvitation:
            let invitation = InvitationPresentation(id: UUID(), moment: moment, scheduledAt: now())
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
        stateStore.save(state)
    }

    // MARK: - Export feedback

    func handleExportSucceeded() {
        record(.exportSucceeded)
        exportFeedback = ExportFeedback(occurredAt: now())
    }

    func dismissExportFeedback() {
        exportFeedback = nil
        if let invitation = pendingInvitation, invitation.moment == .exportSucceeded {
            endInvitationPresentation(id: invitation.id)
        }
    }

    // MARK: - Invitation consumption (token-gated)

    func invitationPresented(id: UUID) {
        guard let invitation = pendingInvitation, invitation.id == id else { return }
        guard !confirmedPresentedInvitationIDs.contains(id) else { return }
        confirmedPresentedInvitationIDs.insert(id)
        var state = stateStore.load()
        state.invitationPresentationCount += 1
        state.lastInvitationDate = now()
        stateStore.save(state)
        emit("guidance.invitation.presented", moment: invitation.moment, tokenID: id)
    }

    func dismissInvitation(id: UUID) {
        guard let invitation = pendingInvitation, invitation.id == id else { return }
        pendingInvitation = nil
        var state = stateStore.load()
        state.invitationDismissalCount += 1
        stateStore.save(state)
        emit("guidance.invitation.dismissed", moment: invitation.moment, tokenID: id)
    }

    func disableInvitations(id: UUID) {
        guard let invitation = pendingInvitation, invitation.id == id else { return }
        pendingInvitation = nil
        var state = stateStore.load()
        state.invitationsDisabled = true
        stateStore.save(state)
        emit("guidance.invitation.disabled", moment: invitation.moment, tokenID: id)
    }

    func openInvitation(id: UUID) {
        guard let invitation = pendingInvitation, invitation.id == id else { return }
        pendingInvitation = nil
        emit("guidance.invitation.view_selected", moment: invitation.moment, tokenID: id)
    }

    /// Host-lifecycle end, called from the host view's `onDisappear` with the
    /// exact token the host rendered. An unpresented invitation is cancelled
    /// without any count or cooldown; a presented one without a user choice is
    /// consumed as Later.
    func endInvitationPresentation(id: UUID) {
        guard let invitation = pendingInvitation, invitation.id == id else { return }
        pendingInvitation = nil
        if confirmedPresentedInvitationIDs.contains(id) {
            var state = stateStore.load()
            state.invitationDismissalCount += 1
            stateStore.save(state)
            emit("guidance.invitation.dismissed", moment: invitation.moment, tokenID: id)
        } else {
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
    public func debugScheduleInvitation(for moment: GuidanceValueMoment) {
        guard moment == .diagnosticsCompleted || moment == .exportSucceeded else {
            emit("guidance.debug.refused", metadata: ["reason": "unsupported_moment"])
            return
        }
        guard pendingInvitation == nil else {
            emit("guidance.debug.refused", metadata: ["reason": "pending_invitation"])
            return
        }
        let invitation = InvitationPresentation(id: UUID(), moment: moment, scheduledAt: now())
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
    public func debugPublishExportFeedback() {
        exportFeedback = ExportFeedback(occurredAt: now())
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
