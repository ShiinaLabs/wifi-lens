@testable import WiFiLensCore

import Foundation
import Testing
@testable import WiFi_Lens

struct GuidancePolicyTests {
    private let calendar = Self.makeCalendar()
    private let appVersion = "2.1.0"
    private var now: Date { date(2026, 8, 5, hour: 12, calendar: calendar) }

    // MARK: - Invitation flow

    @Test func diagnosticsCompletionInvitesWhenEligible() {
        let decision = decide(
            for: .diagnosticsCompleted,
            state: invitationState(),
            config: invitationConfig()
        )

        #expect(decision == .showProInvitation)
    }

    @Test func exportSuccessInvitesWhenEligible() {
        let decision = decide(
            for: .exportSucceeded,
            state: invitationState(),
            config: invitationConfig()
        )

        #expect(decision == .showProInvitation)
    }

    @Test func roamingNeverAppliesPolicy() {
        let decision = decide(
            for: .roamingCompleted,
            state: invitationState(completionCount: 100, presentationCount: 0),
            config: invitationConfig()
        )

        #expect(decision == .none(.roamingPolicyNotEnabled))
    }

    @Test func analysisNeverInvitesEvenWhenInvitationEnabled() {
        let decision = decide(
            for: .analysisLoaded,
            state: invitationState(),
            config: invitationConfig()
        )

        #expect(decision == .none(.editionReviewDisabled))
    }

    @Test func invitationDisabledByUserSuppresses() {
        let decision = decide(
            for: .diagnosticsCompleted,
            state: invitationState(invitationsDisabled: true),
            config: invitationConfig()
        )

        #expect(decision == .none(.invitationsDisabledByUser))
    }

    @Test func laterChoiceTakesPriorityOverPurchaseFollowUp() {
        let state = invitationState(
            lastInvitationDate: daysAgo(3),
            lastInvitationLaterDate: daysAgo(2),
            lastPurchaseExplorationDate: daysAgo(10)
        )
        #expect(decide(for: .appReturnedAfterUse, state: state, config: invitationConfig()) == .none(.invitationRecentlyDeferred))
    }

    @Test func purchaseExplorationEnablesOnlyTheThreeDayAcceleratedFollowUp() {
        let due = invitationState(lastInvitationDate: daysAgo(3), lastPurchaseExplorationDate: daysAgo(3))
        let tooEarly = invitationState(lastInvitationDate: daysAgo(2), lastPurchaseExplorationDate: daysAgo(2))
        let alreadyUsed = invitationState(
            lastInvitationDate: daysAgo(3),
            lastPurchaseExplorationDate: daysAgo(3),
            lastAcceleratedFollowUpExplorationDate: daysAgo(3)
        )
        #expect(decide(for: .appReturnedAfterUse, state: due, config: invitationConfig()) == .showProInvitation)
        #expect(decide(for: .appReturnedAfterUse, state: tooEarly, config: invitationConfig()) == .none(.invitationCooldown))
        #expect(decide(for: .appReturnedAfterUse, state: alreadyUsed, config: invitationConfig()) == .none(.invitationCooldown))
    }

    @Test func acceleratedFollowUpIsLimitedToOncePerFourteenDays() {
        let state = invitationState(
            lastInvitationDate: daysAgo(3),
            lastPurchaseExplorationDate: daysAgo(3),
            lastAcceleratedFollowUpDate: daysAgo(13),
            lastAcceleratedFollowUpExplorationDate: daysAgo(20)
        )
        #expect(decide(for: .appReturnedAfterUse, state: state, config: invitationConfig()) == .none(.invitationCooldown))
    }

    @Test func purchaseExplorationExpiresAfterFourteenDays() {
        let valid = invitationState(lastInvitationDate: daysAgo(3), lastPurchaseExplorationDate: daysAgo(13))
        let expired = invitationState(lastInvitationDate: daysAgo(14), lastPurchaseExplorationDate: daysAgo(14))
        #expect(GuidanceInterestPolicy.canScheduleAcceleratedFollowUp(state: valid, now: now, calendar: calendar))
        #expect(!GuidanceInterestPolicy.canScheduleAcceleratedFollowUp(state: expired, now: now, calendar: calendar))
    }

    @Test func noMoreThanTwoInvitationsInAnySevenLocalDays() {
        let capped = invitationState(presentationDates: [daysAgo(0), daysAgo(4)])
        let eligible = invitationState(presentationDates: [daysAgo(0)])
        #expect(decide(for: .diagnosticsCompleted, state: capped, config: invitationConfig()) == .none(.invitationWeeklyLimit))
        #expect(decide(for: .diagnosticsCompleted, state: eligible, config: invitationConfig()) == .showProInvitation)
    }

    @Test func interestRequiresTwoDistinctDatesWithinFourteenDays() {
        let today = GuidanceState.dayKey(for: now, calendar: calendar)
        let yesterday = GuidanceState.dayKey(for: daysAgo(1), calendar: calendar)
        let expired = GuidanceState.dayKey(for: daysAgo(14), calendar: calendar)
        let oneVisit = [ProInterestVisit(category: .spectrumRecording, day: today)]
        let repeatedVisit = [
            ProInterestVisit(category: .spectrumRecording, day: today),
            ProInterestVisit(category: .spectrumRecording, day: yesterday),
        ]
        let oldVisit = [
            ProInterestVisit(category: .spectrumRecording, day: today),
            ProInterestVisit(category: .spectrumRecording, day: expired),
        ]
        #expect(!GuidanceInterestPolicy.isInterested(in: .spectrumRecording, visits: oneVisit, now: now, calendar: calendar))
        #expect(GuidanceInterestPolicy.isInterested(in: .spectrumRecording, visits: repeatedVisit, now: now, calendar: calendar))
        #expect(!GuidanceInterestPolicy.isInterested(in: .spectrumRecording, visits: oldVisit, now: now, calendar: calendar))
    }

    @Test func contentUsesOnlyQualifiedInterestAfterRealUseMoments() {
        let today = GuidanceState.dayKey(for: now, calendar: calendar)
        let yesterday = GuidanceState.dayKey(for: daysAgo(1), calendar: calendar)
        let qualified = GuidanceState(proInterestVisits: [
            ProInterestVisit(category: .spectrumRecording, day: today),
            ProInterestVisit(category: .spectrumRecording, day: yesterday),
        ])
        let oneVisit = GuidanceState(proInterestVisits: [
            ProInterestVisit(category: .spectrumRecording, day: today),
        ])

        #expect(GuidanceContentSelector.messageKey(for: .appReturnedAfterUse, state: qualified, now: now, calendar: calendar) == "guidance.invitation.message.recording")
        #expect(GuidanceContentSelector.messageKey(for: .appReturnedAfterUse, state: oneVisit, now: now, calendar: calendar) == "guidance.invitation.message.general")
        #expect(GuidanceContentSelector.messageKey(for: .diagnosticsCompleted, state: qualified, now: now, calendar: calendar) == "guidance.invitation.message.diagnostics")
    }

    @Test func proAppInstalledSuppressesInvitation() {
        let decision = decide(
            for: .diagnosticsCompleted,
            state: invitationState(),
            config: invitationConfig(),
            isProAppInstalled: true
        )

        #expect(decision == .none(.proAppInstalled))
    }

    @Test func invitationNoLongerDependsOnCompletionCount() {
        let below = decide(
            for: .diagnosticsCompleted,
            state: invitationState(completionCount: 0),
            config: invitationConfig()
        )
        let at = decide(
            for: .diagnosticsCompleted,
            state: invitationState(completionCount: 1),
            config: invitationConfig()
        )

        #expect(below == .showProInvitation)
        #expect(at == .showProInvitation)
    }

    @Test func invitationActiveDaysThresholdBoundary() {
        let below = decide(
            for: .diagnosticsCompleted,
            state: invitationState(activeDays: ["2026-07-01"]),
            config: invitationConfig()
        )
        let at = decide(
            for: .diagnosticsCompleted,
            state: invitationState(activeDays: ["2026-07-01", "2026-07-02"]),
            config: invitationConfig()
        )

        #expect(below == .none(.activeDaysThresholdNotMet))
        #expect(at == .showProInvitation)
    }

    @Test func lifetimeInvitationLimitIsRemoved() {
        let atLimit = decide(
            for: .diagnosticsCompleted,
            state: invitationState(presentationCount: 3),
            config: invitationConfig()
        )
        let underLimit = decide(
            for: .diagnosticsCompleted,
            state: invitationState(presentationCount: 2),
            config: invitationConfig()
        )

        #expect(atLimit == .showProInvitation)
        #expect(underLimit == .showProInvitation)
    }

    @Test func sevenDayInvitationCooldownBoundary() {
        let inCooldown = decide(
            for: .diagnosticsCompleted,
            state: invitationState(lastInvitationDate: daysAgo(6)),
            config: invitationConfig()
        )
        let atBoundary = decide(
            for: .diagnosticsCompleted,
            state: invitationState(lastInvitationDate: daysAgo(7)),
            config: invitationConfig()
        )

        #expect(inCooldown == .none(.invitationCooldown))
        #expect(atBoundary == .showProInvitation)
    }

    @Test func diagnosticsWithBothFlowsDisabled() {
        let decision = decide(
            for: .diagnosticsCompleted,
            state: invitationState(),
            config: GuidanceConfiguration()
        )

        #expect(decision == .none(.editionInvitationDisabled))
    }

    // MARK: - Review flow

    @Test func analysisRequestsReviewWhenEligible() {
        let decision = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )

        #expect(decision == .requestReview)
    }

    @Test func diagnosticsUsesReviewFlowWhenInvitationDisabled() {
        let decision = decide(
            for: .diagnosticsCompleted,
            state: reviewState(firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )

        #expect(decision == .requestReview)
    }

    @Test func exportUsesReviewFlowWhenInvitationDisabled() {
        let decision = decide(
            for: .exportSucceeded,
            state: reviewState(firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )

        #expect(decision == .requestReview)
    }

    @Test func analysisWithReviewDisabled() {
        let decision = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: nil),
            config: GuidanceConfiguration()
        )

        #expect(decision == .none(.editionReviewDisabled))
    }

    @Test func reviewFirstLaunchAgeBoundary() {
        let noLaunch = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: nil),
            config: reviewConfig()
        )
        let tooYoung = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(6)),
            config: reviewConfig()
        )
        let atBoundary = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )

        #expect(noLaunch == .none(.firstLaunchAgeNotMet))
        #expect(tooYoung == .none(.firstLaunchAgeNotMet))
        #expect(atBoundary == .requestReview)
    }

    @Test func reviewActiveDaysThresholdBoundary() {
        let below = decide(
            for: .analysisLoaded,
            state: reviewState(activeDays: ["2026-07-01", "2026-07-02"], firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )
        let at = decide(
            for: .analysisLoaded,
            state: reviewState(
                activeDays: ["2026-07-01", "2026-07-02", "2026-07-03"],
                firstLaunchDate: daysAgo(7)
            ),
            config: reviewConfig()
        )

        #expect(below == .none(.activeDaysThresholdNotMet))
        #expect(at == .requestReview)
    }

    @Test func reviewCompletionThresholdBoundary() {
        let below = decide(
            for: .analysisLoaded,
            state: reviewState(completionCount: 4, firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )
        let at = decide(
            for: .analysisLoaded,
            state: reviewState(completionCount: 5, firstLaunchDate: daysAgo(7)),
            config: reviewConfig()
        )

        #expect(below == .none(.completionThresholdNotMet))
        #expect(at == .requestReview)
    }

    @Test func reviewVersionGating() {
        let sameVersion = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(7), lastReviewRequestVersion: appVersion),
            config: reviewConfig()
        )
        let nilVersion = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(7), lastReviewRequestVersion: nil),
            config: reviewConfig()
        )
        let newVersion = decide(
            for: .analysisLoaded,
            state: reviewState(firstLaunchDate: daysAgo(7), lastReviewRequestVersion: "2.0.9"),
            config: reviewConfig()
        )

        #expect(sameVersion == .none(.reviewAlreadyRequestedForVersion))
        #expect(nilVersion == .requestReview)
        #expect(newVersion == .requestReview)
    }

    @Test func reviewCooldownBoundary() {
        let inCooldown = decide(
            for: .analysisLoaded,
            state: reviewState(
                firstLaunchDate: daysAgo(7),
                lastReviewRequestDate: daysAgo(119),
                lastReviewRequestVersion: "2.0.9"
            ),
            config: reviewConfig()
        )
        let atBoundary = decide(
            for: .analysisLoaded,
            state: reviewState(
                firstLaunchDate: daysAgo(7),
                lastReviewRequestDate: daysAgo(120),
                lastReviewRequestVersion: "2.0.9"
            ),
            config: reviewConfig()
        )

        #expect(inCooldown == .none(.reviewCooldown))
        #expect(atBoundary == .requestReview)
    }

    // MARK: - Pending-gate reasons are coordinator-only

    @Test func policyNeverReturnsPendingGateReasons() {
        let scenarios: [GuidanceDecision] = [
            decide(for: .diagnosticsCompleted, state: invitationState(), config: invitationConfig()),
            decide(for: .exportSucceeded, state: reviewState(firstLaunchDate: daysAgo(7)), config: reviewConfig()),
            decide(for: .analysisLoaded, state: reviewState(firstLaunchDate: daysAgo(7)), config: reviewConfig()),
            decide(for: .roamingCompleted, state: invitationState(), config: invitationConfig()),
            decide(
                for: .diagnosticsCompleted,
                state: invitationState(invitationsDisabled: true),
                config: invitationConfig()
            ),
            decide(
                for: .analysisLoaded,
                state: reviewState(firstLaunchDate: daysAgo(7), lastReviewRequestVersion: appVersion),
                config: reviewConfig()
            ),
            decide(for: .diagnosticsCompleted, state: invitationState(), config: GuidanceConfiguration())
        ]

        for decision in scenarios {
            if case let .none(reason) = decision {
                #expect(reason != .invitationAlreadyPending)
                #expect(reason != .reviewRequestPending)
            }
        }
    }

    // MARK: - Helpers

    private func decide(
        for moment: GuidanceValueMoment,
        state: GuidanceState,
        config: GuidanceConfiguration,
        isProAppInstalled: Bool = false
    ) -> GuidanceDecision {
        GuidancePolicy.decide(
            for: moment,
            state: state,
            config: config,
            now: now,
            calendar: calendar,
            appVersion: appVersion,
            isProAppInstalled: isProAppInstalled
        )
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

    private func invitationState(
        completionCount: Int = 3,
        activeDays: [String] = ["2026-07-01", "2026-07-02"],
        invitationsDisabled: Bool = false,
        presentationCount: Int = 0,
        lastInvitationDate: Date? = nil,
        lastInvitationLaterDate: Date? = nil,
        lastPurchaseExplorationDate: Date? = nil,
        lastAcceleratedFollowUpDate: Date? = nil,
        lastAcceleratedFollowUpExplorationDate: Date? = nil,
        presentationDates: [Date] = []
    ) -> GuidanceState {
        GuidanceState(
            activeDays: activeDays,
            meaningfulCompletionCount: completionCount,
            lastInvitationDate: lastInvitationDate,
            invitationPresentationCount: presentationCount,
            invitationDismissalCount: 0,
            invitationsDisabled: invitationsDisabled,
            invitationPresentationDates: presentationDates,
            lastInvitationLaterDate: lastInvitationLaterDate,
            lastPurchaseExplorationDate: lastPurchaseExplorationDate,
            lastAcceleratedFollowUpDate: lastAcceleratedFollowUpDate,
            lastAcceleratedFollowUpExplorationDate: lastAcceleratedFollowUpExplorationDate
        )
    }

    private func reviewState(
        completionCount: Int = 5,
        activeDays: [String] = ["2026-07-01", "2026-07-02", "2026-07-03"],
        firstLaunchDate: Date? = nil,
        lastReviewRequestDate: Date? = nil,
        lastReviewRequestVersion: String? = nil
    ) -> GuidanceState {
        GuidanceState(
            firstLaunchDate: firstLaunchDate,
            activeDays: activeDays,
            meaningfulCompletionCount: completionCount,
            lastReviewRequestDate: lastReviewRequestDate,
            lastReviewRequestVersion: lastReviewRequestVersion
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

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }
}
