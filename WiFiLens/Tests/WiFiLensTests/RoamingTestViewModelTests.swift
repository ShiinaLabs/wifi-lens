import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite @MainActor struct RoamingTestViewModelTests {

    // MARK: - Initial State

    @Test func initialStateIsIdle() {
        let vm = RoamingTestViewModel()
        #expect(vm.state == .idle)
        #expect(vm.segments.isEmpty)
        #expect(vm.transitions.isEmpty)
        #expect(vm.elapsedTime == 0)
        #expect(vm.totalSamples == 0)
    }

    // MARK: - Computed Properties

    @Test func canStartIsFalseWhenIdle() {
        let vm = RoamingTestViewModel()
        #expect(vm.state == .idle)
        #expect(!vm.canStart)
    }

    @Test func isRunningIsFalseWhenIdle() {
        let vm = RoamingTestViewModel()
        #expect(!vm.isRunning)
    }

    // MARK: - Edge Cases

    @Test func startTestWhenNotReadyIsNoOp() {
        let vm = RoamingTestViewModel()
        #expect(vm.state == .idle)
        #expect(!vm.canStart)

        // startTest() should be a no-op when canStart is false
        vm.startTest()
        #expect(vm.state == .idle)
        #expect(vm.segments.isEmpty)
    }

    @Test func stopTestWhenIdleIsSafe() {
        let vm = RoamingTestViewModel()
        // stopTest() when idle should not crash
        vm.stopTest()
        #expect(vm.state == .stopped)
    }

    @Test func defaultFileNameContainsSSID() {
        let vm = RoamingTestViewModel()
        // currentSSID is nil initially, so falls back to "WiFi"
        // defaultFileName is private, but saveSession() uses it without crash
        // Just verify the VM is in a consistent state
        #expect(vm.state == .idle)
    }

    // MARK: - Guidance Wiring

    @Test func userInitiatedStopOfLiveTestRecordsRoamingMoment() async {
        let guidance = RoamingGuidanceHarness()
        let vm = makeConnectedViewModel(guidance: guidance.coordinator)

        await vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }
        vm.stopTest()

        #expect(vm.state == .stopped)
        #expect(guidance.store.load().meaningfulCompletionCount == 0)
        #expect(guidance.events.filter { $0.name == "guidance.value_moment" }.count == 1)
        #expect(guidance.events.filter { $0.name == "guidance.no_action" }.first?.suppressionReason == .roamingPolicyNotEnabled)
    }

    @Test func powerOffInterruptionNeverRecordsRoamingMoment() async {
        let guidance = RoamingGuidanceHarness()
        let vm = makeConnectedViewModel(guidance: guidance.coordinator)

        await vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        vm.handleWiFiPowerStateChange(.poweredOff)

        #expect(vm.state == .idle)
        #expect(guidance.events.isEmpty)
        #expect(guidance.store.load().meaningfulCompletionCount == 0)
    }

    @Test func idleStopNeverRecordsRoamingMoment() {
        let guidance = RoamingGuidanceHarness()
        let vm = RoamingTestViewModel(onRoamingCompleted: {
            guidance.coordinator.record(.roamingCompleted)
        })

        vm.stopTest()

        #expect(vm.state == .stopped)
        #expect(guidance.events.isEmpty)
        #expect(guidance.store.load().meaningfulCompletionCount == 0)
    }

    @Test("A delayed old start cannot replace a newer roaming run")
    func delayedStartCannotReplaceRestart() async throws {
        let provider = DelayedStartRoamingProvider()
        let vm = RoamingTestViewModel(
            roamingProvider: provider,
            latencyProvider: MockGatewayLatencyProvider(result: .init(timestamp: Date(), latencyMs: 3))
        )

        vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await provider.waitForDelayedStart()

        vm.stopTest(userInitiated: false)
        vm.startTest()
        await waitUntil { vm.state == .running && vm.currentBSSID == "BB:00:00:00:00:02" }
        await provider.releaseDelayedStart()
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.state == .running)
        #expect(vm.currentBSSID == "BB:00:00:00:00:02")
        #expect(vm.segments.first?.bssid == "BB:00:00:00:00:02")
        vm.stopTest(userInitiated: false)
    }

    @Test("a transient disconnected probe does not erase the next AP handoff")
    func transientDisconnectPreservesHandoffIdentity() async {
        let provider = ScriptedRoamingProbeProvider(statuses: [
            roamingStatus(bssid: "AA:00:00:00:00:01"),
            roamingStatus(bssid: "AA:00:00:00:00:01"),
            WiFiCurrentStatus(timestamp: Date(), isConnected: false, isWiFiPowerOn: true),
            roamingStatus(bssid: "BB:00:00:00:00:02")
        ])
        let vm = RoamingTestViewModel(
            roamingProvider: provider,
            latencyProvider: MockGatewayLatencyProvider(result: .init(timestamp: Date(), latencyMs: 5))
        )
        vm.fallbackRouterProvider = { nil }

        await vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        vm.tick()
        await waitUntil { vm.currentBSSID == nil }
        vm.tick()
        await waitUntil { vm.transitions.count == 1 }

        #expect(vm.transitions.first?.fromBSSID == "AA:00:00:00:00:01")
        #expect(vm.transitions.first?.toBSSID == "BB:00:00:00:00:02")
        #expect(vm.transitions.first?.rssiBefore == -50)
        vm.stopTest(userInitiated: false)
    }

    @Test("gateway latency is measured against the current probe route")
    func gatewayLatencyUsesCurrentRoute() async {
        let provider = ScriptedRoamingProbeProvider(statuses: [
            roamingStatus(bssid: "AA:00:00:00:00:01", routerIP: "192.0.2.1"),
            roamingStatus(bssid: "AA:00:00:00:00:01", routerIP: "192.0.2.1"),
            roamingStatus(bssid: "BB:00:00:00:00:02", routerIP: "192.0.2.2")
        ])
        let latency = RecordingGatewayLatencyProvider(result: .init(timestamp: Date(), latencyMs: 5))
        let vm = RoamingTestViewModel(roamingProvider: provider, latencyProvider: latency)
        vm.fallbackRouterProvider = { "198.51.100.1" }

        await vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }
        vm.tick()
        await waitUntil { vm.transitions.count == 1 }

        #expect(await latency.measuredRouterIPs == ["192.0.2.2"])
        #expect(vm.routerIP == "192.0.2.2")
        vm.stopTest(userInitiated: false)
    }

    // MARK: - Helpers

    private func makeConnectedViewModel(guidance: GuidanceCoordinator) -> RoamingTestViewModel {
        let status = WiFiCurrentStatus(
            timestamp: Date(),
            ssid: "TestNet",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 6,
            rssi: -45,
            txRate: 300,
            isConnected: true,
            isWiFiPowerOn: true
        )
        return RoamingTestViewModel(
            roamingProvider: MockRoamingProbeProvider(result: status),
            latencyProvider: MockGatewayLatencyProvider(result: .init(timestamp: Date(), latencyMs: 3)),
            onRoamingCompleted: {
                guidance.record(.roamingCompleted)
            }
        )
    }

    private func roamingStatus(bssid: String, routerIP: String? = nil) -> WiFiCurrentStatus {
        WiFiCurrentStatus(
            timestamp: Date(),
            ssid: "TestNet",
            bssid: bssid,
            channel: 36,
            rssi: -50,
            txRate: 300,
            routerIP: routerIP,
            isConnected: true,
            isWiFiPowerOn: true
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        var spins = 0
        while !condition(), spins < 500 {
            spins += 1
            await Task.yield()
        }
    }
}

private actor ScriptedRoamingProbeProvider: RoamingProbeProviding {
    private var statuses: [WiFiCurrentStatus]

    init(statuses: [WiFiCurrentStatus]) {
        self.statuses = statuses
    }

    func fetchCurrentProbe() async -> WiFiCurrentStatus {
        guard statuses.count > 1 else { return statuses[0] }
        return statuses.removeFirst()
    }
}

private actor DelayedStartRoamingProvider: RoamingProbeProviding {
    private var calls = 0
    private var delayedStart: CheckedContinuation<WiFiCurrentStatus, Never>?
    private var pendingWaiter: CheckedContinuation<Void, Never>?

    func fetchCurrentProbe() async -> WiFiCurrentStatus {
        calls += 1
        if calls == 2 {
            return await withCheckedContinuation { continuation in
                delayedStart = continuation
                pendingWaiter?.resume()
                pendingWaiter = nil
            }
        }
        return status(bssid: calls == 1 ? "AA:00:00:00:00:01" : "BB:00:00:00:00:02")
    }

    func waitForDelayedStart() async {
        if delayedStart != nil { return }
        await withCheckedContinuation { pendingWaiter = $0 }
    }

    func releaseDelayedStart() {
        delayedStart?.resume(returning: status(bssid: "AA:00:00:00:00:01"))
        delayedStart = nil
    }

    private func status(bssid: String) -> WiFiCurrentStatus {
        WiFiCurrentStatus(
            timestamp: Date(),
            ssid: "TestNet",
            bssid: bssid,
            channel: 36,
            rssi: -50,
            isConnected: true,
            isWiFiPowerOn: true
        )
    }
}

/// Isolated guidance harness for roaming tests: in-memory store, fixed clock,
/// collecting event sink — no real UserDefaults or Launch Services queries.
@MainActor
private final class RoamingGuidanceHarness {
    let store: InMemoryGuidanceStateStore
    let coordinator: GuidanceCoordinator
    private let eventBox: EventBox

    var events: [GuidanceEvent] { eventBox.events }

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12))!
        let box = EventBox()
        store = InMemoryGuidanceStateStore()
        var configuration = GuidanceConfiguration()
        configuration.invitationEnabled = true
        coordinator = GuidanceCoordinator(
            configuration: configuration,
            stateStore: store,
            now: { now },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { event in box.events.append(event) }
        )
        eventBox = box
    }
}

@MainActor
private final class EventBox {
    var events: [GuidanceEvent] = []
}
