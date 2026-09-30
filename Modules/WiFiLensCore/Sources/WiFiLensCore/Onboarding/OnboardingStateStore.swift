import Foundation

/// Serialization boundary for `OnboardingState`. Mirrors the guidance store:
/// the coordinator serializes access on the main actor, so the protocol needs
/// no `Sendable` requirement.
@MainActor
public protocol OnboardingStateStoring {
    func load() -> OnboardingState

    /// Whether a value for the onboarding key exists. Distinguishes "never
    /// migrated / key absent" from "key present with `false`", which matters
    /// for the one-time existing-install migration.
    func hasStoredState() -> Bool

    func save(_ state: OnboardingState)
}

/// `UserDefaults`-backed onboarding store. Uses a versioned key so a future
/// intentional `v2` onboarding can ship without breaking `v1` semantics.
public struct UserDefaultsOnboardingStateStore: OnboardingStateStoring {
    private enum Key {
        static let welcomeCompleted = "onboarding.welcome.completed.v1"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> OnboardingState {
        OnboardingState(
            hasCompletedWelcome: defaults.bool(forKey: Key.welcomeCompleted)
        )
    }

    public func hasStoredState() -> Bool {
        defaults.object(forKey: Key.welcomeCompleted) != nil
    }

    public func save(_ state: OnboardingState) {
        defaults.set(state.hasCompletedWelcome, forKey: Key.welcomeCompleted)
    }
}

/// In-memory store for tests and previews.
@MainActor
final class InMemoryOnboardingStateStore: OnboardingStateStoring {
    private var state: OnboardingState
    private var stored: Bool

    init(initial: OnboardingState = OnboardingState(), hasStoredState: Bool = false) {
        self.state = initial
        self.stored = hasStoredState
    }

    func load() -> OnboardingState {
        state
    }

    func hasStoredState() -> Bool {
        stored
    }

    func save(_ state: OnboardingState) {
        self.state = state
        stored = true
    }
}
