import Foundation

/// Edition-provided tuning for the guidance policy. Pure data — the policy
/// never reads edition or presentation concerns from here beyond the enabled
/// flags and thresholds.
public struct GuidanceConfiguration: Equatable, Sendable {
    public var invitationEnabled = false
    public var reviewEnabled = false
    public var minimumInvitationCompletions = 3
    public var minimumInvitationActiveDays = 2
    public var invitationCooldownDays = 30
    public var maxAutomaticInvitations = 3
    public var minimumReviewCompletions = 5
    public var minimumReviewActiveDays = 3
    public var minimumReviewAgeDays = 7
    public var reviewCooldownDays = 120

    public init() {}
}

/// The value moments the guidance system observes.
public enum GuidanceValueMoment: String, Equatable, Sendable {
    case diagnosticsCompleted
    case exportSucceeded
    case analysisLoaded
    case roamingCompleted
}

/// Why no guidance decision was made. There is deliberately no `.none` case:
/// `GuidanceDecision.none(reason)` already expresses "no action", so a
/// meaningless `.none(.none)` must not be expressible.
public enum GuidanceSuppressionReason: String, Equatable, Sendable {
    case editionInvitationDisabled
    case editionReviewDisabled
    case invitationsDisabledByUser
    case proAppInstalled
    case completionThresholdNotMet
    case activeDaysThresholdNotMet
    case invitationCooldown
    case invitationPresentationLimit
    case firstLaunchAgeNotMet
    case reviewCooldown
    case reviewAlreadyRequestedForVersion
    case roamingPolicyNotEnabled
    // Coordinator-level gates (checked before the pure policy; the policy
    // itself never reads pending state):
    case invitationAlreadyPending
    case reviewRequestPending
}

public enum GuidanceDecision: Equatable, Sendable {
    case none(GuidanceSuppressionReason)
    case showProInvitation
    case requestReview
}
