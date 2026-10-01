final class MACVendorDatabaseReminderPolicy {
    private(set) var hasPresentedThisSession = false

    func shouldPresent(
        isSpectrum: Bool,
        isDatabaseEmpty: Bool,
        remindersEnabled: Bool
    ) -> Bool {
        guard !hasPresentedThisSession,
              isSpectrum,
              isDatabaseEmpty,
              remindersEnabled
        else { return false }

        hasPresentedThisSession = true
        return true
    }
}

extension MACVendorDatabaseAvailability {
    var shouldRemindWhenEmpty: Bool {
        switch self {
        case .notInstalled, .unavailable:
            true
        case .loading, .installed:
            false
        }
    }
}
