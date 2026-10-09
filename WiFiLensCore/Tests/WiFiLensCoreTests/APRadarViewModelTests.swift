import Foundation
import Testing
import WiFiLensCore
@testable import WiFiLensCore

@MainActor
private final class FakeAudioPlayer: APRadarAudioPlaying {
    var prepareShouldThrow = false
    var playResult = true
    private(set) var prepareCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastPreparedPreset: APRadarSoundPreset?

    func prepare(preset: APRadarSoundPreset) throws {
        prepareCallCount += 1
        lastPreparedPreset = preset
        if prepareShouldThrow {
            throw APRadarAudioError.resourceNotFound
        }
    }

    @discardableResult
    func playPulse() -> Bool {
        playCallCount += 1
        return playResult
    }

    func stop() {
        stopCallCount += 1
    }
}

@MainActor
private final class FakePulseScheduler: APRadarPulseScheduling {
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    private(set) var activeOverride = false
    private(set) var lastStochastic: Bool?

    var isActive: Bool { activeOverride }

    func start(
        shouldContinue: @escaping @MainActor () -> Bool,
        intervalProvider: @escaping @MainActor () -> Duration,
        playPulse: @escaping @MainActor () -> Void,
        stochastic: Bool
    ) {
        startCount += 1
        lastStochastic = stochastic
    }

    func cancel() {
        cancelCount += 1
        activeOverride = false
    }
}

@Suite("APRadarViewModel")
@MainActor
struct APRadarViewModelTests {

    @Test("Picker retains positions while updating signal readings")
    func pickerRetainsPositionsAcrossScans() {
        let first = APRadarAPOption(observation: makeNetwork(bssid: "AA:BB:CC:DD:EE:01", rssi: -40))
        let second = APRadarAPOption(observation: makeNetwork(bssid: "AA:BB:CC:DD:EE:02", rssi: -50))
        var order = APSelectionOrder()
        order.update([first, second])

        let strongerSecond = APRadarAPOption(observation: makeNetwork(bssid: second.bssid, rssi: -30))
        let newAP = APRadarAPOption(observation: makeNetwork(bssid: "AA:BB:CC:DD:EE:03", rssi: -20))
        let nextScan = [newAP, strongerSecond, first]
        order.update(nextScan)
        let arranged = order.arrange(nextScan)
        #expect(arranged.map(\.id) == [first.id, second.id, newAP.id])
        #expect(arranged[1].rssi == -30)

        order.update([newAP, first])
        #expect(order.arrange([newAP, first]).map(\.id) == [first.id, newAP.id])
        order.update([])
        order.update([newAP, first])
        #expect(order.arrange([newAP, first]).map(\.id) == [newAP.id, first.id])
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suite = "APRadarViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeHarness(
        audio: FakeAudioPlayer = FakeAudioPlayer(),
        scheduler: FakePulseScheduler = FakePulseScheduler(),
        defaults: UserDefaults? = nil
    ) -> (viewModel: APRadarViewModel, runtime: WiFiObservationRuntime, audio: FakeAudioPlayer, scheduler: FakePulseScheduler, defaults: UserDefaults) {
        let runtime = WiFiObservationRuntime(store: WiFiObservationStore())
        let resolvedDefaults = defaults ?? makeDefaults()
        let vm = APRadarViewModel(
            observationRuntime: runtime,
            audioPlayer: audio,
            scheduler: scheduler,
            userDefaults: resolvedDefaults
        )
        return (vm, runtime, audio, scheduler, resolvedDefaults)
    }

    private func makeNetwork(
        ssid: String? = "Home Wi-Fi",
        bssid: String,
        rssi: Int,
        channel: Int = 36,
        band: ChannelBand = .band5GHz
    ) -> WiFiNetworkObservation {
        WiFiNetworkObservation(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(band: band, channelNumber: channel, channelWidthMHz: 20)
        )
    }

    private func makeObservation(
        timestamp: Date,
        networks: [WiFiNetworkObservation] = [],
        error: WiFiObservationError? = nil
    ) -> WiFiObservation {
        WiFiObservation(
            timestamp: timestamp,
            environmentSnapshot: WiFiEnvironmentSnapshot(
                timestamp: timestamp,
                interfaceName: nil,
                networks: networks,
                scanDurationMs: nil,
                error: error
            ),
            errors: error.map { [$0] } ?? []
        )
    }

    private func activateAndSelect(
        _ vm: APRadarViewModel,
        bssid: String = "AA:BB:CC:DD:EE:FF",
        ssid: String? = "Home Wi-Fi",
        rssi: Int = -55
    ) {
        vm.setActive(true)
        let option = APRadarAPOption(observation: makeNetwork(ssid: ssid, bssid: bssid, rssi: rssi))
        vm.selectTarget(option)
    }

    private func trackingSnapshot(_ vm: APRadarViewModel) -> APRadarSnapshot? {
        guard case .tracking(let snapshot) = vm.state else { return nil }
        return snapshot
    }

    private func lostSnapshot(_ vm: APRadarViewModel) -> APRadarLostSnapshot? {
        guard case .signalLost(let snapshot) = vm.state else { return nil }
        return snapshot
    }

    // MARK: - Target selection

    @Test("selecting an AP enters tracking with the chosen BSSID")
    func selectEntersTracking() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)

        let snapshot = trackingSnapshot(harness.viewModel)
        #expect(snapshot != nil)
        #expect(snapshot?.target.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(snapshot?.target.currentSSID == "Home Wi-Fi")
        #expect(snapshot?.smoothedRSSI == nil)

        // First valid sample initializes the smoother.
        let t0 = Date(timeIntervalSince1970: 100)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "aa:bb:cc:dd:ee:ff", rssi: -54)])
        )
        let updated = trackingSnapshot(harness.viewModel)
        #expect(updated?.rawRSSI == -54)
        #expect(updated?.smoothedRSSI == -54)
    }

    @Test("failed environment samples do not count as target loss or reuse RSSI")
    func failedScanInvalidatesLiveRadarSignalWithoutDeclaringLoss() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 200)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -51)])
        )
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == -51)

        try await harness.viewModel.consume(
            makeObservation(
                timestamp: t0.addingTimeInterval(60),
                networks: [],
                error: .environmentScanFailed("interface unavailable")
            )
        )

        #expect(harness.viewModel.scanFailed)
        #expect(harness.viewModel.isAwaitingFreshScan)
        #expect(harness.viewModel.latestNetworks.isEmpty)
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == nil)
        #expect(lostSnapshot(harness.viewModel) == nil)
        #expect(harness.scheduler.cancelCount > 0)

        try await harness.viewModel.consume(
            makeObservation(
                timestamp: t0.addingTimeInterval(61),
                networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -47)]
            )
        )
        #expect(!harness.viewModel.scanFailed)
        #expect(!harness.viewModel.isAwaitingFreshScan)
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == -47)
        #expect(lostSnapshot(harness.viewModel) == nil)
    }

    @Test("matching is BSSID-based and case/whitespace insensitive")
    func matchingNormalizesBSSID() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel, bssid: "AA:BB:CC:DD:EE:FF")
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: " aa:bb:cc:dd:ee:ff ", rssi: -48)])
        )
        #expect(trackingSnapshot(harness.viewModel)?.rawRSSI == -48)
    }

    @Test("invalid RSSI samples are ignored and do not update state")
    func invalidRSSIIsIgnored() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(1), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: 5)])
        )
        let snapshot = trackingSnapshot(harness.viewModel)
        #expect(snapshot?.rawRSSI == -60)
        #expect(snapshot?.smoothedRSSI == -60)
        #expect(snapshot?.lastSeenAt == t0)
    }

    @Test("reappearing target without SSID keeps identity and refreshes channel/band")
    func reappearingTargetWithoutSSIDKeepsIdentity() async throws {
        // Regression: consume() used to read and modify the @Observable
        // `target` property inside one expression when the fresh sample had no
        // SSID, trapping with an exclusivity conflict in Debug builds.
        let harness = makeHarness()
        activateAndSelect(harness.viewModel, bssid: "AA:BB:CC:DD:EE:FF", ssid: "Home Wi-Fi")
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [
                makeNetwork(ssid: nil, bssid: "AA:BB:CC:DD:EE:FF", rssi: -53, channel: 149, band: .band5GHz)
            ])
        )
        let snapshot = trackingSnapshot(harness.viewModel)
        #expect(snapshot?.rawRSSI == -53)
        #expect(snapshot?.smoothedRSSI == -53)
        #expect(snapshot?.target.currentSSID == "Home Wi-Fi")
        #expect(snapshot?.target.channel == 149)
        #expect(snapshot?.target.band == .band5GHz)
    }

    @Test("empty SSID is treated as a hidden network")
    func emptySSIDIsHiddenNetwork() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel, bssid: "AA:BB:CC:DD:EE:FF", ssid: "")
        #expect(trackingSnapshot(harness.viewModel)?.target.currentSSID == nil)

        // A later sample with an empty SSID must not blank out a known name.
        harness.viewModel.stopTracking()
        activateAndSelect(harness.viewModel, bssid: "AA:BB:CC:DD:EE:FF", ssid: "Home Wi-Fi")
        let t0 = Date(timeIntervalSince1970: 100)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [
                makeNetwork(ssid: "", bssid: "AA:BB:CC:DD:EE:FF", rssi: -53)
            ])
        )
        let snapshot = trackingSnapshot(harness.viewModel)
        #expect(snapshot?.target.currentSSID == "Home Wi-Fi")
        #expect(snapshot?.rawRSSI == -53)
    }

    // MARK: - Signal lost

    @Test("missing target past the timeout enters signal lost and stops sound")
    func signalLostStopsSound() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        let cancelsBefore = harness.scheduler.cancelCount

        // 9 seconds later with no target: 9 >= 8s default timeout.
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(lostSnapshot(harness.viewModel) != nil)
        #expect(harness.scheduler.cancelCount > cancelsBefore)
        #expect(harness.audio.stopCallCount >= 1)
        #expect(harness.viewModel.state.isTracking == false)
    }

    @Test("lifecycle scan interval extends the loss timeout to max(8s, 2.5x)")
    func lifecycleExtendsLossTimeout() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consumeLifecycle(.started(at: t0, expectedInterval: .seconds(4)))
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )

        // 9s < 10s timeout from a 4s scan interval: still tracking.
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(harness.viewModel.state.isTracking)
        #expect(lostSnapshot(harness.viewModel) == nil)

        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(10)))
        #expect(lostSnapshot(harness.viewModel) != nil)
    }

    @Test("same BSSID reappearing restores tracking automatically")
    func sameBSSIDRestoresTracking() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(lostSnapshot(harness.viewModel) != nil)

        let t1 = t0.addingTimeInterval(10)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t1, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -55)])
        )
        let snapshot = trackingSnapshot(harness.viewModel)
        #expect(snapshot != nil)
        #expect(snapshot?.rawRSSI == -55)
        #expect(snapshot?.lastSeenAt == t1)
    }

    @Test("a different BSSID with the same SSID cannot restore tracking")
    func differentBSSIDSameSSIDDoesNotRestore() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel, bssid: "AA:BB:CC:DD:EE:FF", ssid: "Shared SSID")
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(ssid: "Shared SSID", bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(lostSnapshot(harness.viewModel) != nil)

        // Another AP with the same SSID appears; the target BSSID is still absent.
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(10), networks: [
                makeNetwork(ssid: "Shared SSID", bssid: "11:22:33:44:55:66", rssi: -40)
            ])
        )
        #expect(lostSnapshot(harness.viewModel) != nil)
    }

    @Test("recovery after a long loss resets the smoother")
    func longLossResetsSmoother() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(1), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -50)])
        )
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(lostSnapshot(harness.viewModel) != nil)

        // 16 seconds after loss (> 15s): the first new sample is the baseline.
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(25), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -80)])
        )
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == -80)
    }

    @Test("recovery after a short loss keeps the smoother state")
    func shortLossKeepsSmoother() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)

        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(1), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -50)])
        )
        try await harness.viewModel.consume(makeObservation(timestamp: t0.addingTimeInterval(9)))
        #expect(lostSnapshot(harness.viewModel) != nil)

        // 1 second after loss (< 15s): EMA continues from -57.
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(10), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -80)])
        )
        let smoothed = trackingSnapshot(harness.viewModel)?.smoothedRSSI ?? .nan
        #expect(abs(smoothed - (-63.9)) < 0.0001)
    }

    // MARK: - Sound

    @Test("sound off prevents all audio and scheduler activity")
    func soundOffPreventsAudio() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: APRadarViewModel.soundEnabledKey)
        let harness = makeHarness(defaults: defaults)
        #expect(harness.viewModel.soundEnabled == false)

        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        #expect(harness.viewModel.state.isTracking)
        #expect(harness.audio.playCallCount == 0)
        #expect(harness.audio.prepareCallCount == 0)
        #expect(harness.scheduler.startCount == 0)
    }

    @Test("re-enabling sound resumes audio after a valid sample")
    func reEnablingSoundResumes() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: APRadarViewModel.soundEnabledKey)
        let harness = makeHarness(defaults: defaults)

        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        #expect(harness.scheduler.startCount == 0)

        harness.viewModel.setSoundEnabled(true)
        #expect(harness.viewModel.soundEnabled == true)
        #expect(harness.audio.prepareCallCount >= 1)
        #expect(harness.scheduler.startCount == 1)
    }

    @Test("turning sound off cancels the active pulse scheduler")
    func turningSoundOffCancelsScheduler() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        #expect(harness.scheduler.startCount == 1)

        harness.viewModel.setSoundEnabled(false)
        #expect(harness.scheduler.cancelCount >= 1)
        #expect(harness.audio.stopCallCount >= 1)
    }

    @Test("audio initialization failure does not terminate RSSI tracking")
    func audioFailureKeepsTracking() async throws {
        let audio = FakeAudioPlayer()
        audio.prepareShouldThrow = true
        let harness = makeHarness(audio: audio)

        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        #expect(harness.viewModel.audioAvailable == false)
        #expect(harness.viewModel.audioErrorMessage != nil)
        #expect(harness.scheduler.startCount == 0)
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == -54)

        // Tracking continues and updates with later samples.
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(1), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -60)])
        )
        let smoothed = trackingSnapshot(harness.viewModel)?.smoothedRSSI ?? .nan
        #expect(abs(smoothed - (-55.8)) < 0.0001)
        // The failure is reported only once.
        #expect(harness.audio.prepareCallCount >= 1)
    }

    // MARK: - Lifecycle

    @Test("stop tracking cancels the scheduler and returns to idle")
    func stopTrackingCancelsScheduler() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        #expect(harness.scheduler.startCount == 1)

        harness.viewModel.stopTracking()

        #expect(harness.viewModel.state == .idle)
        #expect(harness.scheduler.cancelCount >= 1)
        #expect(harness.audio.stopCallCount >= 1)
        #expect(trackingSnapshot(harness.viewModel) == nil)
    }

    @Test("leaving the page cancels scheduling and releases the scan subscription")
    func leavingPageReleasesSubscription() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        #expect(harness.runtime.diagnostics().count == 1)
        let cancelsAfterStart = harness.scheduler.cancelCount

        harness.viewModel.setActive(false)
        #expect(harness.runtime.diagnostics().count == 0)
        #expect(harness.scheduler.cancelCount > cancelsAfterStart)
        #expect(harness.audio.stopCallCount >= 1)
    }

    @Test("repeated page visits do not stack scan subscriptions")
    func repeatedVisitsDoNotStackSubscriptions() {
        let harness = makeHarness()
        for _ in 0..<10 {
            harness.viewModel.setActive(true)
            #expect(harness.runtime.diagnostics().count == 1)
            harness.viewModel.setActive(false)
            #expect(harness.runtime.diagnostics().count == 0)
        }
    }

    @Test("returning to the page starts from the idle state")
    func returningStartsIdle() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        harness.viewModel.setActive(false)
        harness.viewModel.setActive(true)

        #expect(harness.viewModel.state == .idle)
        #expect(trackingSnapshot(harness.viewModel) == nil)
    }

    @Test("suspend stops sound and scheduling while preserving the target")
    func suspendPreservesTarget() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        harness.viewModel.handleAppBackground()

        #expect(harness.scheduler.cancelCount >= 1)
        #expect(harness.audio.stopCallCount >= 1)
        // Target is preserved; once the app returns to active, a fresh sample
        // resumes the session.
        harness.viewModel.handleAppActive()
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 101), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -50)])
        )
        #expect(trackingSnapshot(harness.viewModel) != nil)
    }

    @Test("observations while suspended do not restart sound or tracking")
    func suspendedObservationsStaySuspended() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        let t0 = Date(timeIntervalSince1970: 100)
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0, networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        harness.viewModel.handleAppBackground()
        let schedulerStarts = harness.scheduler.startCount
        let playCalls = harness.audio.playCallCount

        // A fresh sample while backgrounded must not clear the suspension or
        // re-arm the pulse loop (the app could still be in the background).
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(1), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -50)])
        )
        #expect(harness.scheduler.startCount == schedulerStarts)
        #expect(harness.audio.playCallCount == playCalls)
        // The sample was ignored, so the smoother still holds the old value.
        #expect(trackingSnapshot(harness.viewModel)?.smoothedRSSI == -54)

        // Returning to active allows the next sample to resume tracking.
        harness.viewModel.handleAppActive()
        try await harness.viewModel.consume(
            makeObservation(timestamp: t0.addingTimeInterval(2), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -48)])
        )
        #expect(trackingSnapshot(harness.viewModel)?.rawRSSI == -48)
        #expect(harness.scheduler.startCount > schedulerStarts)
    }

    // MARK: - Sound presets

    @Test("changing the preset persists the choice and reloads audio")
    func changingPresetPersistsAndReloads() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        // Audio is prepared once the first valid sample arrives.
        #expect(harness.audio.prepareCallCount >= 1)
        #expect(harness.audio.lastPreparedPreset == .softPulse)

        harness.viewModel.setSoundPreset(.blip)

        #expect(harness.viewModel.soundPreset == .blip)
        #expect(harness.defaults.string(forKey: APRadarViewModel.soundPresetKey) == "blip")
        #expect(harness.audio.lastPreparedPreset == .blip)
    }

    @Test("preset stored in preferences applies when the session begins")
    func storedPresetAppliesOnSessionStart() {
        let defaults = makeDefaults()
        defaults.set("tick", forKey: APRadarViewModel.soundPresetKey)
        let harness = makeHarness(defaults: defaults)
        #expect(harness.viewModel.soundPreset == .tick)

        harness.viewModel.setActive(true)
        #expect(harness.viewModel.soundPreset == .tick)
    }

    @Test("unknown stored preset falls back to the default")
    func unknownStoredPresetFallsBack() {
        let defaults = makeDefaults()
        defaults.set("not-a-preset", forKey: APRadarViewModel.soundPresetKey)
        let harness = makeHarness(defaults: defaults)
        #expect(harness.viewModel.soundPreset == .softPulse)
    }

    // MARK: - Geiger easter egg

    @Test("unlocking the Geiger preset persists and reports first unlock")
    func unlockingGeigerPersists() {
        let harness = makeHarness()
        #expect(harness.viewModel.geigerUnlocked == false)

        #expect(harness.viewModel.unlockGeigerPreset() == true)
        #expect(harness.viewModel.geigerUnlocked == true)
        #expect(harness.defaults.bool(forKey: APRadarViewModel.geigerUnlockedKey) == true)

        #expect(harness.viewModel.unlockGeigerPreset() == false)
    }

    @Test("an already unlocked Geiger preset is honored on session start")
    func unlockedGeigerPersistsAcrossSessions() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: APRadarViewModel.geigerUnlockedKey)
        let harness = makeHarness(defaults: defaults)
        #expect(harness.viewModel.geigerUnlocked == true)
    }

    @Test("geiger preset schedules stochastic pulses")
    func geigerSchedulesStochasticPulses() async throws {
        let defaults = makeDefaults()
        defaults.set(APRadarSoundPreset.geiger.rawValue, forKey: APRadarViewModel.soundPresetKey)
        let harness = makeHarness(defaults: defaults)

        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        #expect(harness.scheduler.startCount == 1)
        #expect(harness.scheduler.lastStochastic == true)
        #expect(harness.audio.lastPreparedPreset == .geiger)
    }

    @Test("non-geiger presets schedule deterministic pulses")
    func nonGeigerSchedulesDeterministicPulses() async throws {
        let defaults = makeDefaults()
        defaults.set(APRadarSoundPreset.blip.rawValue, forKey: APRadarViewModel.soundPresetKey)
        let harness = makeHarness(defaults: defaults)

        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )

        #expect(harness.scheduler.startCount == 1)
        #expect(harness.scheduler.lastStochastic == false)
    }

    @Test("switching to geiger while tracking restarts the scheduler stochastically")
    func switchingToGeigerRestartsScheduler() async throws {
        let harness = makeHarness()
        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        #expect(harness.scheduler.startCount == 1)
        #expect(harness.scheduler.lastStochastic == false)

        let cancelsBefore = harness.scheduler.cancelCount
        harness.viewModel.setSoundPreset(.geiger)

        #expect(harness.scheduler.startCount == 2)
        #expect(harness.scheduler.lastStochastic == true)
        #expect(harness.scheduler.cancelCount > cancelsBefore)
        #expect(harness.audio.lastPreparedPreset == .geiger)
    }

    @Test("switching away from geiger restarts the scheduler deterministically")
    func switchingAwayFromGeigerRestartsScheduler() async throws {
        let defaults = makeDefaults()
        defaults.set(APRadarSoundPreset.geiger.rawValue, forKey: APRadarViewModel.soundPresetKey)
        let harness = makeHarness(defaults: defaults)

        activateAndSelect(harness.viewModel)
        try await harness.viewModel.consume(
            makeObservation(timestamp: Date(timeIntervalSince1970: 100), networks: [makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", rssi: -54)])
        )
        #expect(harness.scheduler.lastStochastic == true)

        harness.viewModel.setSoundPreset(.softPulse)

        #expect(harness.scheduler.startCount == 2)
        #expect(harness.scheduler.lastStochastic == false)
    }

}

/// Deterministic sleep seam for AP Radar audio and scheduler tests. `sleep(for:)`
/// suspends until the test calls `advance(by:)`, so every wait is driven
/// explicitly and no test relies on wall-clock timing.
@MainActor
private final class ManualSleeper {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private(set) var elapsed: Duration = .zero
    private(set) var requestedDurations: [Duration] = []
    private var waiters: [Waiter] = []

    /// Registers a sleep that fires once `elapsed` reaches its deadline.
    func sleep(for duration: Duration) async {
        requestedDurations.append(duration)
        let deadline = elapsed + duration
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(Waiter(deadline: deadline, continuation: continuation))
        }
    }

    /// Advances the fake clock and resumes every sleep whose deadline is due.
    func advance(by duration: Duration) {
        elapsed += duration
        let due = waiters.filter { $0.deadline <= elapsed }
        waiters.removeAll { $0.deadline <= elapsed }
        for waiter in due {
            waiter.continuation.resume()
        }
    }

    /// Yields until the production task registers its next sleep, letting any
    /// resumed task run to its next suspension. Bounded so a missing sleep
    /// fails the test instead of hanging CI.
    func waitForPendingSleep() async {
        for _ in 0..<1_000 where waiters.isEmpty {
            await Task.yield()
        }
    }
}

@Suite("APRadarSoundPreviewer")
@MainActor
struct APRadarSoundPreviewerTests {
    private func makePreviewer(
        _ audio: FakeAudioPlayer,
        _ sleeper: ManualSleeper
    ) -> APRadarSoundPreviewer {
        APRadarSoundPreviewer(player: audio, sleep: sleeper.sleep(for:))
    }

    @Test("preview prepares the preset and plays a short burst")
    func previewPlaysShortBurst() async throws {
        let audio = FakeAudioPlayer()
        let sleeper = ManualSleeper()
        let previewer = makePreviewer(audio, sleeper)

        let started = previewer.start(preset: .tick)
        #expect(started)
        #expect(previewer.isPlaying)
        #expect(audio.prepareCallCount == 1)
        #expect(audio.lastPreparedPreset == .tick)

        // Three pulses at 300 ms spacing; drive each wait explicitly.
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == 1)
        #expect(previewer.isPlaying)

        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == 2)
        #expect(previewer.isPlaying)

        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == 3)
        #expect(previewer.isPlaying)

        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(!previewer.isPlaying)
        #expect(audio.stopCallCount >= 1)
    }

    @Test("stop cancels the preview task immediately")
    func stopCancelsPreview() async throws {
        let audio = FakeAudioPlayer()
        let sleeper = ManualSleeper()
        let previewer = makePreviewer(audio, sleeper)

        previewer.start(preset: .tick)
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == 1)

        previewer.stop()

        let playCountAfterStop = audio.playCallCount
        #expect(!previewer.isPlaying)
        #expect(audio.stopCallCount >= 1)

        // Wake the cancelled task; it must not fire any further pulses.
        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == playCountAfterStop)
    }

    @Test("preview failure is non-fatal and stays silent")
    func previewFailsGracefully() async throws {
        let audio = FakeAudioPlayer()
        audio.prepareShouldThrow = true
        let previewer = APRadarSoundPreviewer(player: audio)

        let started = previewer.start(preset: .blip)
        #expect(!started)
        #expect(!previewer.isPlaying)
        #expect(audio.playCallCount == 0)
    }

    @Test("geiger preview plays a burst of irregular clicks")
    func geigerPreviewPlaysBurst() async throws {
        let audio = FakeAudioPlayer()
        let sleeper = ManualSleeper()
        let previewer = makePreviewer(audio, sleeper)

        previewer.start(preset: .geiger)
        #expect(audio.lastPreparedPreset == .geiger)
        #expect(previewer.isPlaying)

        // Drive ~1.5 s of burst time in chunks. The exact click count is
        // random, but several pulses must fire and stop() must silence it.
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount >= 1)

        for _ in 0..<6 {
            sleeper.advance(by: .milliseconds(250))
            await sleeper.waitForPendingSleep()
        }
        #expect(audio.playCallCount >= 2)

        previewer.stop()
        #expect(!previewer.isPlaying)
    }

    @Test("replacing a preview immediately does not stop the new one")
    func replacingPreviewDoesNotStopNewOne() async throws {
        let audio = FakeAudioPlayer()
        let sleeper = ManualSleeper()
        let previewer = makePreviewer(audio, sleeper)

        // Tick preview starts and reaches its first sleep.
        previewer.start(preset: .tick)
        await sleeper.waitForPendingSleep()
        #expect(audio.playCallCount == 1)

        // Replace with blip while the tick loop is mid-sleep (the race).
        previewer.start(preset: .blip)
        #expect(previewer.isPlaying)
        #expect(audio.lastPreparedPreset == .blip)

        // Wake the stale tick loop first: it must not stop the blip preview.
        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(previewer.isPlaying)
        #expect(audio.lastPreparedPreset == .blip)
        #expect(audio.playCallCount == 2)

        // The blip preview continues: pulse 2, pulse 3, then natural stop.
        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(previewer.isPlaying)
        #expect(audio.playCallCount == 3)

        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(previewer.isPlaying)
        #expect(audio.playCallCount == 4)

        sleeper.advance(by: .milliseconds(300))
        await sleeper.waitForPendingSleep()
        #expect(!previewer.isPlaying)
        #expect(audio.stopCallCount >= 1)
    }

    @Test("toggling while playing stops the preview")
    func toggleStopsPreview() async throws {
        let audio = FakeAudioPlayer()
        let previewer = APRadarSoundPreviewer(player: audio)

        previewer.toggle(preset: .tick)
        #expect(previewer.isPlaying)

        previewer.toggle(preset: .tick)
        #expect(!previewer.isPlaying)
        #expect(audio.stopCallCount >= 1)
    }
}

@Suite("APRadarPulseScheduler")
@MainActor
struct APRadarPulseSchedulerTests {
    @Test("immediate restart keeps the new loop active and pulsing")
    func restartKeepsNewLoopActive() async {
        let sleeper = ManualSleeper()
        let scheduler = APRadarPulseScheduler(sleep: sleeper.sleep(for:))
        let counter = PulseCounter()
        var shouldContinue = true
        let interval: Duration = .milliseconds(80)

        // Preset changes / cadence-mode switches call start() twice back to
        // back. Loop A starts and reaches its first sleep.
        scheduler.start(
            shouldContinue: { shouldContinue },
            intervalProvider: { interval },
            playPulse: { counter.increment() },
            stochastic: false
        )
        await sleeper.waitForPendingSleep()
        #expect(counter.count == 1)

        // Replace the loop while A is mid-sleep; B takes over but cannot run
        // until A's sleep is driven to completion.
        scheduler.start(
            shouldContinue: { shouldContinue },
            intervalProvider: { interval },
            playPulse: { counter.increment() },
            stochastic: false
        )

        // Wake the stale A first: it must not tear down B.
        sleeper.advance(by: interval)
        await sleeper.waitForPendingSleep()
        #expect(scheduler.isActive)
        #expect(counter.count == 2)

        // B keeps pulsing until told to stop.
        sleeper.advance(by: interval)
        await sleeper.waitForPendingSleep()
        #expect(scheduler.isActive)
        #expect(counter.count == 3)

        sleeper.advance(by: interval)
        await sleeper.waitForPendingSleep()
        #expect(scheduler.isActive)
        #expect(counter.count == 4)

        shouldContinue = false
        scheduler.cancel()
        #expect(!scheduler.isActive)
    }
}

/// Thread-confined pulse counter for scheduler tests.
@MainActor
private final class PulseCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
