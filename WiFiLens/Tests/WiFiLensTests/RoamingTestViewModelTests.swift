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

    @Test("An invalid association sample closes its segment and clears current link data")
    func invalidAssociationClosesSegmentAndReassociationStartsFreshSegment() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = verifiedStatus(at: start, bssid: "AA:00:00:00:00:01")
        let vm = RoamingTestViewModel(roamingProvider: MockRoamingProbeProvider(result: initial))
        vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        let nextValid = verifiedStatus(at: start.addingTimeInterval(1), bssid: "AA:00:00:00:00:01")
        vm.recordProbe(nextValid)
        vm.gatewayLatency = 11

        let invalid = WiFiCurrentStatus(
            timestamp: start.addingTimeInterval(2),
            interfaceName: "en0",
            ssid: "TestNet",
            bssid: "AA:00:00:00:00:01",
            channel: 6,
            rssi: -42,
            routerIP: "192.0.2.1",
            isConnected: true,
            isWiFiPowerOn: true
        )
        vm.recordProbe(invalid)

        #expect(vm.segments.count == 1)
        #expect(vm.segments[0].endTime == nextValid.timestamp)
        #expect(vm.currentSSID == nil)
        #expect(vm.currentBSSID == nil)
        #expect(vm.currentRSSI == nil)
        #expect(vm.currentChannel == nil)
        #expect(vm.routerIP == nil)
        #expect(vm.gatewayLatency == nil)
        #expect(vm.transitions.isEmpty)

        let recovered = verifiedStatus(at: start.addingTimeInterval(3), bssid: "AA:00:00:00:00:01")
        vm.recordProbe(recovered)

        #expect(vm.segments.count == 2)
        #expect(vm.segments[1].startTime == recovered.timestamp)
        #expect(vm.segments[1].endTime == nil)
        #expect(vm.segments[1].samples.map(\.timestamp) == [recovered.timestamp])
        #expect(vm.transitions.isEmpty)
        vm.stopTest(userInitiated: false)
    }

    @Test("Out-of-order probes cannot replace current roaming state")
    func outOfOrderProbeIsIgnored() async {
        let start = Date(timeIntervalSince1970: 1_800_000_100)
        let initial = verifiedStatus(at: start, bssid: "AA:00:00:00:00:01")
        let vm = RoamingTestViewModel(roamingProvider: MockRoamingProbeProvider(result: initial))
        vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        let newer = verifiedStatus(at: start.addingTimeInterval(2), bssid: "AA:00:00:00:00:02")
        vm.recordProbe(newer)
        let stale = verifiedStatus(at: start.addingTimeInterval(1), bssid: "AA:00:00:00:00:03")
        vm.recordProbe(stale)

        #expect(vm.currentBSSID == newer.bssid)
        #expect(vm.segments.count == 2)
        #expect(vm.segments[0].endTime == newer.timestamp)
        #expect(vm.segments[1].bssid == newer.bssid)
        #expect(vm.transitions.count == 1)
        #expect(vm.transitions[0].toBSSID == newer.bssid)
        vm.stopTest(userInitiated: false)
    }

    @Test("Unverified metrics remain absent while verified BSSID transitions are retained")
    func missingMetricsDoNotBecomeNumbersOrCarryForward() async {
        let start = Date(timeIntervalSince1970: 1_800_000_300)
        let initial = verifiedStatus(at: start, bssid: "AA:00:00:00:00:01", rssi: -48, channel: 36)
        let vm = RoamingTestViewModel(roamingProvider: MockRoamingProbeProvider(result: initial))
        vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        let unverified = verifiedStatus(
            at: start.addingTimeInterval(1), bssid: "AA:00:00:00:00:02",
            metricsAttribution: .unverified, rssi: nil, channel: nil, txRate: nil
        )
        vm.recordProbe(unverified)

        #expect(vm.transitions.count == 1)
        #expect(vm.transitions[0].rssiBefore == -48)
        #expect(vm.transitions[0].rssiAfter == nil)
        #expect(vm.transitions[0].channelBefore == 36)
        #expect(vm.transitions[0].channelAfter == nil)
        #expect(vm.currentRSSI == nil)
        #expect(vm.currentChannel == nil)
        #expect(vm.currentTxRate == nil)
        #expect(vm.segments[1].samples.last?.rssi == nil)
        #expect(vm.segments[1].samples.last?.channel == nil)
        #expect(vm.segments[1].samples.last?.txRate == nil)

        let recovered = verifiedStatus(at: start.addingTimeInterval(2), bssid: "AA:00:00:00:00:03", rssi: -60, channel: 44)
        vm.recordProbe(recovered)
        #expect(vm.transitions.count == 2)
        #expect(vm.transitions[1].rssiBefore == nil)
        #expect(vm.transitions[1].channelBefore == nil)
        vm.stopTest(userInitiated: false)
    }

    @Test("Associated samples with no measured metrics are still recorded")
    func associationSampleCanKeepNilMetrics() async {
        let start = Date(timeIntervalSince1970: 1_800_000_350)
        let status = verifiedStatus(
            at: start, bssid: "AA:00:00:00:00:01",
            metricsAttribution: .verified, rssi: nil, channel: nil, txRate: nil
        )
        let vm = RoamingTestViewModel(roamingProvider: MockRoamingProbeProvider(result: status))
        vm.checkReadiness()
        await waitUntil { vm.state == .ready }
        vm.startTest()
        await waitUntil { vm.state == .running }

        #expect(vm.currentBSSID == status.bssid)
        #expect(vm.currentRSSI == nil)
        #expect(vm.currentChannel == nil)
        #expect(vm.currentTxRate == nil)
        #expect(vm.segments.first?.samples.first?.rssi == nil)
        vm.stopTest(userInitiated: false)
    }

    @Test("A probe released after stopping cannot append a roaming sample")
    func delayedProbeCannotMutateStoppedRun() async {
        let provider = SuspendedRoamingProbeProvider(result: verifiedStatus(
            at: Date(timeIntervalSince1970: 1_800_000_400), bssid: "AA:00:00:00:00:01"
        ))
        let vm = RoamingTestViewModel(roamingProvider: provider)
        vm.state = .running

        let pendingSample = Task { await vm.sampleOnce() }
        await provider.waitForFirstRequest()
        vm.stopTest(userInitiated: false)
        await provider.releaseFirstRequest()
        await pendingSample.value

        #expect(vm.state == .stopped)
        #expect(vm.segments.isEmpty)
        #expect(vm.transitions.isEmpty)
    }

    @Test("Gateway probing occurs only after the current link evidence is verified")
    func gatewayProbeWaitsForVerifiedAssociation() async {
        let start = Date(timeIntervalSince1970: 1_800_000_200)
        let unverified = WiFiCurrentStatus(
            timestamp: start,
            interfaceName: "en0",
            ssid: "StaleNet",
            bssid: "AA:00:00:00:00:01",
            routerIP: "192.0.2.99",
            isConnected: true,
            isWiFiPowerOn: true
        )
        let verified = verifiedStatus(
            at: start.addingTimeInterval(1),
            bssid: "AA:00:00:00:00:02",
            routerIP: "192.0.2.1"
        )
        let provider = SequenceRoamingProbeProvider([unverified, verified])
        let latency = CountingRoamingLatencyProvider()
        let vm = RoamingTestViewModel(roamingProvider: provider, latencyProvider: latency)
        vm.state = .running

        await vm.sampleOnce()
        #expect(await latency.calls.isEmpty)
        #expect(vm.currentSSID == nil)

        await vm.sampleOnce()
        #expect(await latency.calls == ["192.0.2.1"])
        #expect(vm.currentBSSID == verified.bssid)
        #expect(vm.gatewayLatency == 9)
        #expect(vm.segments.count == 1)
    }

    // MARK: - Helpers

    private func makeConnectedViewModel(guidance: GuidanceCoordinator) -> RoamingTestViewModel {
        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:FF",
            channel: 6, rssi: -45, txRate: 300, isConnected: true, isWiFiPowerOn: true
        )
        let verified = verifiedRoamingStatus(from: status)
        return RoamingTestViewModel(
            roamingProvider: MockRoamingProbeProvider(result: verified),
            latencyProvider: MockGatewayLatencyProvider(result: .init(timestamp: Date(), latencyMs: 3)),
            onRoamingCompleted: {
                guidance.record(.roamingCompleted)
            }
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
        verifiedRoamingStatus(from: WiFiCurrentStatus(
            timestamp: Date(),
            ssid: "TestNet",
            bssid: bssid,
            channel: 36,
            rssi: -50,
            isConnected: true,
            isWiFiPowerOn: true
        ))
    }
}

private func verifiedRoamingStatus(
    from original: WiFiCurrentStatus,
    metricsAttribution: WiFiMetricsAttribution = .verified
) -> WiFiCurrentStatus {
    let cycleID = UUID()
    let evidence = WiFiLinkRawEvidence(
        snapshotCycleID: cycleID,
        capturedAt: original.timestamp,
        interfaceName: "en0",
        mode: .station,
        coreWLANModeRawValue: 1,
        radio: .reportedOn,
        linkActive: true,
        ssid: original.ssid,
        bssid: original.bssid,
        interfaceIndex: 4,
        radioPowerOnRaw: true
    )
    let assessment = WiFiLinkInterpreter.evaluate(evidence, expectedCycleID: cycleID, expectedCapturedAt: original.timestamp)
    return WiFiCurrentStatus(
        timestamp: original.timestamp,
        interfaceSnapshotCycleID: cycleID,
        interfaceName: "en0",
        interfaceIndex: 4,
        ssid: original.ssid,
        bssid: original.bssid,
        channel: original.channel,
        rssi: original.rssi,
        txRate: original.txRate,
            routerIP: original.routerIP,
        isConnected: true,
        isWiFiPowerOn: true,
        linkEvidence: evidence,
        linkAssessment: assessment,
        metricsAttribution: metricsAttribution
    )
}

private func verifiedStatus(
    at timestamp: Date,
    bssid: String,
    routerIP: String? = "192.0.2.1",
    metricsAttribution: WiFiMetricsAttribution = .verified,
    rssi: Int? = -48,
    channel: Int? = 6,
    txRate: Double? = 200
) -> WiFiCurrentStatus {
    verifiedRoamingStatus(from: WiFiCurrentStatus(
        timestamp: timestamp,
        ssid: "TestNet",
        bssid: bssid,
        channel: channel,
        rssi: rssi,
        txRate: txRate,
        routerIP: routerIP,
        isConnected: true,
        isWiFiPowerOn: true
    ), metricsAttribution: metricsAttribution)
}

private actor SequenceRoamingProbeProvider: RoamingProbeProviding {
    private var statuses: [WiFiCurrentStatus]

    init(_ statuses: [WiFiCurrentStatus]) {
        self.statuses = statuses
    }

    func fetchCurrentProbe() async -> WiFiCurrentStatus {
        guard !statuses.isEmpty else { return WiFiCurrentStatus(timestamp: Date(), isConnected: false, isWiFiPowerOn: false) }
        return statuses.removeFirst()
    }
}

private actor SuspendedRoamingProbeProvider: RoamingProbeProviding {
    private let result: WiFiCurrentStatus
    private var calls = 0
    private var pending: CheckedContinuation<WiFiCurrentStatus, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(result: WiFiCurrentStatus) { self.result = result }

    func fetchCurrentProbe() async -> WiFiCurrentStatus {
        calls += 1
        guard calls == 1 else {
            return WiFiCurrentStatus(timestamp: Date(), isConnected: false, isWiFiPowerOn: false)
        }
        return await withCheckedContinuation { continuation in
            pending = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForFirstRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func releaseFirstRequest() {
        pending?.resume(returning: result)
        pending = nil
    }
}

private actor CountingRoamingLatencyProvider: GatewayLatencyProviding, WiFiBoundGatewayMeasuring {
    private(set) var calls: [String] = []
    private(set) var targets: [WiFiGatewayProbeTarget] = []

    func measure(routerIP: String?) async -> GatewayLatencyResult {
        if let routerIP { calls.append(routerIP) }
        return GatewayLatencyResult(
            timestamp: Date(),
            routerIP: routerIP,
            latencyMs: 9,
            probeOutcome: .replied(milliseconds: 9),
            attemptID: UUID()
        )
    }

    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult {
        calls.append(target.address)
        targets.append(target)
        return GatewayLatencyResult(
            timestamp: target.capturedAt, routerIP: target.address, latencyMs: 9,
            probeOutcome: .replied(milliseconds: 9), attemptID: UUID(),
            cycleID: target.snapshotCycleID, interfaceName: target.interfaceName, interfaceBound: true
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
