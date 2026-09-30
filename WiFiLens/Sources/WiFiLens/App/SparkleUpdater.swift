#if OSS
import Sparkle
#endif
import WiFiLensCore

#if OSS

private let autoCheckKey = "SUEnableAutomaticChecks"

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        AppLogger.sparkle.error("aborted: code=\(nsError.code) domain=\(nsError.domain) \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        let nsError = error as NSError
        AppLogger.sparkle.error("download failed: code=\(nsError.code) domain=\(nsError.domain) \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        AppLogger.sparkle.info("found update: \(item.displayVersionString) (\(item.versionString))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        AppLogger.sparkle.info("no update found: code=\(nsError.code) domain=\(nsError.domain) \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            let nsError = error as NSError
            AppLogger.sparkle.error("update cycle finished with error: code=\(nsError.code) domain=\(nsError.domain) \(error.localizedDescription)")
        } else {
            AppLogger.sparkle.info("update cycle finished")
        }
    }
}

@MainActor
final class SparkleUpdater: ObservableObject, WiFiLensUpdateChecking {
    let controller: SPUStandardUpdaterController
    private let updater: SPUUpdater
    private let updaterDelegate = UpdaterDelegate()

    init() {
        if UserDefaults.standard.object(forKey: autoCheckKey) == nil {
            UserDefaults.standard.set(false, forKey: autoCheckKey)
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        updater = controller.updater
        let autoCheck = UserDefaults.standard.bool(forKey: autoCheckKey)
        updater.automaticallyChecksForUpdates = autoCheck
        if autoCheck {
            updater.checkForUpdatesInBackground()
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: autoCheckKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: autoCheckKey)
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        AppLogger.sparkle.info("manual check triggered")
        controller.checkForUpdates(nil)
    }
}
#else
@MainActor
final class SparkleUpdater: WiFiLensUpdateChecking {
    init() {}
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { }
    }
    func checkForUpdates() {}
}
#endif
