import Foundation

/// Persisted first-run onboarding state. Independent from `GuidanceState`:
/// onboarding never records value moments, invitation/review counts, or any
/// lifecycle-guidance field.
public struct OnboardingState: Equatable, Sendable {
    public var hasCompletedWelcome: Bool

    public init(hasCompletedWelcome: Bool = false) {
        self.hasCompletedWelcome = hasCompletedWelcome
    }
}
