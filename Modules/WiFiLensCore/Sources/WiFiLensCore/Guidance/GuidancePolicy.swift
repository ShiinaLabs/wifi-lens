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
        case .diagnosticsCompleted, .exportSucceeded:
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
        if let lastInvitationDate = state.lastInvitationDate,
           daysSince(lastInvitationDate, now: now, calendar: calendar) < config.invitationCooldownDays {
            return .none(.invitationCooldown)
        }
        guard state.invitationPresentationCount < config.maxAutomaticInvitations else {
            return .none(.invitationPresentationLimit)
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
    private static func daysSince(_ date: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
