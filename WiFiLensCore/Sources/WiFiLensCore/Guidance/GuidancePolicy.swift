import Foundation

/// Pure eligibility and cooldown decisions. No I/O, no clock (all dates are
/// injected), no edition knowledge, and no pending-state awareness — the
/// coordinator applies its own pending gates before consulting the policy.
enum GuidancePolicy {
    static func decide(
        for moment: GuidanceValueMoment,
        state: GuidanceState,
        config: GuidanceConfiguration,
        now: Date,
        calendar: Calendar,
        appVersion: String,
        isProAppInstalled: Bool
    ) -> GuidanceDecision {
        switch moment {
        case .roamingCompleted:
            // Roaming participates in events and logs in v1, never in policy.
            return .none(.roamingPolicyNotEnabled)
        case .analysisLoaded:
            // Analysis is Pro-exclusive: the invitation path never applies.
            guard config.reviewEnabled else {
                return .none(.editionReviewDisabled)
            }
            return reviewDecision(
                state: state,
                config: config,
                now: now,
                calendar: calendar,
                appVersion: appVersion
            )
        case .diagnosticsCompleted, .exportSucceeded, .appReturnedAfterUse:
            guard config.invitationEnabled else {
                if config.reviewEnabled {
                    return reviewDecision(
                        state: state,
                        config: config,
                        now: now,
                        calendar: calendar,
                        appVersion: appVersion
                    )
                }
                return .none(.editionInvitationDisabled)
            }
            return invitationDecision(
                state: state,
                config: config,
                now: now,
                calendar: calendar,
                isProAppInstalled: isProAppInstalled
            )
        }
    }

    private static func invitationDecision(
        state: GuidanceState,
        config: GuidanceConfiguration,
        now: Date,
        calendar: Calendar,
        isProAppInstalled: Bool
    ) -> GuidanceDecision {
        guard !state.invitationsDisabled else {
            return .none(.invitationsDisabledByUser)
        }
        guard !isProAppInstalled else {
            return .none(.proAppInstalled)
        }
        guard state.meaningfulCompletionCount >= config.minimumInvitationCompletions else {
            return .none(.completionThresholdNotMet)
        }
        guard state.activeDays.count >= config.minimumInvitationActiveDays else {
            return .none(.activeDaysThresholdNotMet)
        }
        guard config.localMarketingPolicyEnabled else {
            if let lastInvitationDate = state.lastInvitationDate,
               daysSince(lastInvitationDate, now: now, calendar: calendar) < config.invitationCooldownDays {
                return .none(.invitationCooldown)
            }
            guard state.invitationPresentationCount < config.maxAutomaticInvitations else {
                return .none(.invitationPresentationLimit)
            }
            return .showProInvitation
        }
        if let laterDate = state.lastInvitationLaterDate,
           daysSince(laterDate, now: now, calendar: calendar) < config.invitationCooldownDays {
            return .none(.invitationRecentlyDeferred)
        }
        var recordedPresentationDates = state.invitationPresentationDates
        if let legacyPresentationDate = state.lastInvitationDate,
           !recordedPresentationDates.contains(legacyPresentationDate) {
            recordedPresentationDates.append(legacyPresentationDate)
        }
        let presentationsInLastWeek = recordedPresentationDates.filter {
            (0..<7).contains(daysSince($0, now: now, calendar: calendar))
        }.count
        guard presentationsInLastWeek < 2 else {
            return .none(.invitationWeeklyLimit)
        }
        let accelerated = GuidanceInterestPolicy.canScheduleAcceleratedFollowUp(
            state: state,
            now: now,
            calendar: calendar
        )
        if !accelerated,
           let lastInvitationDate = state.lastInvitationDate,
           daysSince(lastInvitationDate, now: now, calendar: calendar) < config.invitationCooldownDays {
            return .none(.invitationCooldown)
        }
        return .showProInvitation
    }

    private static func reviewDecision(
        state: GuidanceState,
        config: GuidanceConfiguration,
        now: Date,
        calendar: Calendar,
        appVersion: String
    ) -> GuidanceDecision {
        guard let firstLaunchDate = state.firstLaunchDate,
              daysSince(firstLaunchDate, now: now, calendar: calendar) >= config.minimumReviewAgeDays else {
            return .none(.firstLaunchAgeNotMet)
        }
        guard state.activeDays.count >= config.minimumReviewActiveDays else {
            return .none(.activeDaysThresholdNotMet)
        }
        guard state.meaningfulCompletionCount >= config.minimumReviewCompletions else {
            return .none(.completionThresholdNotMet)
        }
        guard state.lastReviewRequestVersion != appVersion else {
            return .none(.reviewAlreadyRequestedForVersion)
        }
        if let lastReviewRequestDate = state.lastReviewRequestDate,
           daysSince(lastReviewRequestDate, now: now, calendar: calendar) < config.reviewCooldownDays {
            return .none(.reviewCooldown)
        }
        return .requestReview
    }

    /// Whole local days between `date` and `now`, using the injected calendar.
    /// A cooldown boundary at exactly `cooldownDays` days is eligible because
    /// the callers compare with `>=` / `<`.
    static func localDaysBetween(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func daysSince(_ date: Date, now: Date, calendar: Calendar) -> Int {
        localDaysBetween(date, now: now, calendar: calendar)
    }
}

/// Pure local-interest rules. No user identity or network data enters this state.
enum GuidanceInterestPolicy {
    static func isInterested(
        in category: ProInterestCategory,
        visits: [ProInterestVisit],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(byAdding: .day, value: -13, to: today) else { return false }
        let firstKey = GuidanceState.dayKey(for: firstDay, calendar: calendar)
        let lastKey = GuidanceState.dayKey(for: today, calendar: calendar)
        let visitDays = Set(visits
            .filter { $0.category == category && $0.day >= firstKey && $0.day <= lastKey }
            .map(\.day))
        return visitDays.count >= 2
    }

    static func canScheduleAcceleratedFollowUp(
        state: GuidanceState,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let exploration = state.lastPurchaseExplorationDate,
              GuidancePolicy.localDaysBetween(exploration, now: now, calendar: calendar) >= 3,
              state.lastInvitationLaterDate.map({ $0 < exploration }) ?? true,
              state.lastAcceleratedFollowUpExplorationDate != exploration,
              state.lastAcceleratedFollowUpDate.map({
                  GuidancePolicy.localDaysBetween($0, now: now, calendar: calendar) >= 14
              }) ?? true else { return false }
        return true
    }
}

/// Pure copy selection, separate from eligibility and view presentation.
enum GuidanceContentSelector {
    static func messageKey(
        for moment: GuidanceValueMoment,
        state: GuidanceState,
        now: Date,
        calendar: Calendar
    ) -> String {
        switch moment {
        case .diagnosticsCompleted:
            return "guidance.invitation.message.diagnostics"
        case .exportSucceeded:
            return "guidance.invitation.message.export"
        case .analysisLoaded, .roamingCompleted, .appReturnedAfterUse:
            let currentDay = GuidanceState.dayKey(for: now, calendar: calendar)
            let interested = Set(ProInterestCategory.allCases.filter {
                GuidanceInterestPolicy.isInterested(in: $0, visits: state.proInterestVisits, now: now, calendar: calendar)
            })
            guard let category = state.proInterestVisits
                .filter({ $0.day <= currentDay && interested.contains($0.category) })
                .max(by: { $0.day < $1.day })?.category else {
                return "guidance.invitation.message.general"
            }
            switch category {
            case .longTermMonitoring: return "guidance.invitation.message.monitoring"
            case .spectrumRecording: return "guidance.invitation.message.recording"
            case .advancedDiagnostics: return "guidance.invitation.message.advanced_diagnostics"
            case .generalPro: return "guidance.invitation.message.general"
            }
        }
    }
}
