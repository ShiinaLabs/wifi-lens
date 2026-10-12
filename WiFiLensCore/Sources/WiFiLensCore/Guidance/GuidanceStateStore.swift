import Foundation

/// Serialization boundary for `GuidanceState`. The coordinator serializes all
/// access on the main actor, so no `Sendable` requirements are needed.
@MainActor
protocol GuidanceStateStoring {
    func load() -> GuidanceState
    func save(_ state: GuidanceState)
}

/// `UserDefaults`-backed store. Stays a struct — it writes through the
/// external `UserDefaults` instance.
public struct UserDefaultsGuidanceStateStore: GuidanceStateStoring {
    private enum Key {
        static let firstLaunchDate = "guidance.firstLaunchDate"
        static let activeDays = "guidance.activeDays"
        static let completionCount = "guidance.completionCount"
        static let lastInvitationDate = "guidance.lastInvitationDate"
        static let invitationPresentationCount = "guidance.invitationPresentationCount"
        static let invitationDismissalCount = "guidance.invitationDismissalCount"
        static let invitationsDisabled = "guidance.invitationsDisabled"
        static let invitationPresentationDates = "guidance.invitationPresentationDates"
        static let lastInvitationLaterDate = "guidance.lastInvitationLaterDate"
        static let lastPurchaseExplorationDate = "guidance.lastPurchaseExplorationDate"
        static let lastAcceleratedFollowUpDate = "guidance.lastAcceleratedFollowUpDate"
        static let lastAcceleratedFollowUpExplorationDate = "guidance.lastAcceleratedFollowUpExplorationDate"
        static let proInterestVisits = "guidance.proInterestVisits"
        static let lastReviewRequestDate = "guidance.lastReviewRequestDate"
        static let lastReviewRequestVersion = "guidance.lastReviewRequestVersion"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GuidanceState {
        GuidanceState(
            firstLaunchDate: defaults.object(forKey: Key.firstLaunchDate) as? Date,
            activeDays: defaults.stringArray(forKey: Key.activeDays) ?? [],
            meaningfulCompletionCount: defaults.integer(forKey: Key.completionCount),
            lastInvitationDate: defaults.object(forKey: Key.lastInvitationDate) as? Date,
            invitationPresentationCount: defaults.integer(forKey: Key.invitationPresentationCount),
            invitationDismissalCount: defaults.integer(forKey: Key.invitationDismissalCount),
            invitationsDisabled: defaults.bool(forKey: Key.invitationsDisabled),
            lastReviewRequestDate: defaults.object(forKey: Key.lastReviewRequestDate) as? Date,
            lastReviewRequestVersion: defaults.string(forKey: Key.lastReviewRequestVersion),
            invitationPresentationDates: defaults.array(forKey: Key.invitationPresentationDates) as? [Date] ?? [],
            lastInvitationLaterDate: defaults.object(forKey: Key.lastInvitationLaterDate) as? Date,
            lastPurchaseExplorationDate: defaults.object(forKey: Key.lastPurchaseExplorationDate) as? Date,
            lastAcceleratedFollowUpDate: defaults.object(forKey: Key.lastAcceleratedFollowUpDate) as? Date,
            lastAcceleratedFollowUpExplorationDate: defaults.object(forKey: Key.lastAcceleratedFollowUpExplorationDate) as? Date,
            proInterestVisits: (defaults.data(forKey: Key.proInterestVisits).flatMap { try? JSONDecoder().decode([ProInterestVisit].self, from: $0) }) ?? []
        )
    }

    func save(_ state: GuidanceState) {
        defaults.set(state.firstLaunchDate, forKey: Key.firstLaunchDate)
        defaults.set(state.activeDays, forKey: Key.activeDays)
        defaults.set(state.meaningfulCompletionCount, forKey: Key.completionCount)
        defaults.set(state.lastInvitationDate, forKey: Key.lastInvitationDate)
        defaults.set(state.invitationPresentationCount, forKey: Key.invitationPresentationCount)
        defaults.set(state.invitationDismissalCount, forKey: Key.invitationDismissalCount)
        defaults.set(state.invitationsDisabled, forKey: Key.invitationsDisabled)
        defaults.set(state.invitationPresentationDates, forKey: Key.invitationPresentationDates)
        defaults.set(state.lastInvitationLaterDate, forKey: Key.lastInvitationLaterDate)
        defaults.set(state.lastPurchaseExplorationDate, forKey: Key.lastPurchaseExplorationDate)
        defaults.set(state.lastAcceleratedFollowUpDate, forKey: Key.lastAcceleratedFollowUpDate)
        defaults.set(state.lastAcceleratedFollowUpExplorationDate, forKey: Key.lastAcceleratedFollowUpExplorationDate)
        if let visits = try? JSONEncoder().encode(state.proInterestVisits) {
            defaults.set(visits, forKey: Key.proInterestVisits)
        }
        defaults.set(state.lastReviewRequestDate, forKey: Key.lastReviewRequestDate)
        defaults.set(state.lastReviewRequestVersion, forKey: Key.lastReviewRequestVersion)
    }
}

/// In-memory store for tests and previews. A `final class` because its
/// non-mutating `save` must replace stored state; a struct cannot do that.
@MainActor
final class InMemoryGuidanceStateStore: GuidanceStateStoring {
    private var state: GuidanceState

    init(initial: GuidanceState = GuidanceState()) {
        self.state = initial
    }

    func load() -> GuidanceState {
        state
    }

    func save(_ state: GuidanceState) {
        self.state = state
    }
}
