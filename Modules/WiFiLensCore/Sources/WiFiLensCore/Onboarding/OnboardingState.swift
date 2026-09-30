import Foundation

/// Persisted first-run onboarding state. Independent from `GuidanceState`:
/// onboarding never records value moments, invitation/review counts, or any
/// lifecycle-guidance field.
struct OnboardingState: Equatable, Sendable {
    var hasCompletedWelcome: Bool

    public init(hasCompletedWelcome: Bool = false) {
        self.hasCompletedWelcome = hasCompletedWelcome
    }
}
