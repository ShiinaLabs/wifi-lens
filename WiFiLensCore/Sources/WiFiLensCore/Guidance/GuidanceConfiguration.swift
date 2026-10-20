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
    public var localMarketingPolicyEnabled = false
    /// Title-badge callout. Off unless an edition opts in; OSS turns it on.
    public var badgeBarEnabled = false
    /// Chance that a given launch shows the badge bar, once the cooldown allows it.
    public var badgeBarProbability = 0.25
    /// Minimum whole local days between badge-bar prompts.
    public var badgeBarCooldownDays = 7
    var minimumReviewCompletions = 5
    var minimumReviewActiveDays = 3
    var minimumReviewAgeDays = 7
    var reviewCooldownDays = 120

    public init() {}
}

/// The value moments the guidance system observes.
public enum GuidanceValueMoment: String, Equatable, Sendable {
    case diagnosticsCompleted
    case exportSucceeded
    case appReturnedAfterUse
    case analysisLoaded
    case roamingCompleted
}

/// Why no guidance decision was made. There is deliberately no `.none` case:
/// `GuidanceDecision.none(reason)` already expresses "no action", so a
/// meaningless `.none(.none)` must not be expressible.
enum GuidanceSuppressionReason: String, Equatable, Sendable {
    case editionInvitationDisabled
    case editionReviewDisabled
    case invitationsDisabledByUser
    case proAppInstalled
    case completionThresholdNotMet
    case activeDaysThresholdNotMet
    case invitationCooldown
    case invitationPresentationLimit
    case invitationWeeklyLimit
    case invitationAlreadyShownThisSession
    case invitationRecentlyDeferred
    case invitationHostInactive
    case acceleratedFollowUpUnavailable
    case badgeBarDisabled
    case badgeBarCooldown
    case badgeBarProbability
    case firstLaunchAgeNotMet
    case reviewCooldown
    case reviewAlreadyRequestedForVersion
    case roamingPolicyNotEnabled
    // Coordinator-level gates (checked before the pure policy; the policy
    // itself never reads pending state):
    case invitationAlreadyPending
    case reviewRequestPending
}

enum GuidanceDecision: Equatable, Sendable {
    case none(GuidanceSuppressionReason)
    case showProInvitation
    case requestReview
}

enum BadgeBarDecision: Equatable, Sendable {
    case none(GuidanceSuppressionReason)
    case show
}

/// What the badge-bar callout should offer when it is shown. Kept separate from
/// the invitation card: this surface is anchored to the title badge rather than
/// to a value moment, and its actions are independent of invitation pacing.
public struct BadgeBarPresentation: Equatable, Sendable {
    /// False once the repository page has been opened, so the row stops nagging.
    public let offersRepositoryStar: Bool

    public init(offersRepositoryStar: Bool) {
        self.offersRepositoryStar = offersRepositoryStar
    }
}
