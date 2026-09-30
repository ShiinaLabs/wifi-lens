import Foundation

/// Persisted What's New version state.
struct WhatsNewState: Equatable, Sendable {
    var lastSeenVersion: String?

    init(lastSeenVersion: String? = nil) {
        self.lastSeenVersion = lastSeenVersion
    }
}

/// Serialization boundary for `WhatsNewState`.
@MainActor
protocol WhatsNewStateStoring {
    func load() -> WhatsNewState
    func save(_ state: WhatsNewState)
}

/// `UserDefaults`-backed What's New store.
struct UserDefaultsWhatsNewStateStore: WhatsNewStateStoring {
    private enum Key {
        static let lastSeenVersion = "whatsnew.lastSeenVersion.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WhatsNewState {
        WhatsNewState(
            lastSeenVersion: defaults.string(forKey: Key.lastSeenVersion)
        )
    }

    func save(_ state: WhatsNewState) {
        if let version = state.lastSeenVersion {
            defaults.set(version, forKey: Key.lastSeenVersion)
        } else {
            defaults.removeObject(forKey: Key.lastSeenVersion)
        }
    }
}

/// In-memory store for tests and previews.
@MainActor
final class InMemoryWhatsNewStateStore: WhatsNewStateStoring {
    private var state: WhatsNewState

    init(initial: WhatsNewState = WhatsNewState()) {
        self.state = initial
    }

    func load() -> WhatsNewState {
        state
    }

    func save(_ state: WhatsNewState) {
        self.state = state
    }
}
