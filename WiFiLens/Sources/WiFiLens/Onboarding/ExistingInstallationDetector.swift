import Foundation
import WiFiLensCore

/// Uses Sparkle's automatic-check key, which every build since May 2026
/// writes on first launch. The migration must run before `SparkleUpdater`
/// initializes, otherwise a brand-new install would already carry the key and
/// the welcome would never show for clean installs.
struct SparkleAutomaticCheckExistingInstallationDetector: ExistingInstallationDetecting {
    static let defaultsKey = "SUEnableAutomaticChecks"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasExistingInstallationEvidence() -> Bool {
        defaults.object(forKey: Self.defaultsKey) != nil
    }
}
