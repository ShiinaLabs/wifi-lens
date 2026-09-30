import Foundation
import Observation
import WiFiLensCore

/// Coordinates AP Radar: target selection, scan observation consumption,
/// RSSI processing, pulse scheduling, audio playback, and lifecycle cleanup.
///
/// The view model is the single owner of tracking state. It registers as a
/// scan consumer only while the page is active and removes itself when the
/// page leaves, so it never creates a second scanning loop.
@MainActor
@Observable
final class APRadarViewModel: WiFiObservationConsuming {
    static let soundEnabledKey = "apRadarSoundEnabled"
    static let soundPresetKey = "apRadarSoundPreset"
    static let geigerUnlockedKey = "apRadarGeigerUnlocked"
    /// Loss duration after which recovery resets the smoother so old samples
    /// cannot pollute the new measurements.
    static let longLossResetThreshold: TimeInterval = 15

    // MARK: - Public state

    var state: APRadarState = .idle
    var soundEnabled: Bool
    /// Selected pulse tone preset, persisted in UserDefaults.
    var soundPreset: APRadarSoundPreset
    /// Whether the hidden Geiger-counter preset has been unlocked.
    var geigerUnlocked: Bool
    var latestNetworks: [WiFiNetworkObservation] = []
    var scanFailed = false
    /// Incremented on every audible pulse; the view uses it to drive the
    /// synchronized radar ring visual.
    var pulseTick = 0
    /// One-shot, non-blocking message when audio initialization fails.
    var audioErrorMessage: String?

    private(set) var audioAvailable = false

    // MARK: - Dependencies

    private let observationRuntime: WiFiObservationRuntime
    private let audioPlayer: any APRadarAudioPlaying
    private let scheduler: any APRadarPulseScheduling
    private let userDefaults: UserDefaults

    // MARK: - Private state

    private var isActive = false
    /// True while the app is backgrounded/asleep or Wi-Fi is off; the view's
    /// visual loop idles on this flag so it stops waking at full cadence.
    private(set) var isSuspended = false
    private var hasRegisteredConsumer = false
    private var target: TrackedAccessPoint?
    private var lastSeenAt: Date?
    /// When the current signal-lost state began; used to reset the smoother
    /// when a target reappears after a long absence.
    private var lostAt: Date?
    private var lossTimeout: Duration = .seconds(8)
    private var signalProcessor = APRadarSignalProcessor()
    private var audioFailureReported = false

    // MARK: - Init

    init(
        observationRuntime: WiFiObservationRuntime,
        audioPlayer: any APRadarAudioPlaying = APRadarAudioPlayer(),
        scheduler: any APRadarPulseScheduling = APRadarPulseScheduler(),
        userDefaults: UserDefaults = .standard
    ) {
        self.observationRuntime = observationRuntime
        self.audioPlayer = audioPlayer
        self.scheduler = scheduler
        self.userDefaults = userDefaults
        if let stored = userDefaults.object(forKey: Self.soundEnabledKey) as? Bool {
            soundEnabled = stored
        } else {
            soundEnabled = true
        }
        soundPreset = APRadarSoundPreset.fromStoredValue(
            userDefaults.string(forKey: Self.soundPresetKey)
        )
        geigerUnlocked = userDefaults.bool(forKey: Self.geigerUnlockedKey)
    }

    // MARK: - Lifecycle (called by the view)

    /// Called when the AP Radar page becomes active or inactive.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            beginSession()
        } else {
            endSession()
        }
    }

    /// App lost focus / entered sleep / Wi-Fi turned off: stop sound and
    /// scheduling, keep the optional target, wait for a fresh sample.
    func suspend() {
        guard isActive else { return }
        isSuspended = true
        scheduler.cancel()
        audioPlayer.stop()
    }

    /// App moved to the background or the system is about to sleep: stop
    /// sound and scheduling, keep the optional target, wait for a fresh
    /// sample after the app returns.
    func handleAppBackground() {
        suspend()
    }

    /// App became active again after a background suspension. Clears the
    /// suspension so the next fresh scan sample rebuilds smoothing and resumes
    /// sound. Sound never starts here: the spec requires a new sample after
    /// sleep/inactivity, and observations delivered while still suspended stay
    /// ignored (see `consume`).
    func handleAppActive() {
        guard isActive, isSuspended else { return }
        isSuspended = false
        signalProcessor.reset()
    }

    func handleWiFiPowerStateChange(_ powerState: WiFiPowerState) {
        switch powerState {
        case .poweredOn:
            // Next scan sample re-establishes smoothing state.
            isSuspended = false
            signalProcessor.reset()
        case .poweredOff, .interfaceUnavailable:
            suspend()
        }
    }

    private func beginSession() {
        guard !hasRegisteredConsumer else { return }
        hasRegisteredConsumer = true
        observationRuntime.addConsumer(self)
        refreshPreferences()
        resetSession()
        AppLogger.apRadar.info("AP Radar session started")
    }

    private func endSession() {
        stopTrackingInternal()
        if hasRegisteredConsumer {
            observationRuntime.removeConsumer(self)
            hasRegisteredConsumer = false
        }
        AppLogger.apRadar.info("AP Radar session stopped")
    }

    private func resetSession() {
        target = nil
        lastSeenAt = nil
        lostAt = nil
        signalProcessor.reset()
        state = .idle
        isSuspended = false
        latestNetworks = []
        scanFailed = false
        audioErrorMessage = nil
        audioFailureReported = false
        audioAvailable = false
        pulseTick = 0
    }

    // MARK: - Target selection

    func selectTarget(_ option: APRadarAPOption) {
        guard isActive else { return }
        stopPulseAndAudio()
        signalProcessor.reset()
        isSuspended = false
        lostAt = nil
        audioErrorMessage = nil
        audioFailureReported = false
        audioAvailable = false

        let bssid = TrackedAccessPoint.normalizedBSSID(option.bssid)
        let newTarget = TrackedAccessPoint(
            bssid: bssid,
            currentSSID: option.ssid,
            channel: option.channel,
            band: option.band
        )
        target = newTarget
        lastSeenAt = nil
        state = .tracking(APRadarSnapshot(target: newTarget))
        AppLogger.apRadar.info("AP Radar target selected")
        // Pulse sound starts after the first valid RSSI sample arrives.
    }

    func stopTracking() {
        guard target != nil || state.isTracking || state.isSignalLost else { return }
        stopTrackingInternal()
        AppLogger.apRadar.info("AP Radar tracking stopped")
    }

    private func stopTrackingInternal() {
        stopPulseAndAudio()
        target = nil
        lastSeenAt = nil
        lostAt = nil
        signalProcessor.reset()
        state = .idle
        isSuspended = false
    }

    // MARK: - Sound

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        userDefaults.set(enabled, forKey: Self.soundEnabledKey)
        if enabled {
            resumeSoundIfNeeded()
        } else {
            stopPulseAndAudio()
        }
    }

    /// Changes the pulse tone and persists the choice. If audio is already
    /// loaded, the next pulse uses the new tone immediately.
    func setSoundPreset(_ preset: APRadarSoundPreset) {
        guard preset != soundPreset else { return }
        soundPreset = preset
        userDefaults.set(preset.rawValue, forKey: Self.soundPresetKey)
        if audioAvailable {
            prepareAudio()
        }
        // The cadence mode changed (Geiger is stochastic, everything else is
        // deterministic): restart an active loop so the new behavior applies
        // immediately instead of on the next pulse.
        if canPulse {
            scheduler.cancel()
            startPulseSchedulerIfNeeded()
        }
        AppLogger.apRadar.info("AP Radar sound preset changed")
    }

    /// Unlocks the hidden Geiger-counter preset. Returns true when this is the
    /// first unlock (used by the view to show the reveal toast once).
    @discardableResult
    func unlockGeigerPreset() -> Bool {
        let firstTime = !geigerUnlocked
        geigerUnlocked = true
        userDefaults.set(true, forKey: Self.geigerUnlockedKey)
        if firstTime {
            AppLogger.apRadar.info("AP Radar Geiger preset unlocked")
        }
        return firstTime
    }

    /// Re-reads persisted sound preferences. Called when a session begins so
    /// choices made in Settings apply on the next page visit.
    private func refreshPreferences() {
        if let stored = userDefaults.object(forKey: Self.soundEnabledKey) as? Bool {
            soundEnabled = stored
        }
        soundPreset = APRadarSoundPreset.fromStoredValue(
            userDefaults.string(forKey: Self.soundPresetKey)
        )
        geigerUnlocked = userDefaults.bool(forKey: Self.geigerUnlockedKey)
    }

    private func resumeSoundIfNeeded() {
        guard isActive, !isSuspended, state.isTracking,
              signalProcessor.smoothedRSSI != nil else { return }
        if !audioAvailable {
            prepareAudio()
            guard audioAvailable else { return }
        }
        startPulseSchedulerIfNeeded()
    }

    private func prepareAudio() {
        do {
            try audioPlayer.prepare(preset: soundPreset)
            audioAvailable = true
            // Clear any error state from a previous transient failure so the
            // banner does not linger for the rest of the session.
            audioErrorMessage = nil
            audioFailureReported = false
        } catch {
            audioAvailable = false
            reportAudioFailure(underlying: error)
        }
    }

    private func reportAudioFailure(underlying: Error? = nil) {
        scheduler.cancel()
        if !audioFailureReported {
            audioFailureReported = true
            audioErrorMessage = String(
                localized: "apRadar.audio.failed",
                comment: "Non-blocking message shown when AP Radar audio cannot be initialized"
            )
            if let underlying {
                AppLogger.apRadar.error("AP Radar audio initialization failed: \(String(describing: underlying))")
            } else {
                AppLogger.apRadar.error("AP Radar audio playback failed")
            }
        }
    }

    private var canPulse: Bool {
        guard isActive, !isSuspended, soundEnabled, audioAvailable,
              state.isTracking, signalProcessor.smoothedRSSI != nil else {
            return false
        }
        return true
    }

    private func startPulseSchedulerIfNeeded() {
        guard !scheduler.isActive, canPulse else { return }
        scheduler.start(
            shouldContinue: { [weak self] in self?.canPulse ?? false },
            intervalProvider: { [weak self] in
                guard let self, let smoothed = self.signalProcessor.smoothedRSSI else {
                    return APRadarPulseInterval.pulseInterval(forRSSI: -90)
                }
                return APRadarPulseInterval.pulseInterval(forRSSI: smoothed)
            },
            playPulse: { [weak self] in self?.playPulse() },
            stochastic: soundPreset == .geiger
        )
    }

    private func playPulse() {
        guard canPulse else { return }
        if audioPlayer.playPulse() {
            pulseTick += 1
        } else {
            reportAudioFailure()
        }
    }

    private func stopPulseAndAudio() {
        scheduler.cancel()
        audioPlayer.stop()
    }

    // MARK: - Observation consumer

    func consume(_ observation: WiFiObservation) async throws {
        guard isActive else { return }
        updateNetworks(from: observation)
        updateScanFailure(from: observation)
        guard let target else { return }

        if isSuspended {
            // While the app is backgrounded / Wi-Fi is off, samples must not
            // re-arm the smoother or restart sound. `handleAppActive` (or a
            // powered-on transition) clears the suspension; the first sample
            // after that rebuilds smoothing from scratch.
            return
        }

        let timestamp = observation.timestamp
        let networks = observation.environmentSnapshot?.networks ?? []
        let matched = networks.first {
            TrackedAccessPoint.normalizedBSSID($0.bssid) == target.bssid
        }

        let wasLost = state.isSignalLost
        if wasLost, let lostAt, timestamp.timeIntervalSince(lostAt) > Self.longLossResetThreshold {
            // The target disappeared long enough that the pre-loss smoother
            // state would pollute the new measurements: start fresh.
            signalProcessor.reset()
        }

        if let matched {
            guard let smoothed = signalProcessor.ingest(rawRSSI: matched.rssi, at: timestamp) else {
                // Invalid RSSI sample: do not update the snapshot, but still
                // evaluate signal loss so the UI does not linger on a stale one.
                checkSignalLoss(at: timestamp)
                return
            }
            // Copy-on-write the tracked target so we never read and modify the
            // @Observable `target` property in the same expression (runtime
            // exclusivity trap in Debug builds).
            var updatedTarget = target
            if let currentSSID = matched.ssid, !currentSSID.isEmpty {
                updatedTarget.currentSSID = currentSSID
            }
            updatedTarget.channel = matched.channel.channelNumber
            updatedTarget.band = matched.channel.band
            self.target = updatedTarget
            lastSeenAt = timestamp
            lostAt = nil

            state = .tracking(APRadarSnapshot(
                target: updatedTarget,
                rawRSSI: matched.rssi,
                smoothedRSSI: smoothed,
                trend: signalProcessor.trend(at: timestamp),
                lastSeenAt: timestamp
            ))
            if wasLost {
                AppLogger.apRadar.info("AP Radar signal restored")
            }
            if soundEnabled {
                resumeSoundIfNeeded()
            }
        } else {
            checkSignalLoss(at: timestamp)
        }
    }

    func consumeLifecycle(_ event: WiFiObservationLifecycleEvent) async throws {
        if case .started(_, let expectedInterval) = event {
            let seconds = Double(expectedInterval.components.seconds)
            lossTimeout = .seconds(max(8, 2.5 * seconds))
        }
    }

    private func checkSignalLoss(at date: Date) {
        guard let target, let lastSeenAt, state.isTracking else { return }
        let timeout = Double(lossTimeout.components.seconds)
        guard date.timeIntervalSince(lastSeenAt) >= timeout else { return }

        stopPulseAndAudio()
        lostAt = date
        state = .signalLost(APRadarLostSnapshot(
            target: target,
            lastRSSI: signalProcessor.smoothedRSSI,
            lastSeenAt: lastSeenAt
        ))
        AppLogger.apRadar.info("AP Radar signal lost")
    }

    // MARK: - Selection data

    private func updateNetworks(from observation: WiFiObservation) {
        let networks = observation.environmentSnapshot?.networks ?? []
        var deduplicated: [String: WiFiNetworkObservation] = [:]
        for network in networks {
            let key = TrackedAccessPoint.normalizedBSSID(network.bssid)
            if let existing = deduplicated[key] {
                if network.rssi > existing.rssi {
                    deduplicated[key] = network
                }
            } else {
                deduplicated[key] = network
            }
        }
        latestNetworks = Array(deduplicated.values)
    }

    private func updateScanFailure(from observation: WiFiObservation) {
        let failed = observation.errors.contains { error in
            if case .environmentScanFailed = error { return true }
            return false
        }
        scanFailed = failed
    }

    /// AP options for the selection sheet, sorted by RSSI (strongest first),
    /// then SSID, then BSSID.
    var selectionOptions: [APRadarAPOption] {
        latestNetworks
            .map(APRadarAPOption.init)
            .sorted { lhs, rhs in
                if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
                let lhsSSID = lhs.ssid ?? ""
                let rhsSSID = rhs.ssid ?? ""
                if lhsSSID != rhsSSID { return lhsSSID < rhsSSID }
                return lhs.bssid < rhs.bssid
            }
    }
}
