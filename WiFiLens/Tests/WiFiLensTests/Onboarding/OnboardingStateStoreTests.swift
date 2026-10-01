import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
final class OnboardingStateStoreTests {
    @Test func cleanInstallDefaultsToIncompleteWithoutStoredKey() {
        let store = UserDefaultsOnboardingStateStore(defaults: suiteDefaults())
        defer { clearSuite() }

        #expect(store.load().hasCompletedWelcome == false)
        #expect(store.hasStoredState() == false)
    }

    @Test func absentKeyDistinctFromExplicitFalse() {
        let defaults = suiteDefaults()
        defer { clearSuite() }
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)

        #expect(store.hasStoredState() == false)

        store.save(OnboardingState())

        #expect(store.hasStoredState() == true)
        #expect(store.load().hasCompletedWelcome == false)
    }

    @Test func completedStateRestores() {
        let defaults = suiteDefaults()
        defer { clearSuite() }
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)

        store.save(OnboardingState(hasCompletedWelcome: true))

        let reloaded = UserDefaultsOnboardingStateStore(defaults: defaults)
        #expect(reloaded.load().hasCompletedWelcome == true)
        #expect(reloaded.hasStoredState() == true)
    }

    @Test func resetReturnsToIncomplete() {
        let defaults = suiteDefaults()
        defer { clearSuite() }
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        store.save(OnboardingState(hasCompletedWelcome: true))

        store.save(OnboardingState())

        #expect(store.load().hasCompletedWelcome == false)
        #expect(store.hasStoredState() == true)
    }

    @Test func corruptDataFallsBackSafely() {
        let defaults = suiteDefaults()
        defer { clearSuite() }
        defaults.set("not-a-bool", forKey: "onboarding.welcome.completed.v1")

        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        let loaded = store.load()

        #expect(loaded.hasCompletedWelcome == false)
        #expect(store.hasStoredState() == true)
    }

    @Test func versionedKeyDoesNotAffectOtherDefaults() {
        let defaults = suiteDefaults()
        defer { clearSuite() }
        defaults.set("kept", forKey: "unrelated.key")

        UserDefaultsOnboardingStateStore(defaults: defaults)
            .save(OnboardingState(hasCompletedWelcome: true))

        #expect(defaults.string(forKey: "unrelated.key") == "kept")
    }

    private func suiteDefaults() -> UserDefaults {
        UserDefaults(suiteName: "OnboardingStateStoreTests.\(UUID().uuidString)")!
    }

    private func clearSuite() {
        // Each test uses its own suite; nothing to clear across tests.
    }
}
