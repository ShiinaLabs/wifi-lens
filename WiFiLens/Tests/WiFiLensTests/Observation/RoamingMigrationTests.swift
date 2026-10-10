import Foundation
import Observation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite("Roaming Migration")
@MainActor
struct RoamingMigrationTests {
    private func connectedStatus(
        ssid: String = "TestNet",
        bssid: String = "AA:BB:CC:DD:EE:FF",
        channel: Int = 36,
        rssi: Int = -50,
        txRate: Double = 130.0,
        phyMode: String? = "802.11ac",
        timestamp: Date = Date(),
        interfaceName: String = "en0"
    ) -> WiFiCurrentStatus {
        let cycleID = UUID()
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: timestamp,
            interfaceName: interfaceName,
            mode: .station,
            coreWLANModeRawValue: 1,
            radio: .reportedOn,
            linkActive: true,
            ssid: ssid,
            bssid: bssid,
            interfaceIndex: 4,
            radioPowerOnRaw: true
        )
        let assessment = WiFiLinkInterpreter.evaluate(evidence, expectedCycleID: cycleID, expectedCapturedAt: timestamp)
        return WiFiCurrentStatus(
            timestamp: timestamp,
            interfaceSnapshotCycleID: cycleID,
            interfaceName: interfaceName,
            interfaceIndex: 4,
            ssid: ssid,
            bssid: bssid,
            channel: channel,
            rssi: rssi,
            txRate: txRate,
            phyMode: phyMode,
            isConnected: true,
            isWiFiPowerOn: true,
            linkEvidence: evidence,
            linkAssessment: assessment
        )
    }

    @Test("checkReadiness uses roaming provider instead of CWWiFiClient")
    func checkReadinessUsesProvider() async {
        let status = connectedStatus()
        let provider = MockRoamingProbeProvider(result: status)
        let vm = RoamingTestViewModel(roamingProvider: provider)
        let state = ObservationWatcher()

        vm.checkReadiness()
        await state.waitUntil { vm.state == .ready }

        #expect(vm.state == .ready)
        #expect(vm.currentSSID == "TestNet")
        #expect(vm.currentBSSID == "AA:BB:CC:DD:EE:FF")
        #expect(vm.currentRSSI == -50)
        #expect(vm.currentChannel == 36)
        #expect(vm.currentTxRate == 130.0)
        #expect(vm.currentPhyMode == "802.11ac")
    }

    @Test("checkReadiness sets error when disconnected")
    func checkReadinessDisconnected() async {
        let status = WiFiCurrentStatus(
            timestamp: Date(),
            isConnected: false,
            isWiFiPowerOn: true
        )
        let provider = MockRoamingProbeProvider(result: status)
        let vm = RoamingTestViewModel(roamingProvider: provider)
        let state = ObservationWatcher()

        vm.checkReadiness()
        await state.waitUntil { vm.errorMessage != nil }

        #expect(vm.state == .idle)
        #expect(vm.errorMessage != nil)
    }

    @Test("startTest fetches initial probe from provider")
    func startTestUsesProvider() async {
        let status = connectedStatus(bssid: "11:22:33:44:55:66")
        let provider = MockRoamingProbeProvider(result: status)
        let vm = RoamingTestViewModel(roamingProvider: provider)
        let state = ObservationWatcher()

        vm.checkReadiness()
        await state.waitUntil { vm.state == .ready }
        #expect(vm.state == .ready)

        vm.startTest()
        await state.waitUntil { vm.state == .running && vm.segments.count == 1 }

        #expect(vm.state == .running)
        #expect(vm.segments.count == 1)
        #expect(vm.segments.first?.bssid == "11:22:33:44:55:66")
        vm.stopTest()
    }

    @Test("Only continuous confirmed same-network probes record an AP transition")
    func roamingRequiresConfirmedContinuousSamples() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let initial = connectedStatus(timestamp: start)
        let vm = RoamingTestViewModel(roamingProvider: MockRoamingProbeProvider(result: initial))
        let state = ObservationWatcher()
        vm.checkReadiness()
        await state.waitUntil { vm.state == .ready }
        vm.startTest()
        await state.waitUntil { vm.state == .running }

        vm.recordProbe(connectedStatus(bssid: "AA:BB:CC:DD:EE:01", timestamp: start.addingTimeInterval(1)))
        #expect(vm.transitions.count == 1)
        #expect(vm.transitions[0].fromBSSID == "AA:BB:CC:DD:EE:FF")
        #expect(vm.transitions[0].toBSSID == "AA:BB:CC:DD:EE:01")

        let unverified = WiFiCurrentStatus(
            timestamp: start.addingTimeInterval(2), ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:02",
            isConnected: true, isWiFiPowerOn: true
        )
        vm.recordProbe(unverified)
        vm.recordProbe(connectedStatus(bssid: "AA:BB:CC:DD:EE:02", timestamp: start.addingTimeInterval(3)))
        vm.recordProbe(connectedStatus(bssid: "AA:BB:CC:DD:EE:03", timestamp: start.addingTimeInterval(4), interfaceName: "en1"))
        vm.recordProbe(connectedStatus(ssid: "OtherNet", bssid: "AA:BB:CC:DD:EE:04", timestamp: start.addingTimeInterval(5)))
        vm.recordProbe(connectedStatus(bssid: "AA:BB:CC:DD:EE:05", timestamp: start.addingTimeInterval(9)))
        #expect(vm.transitions.count == 1)
        vm.stopTest(userInitiated: false)
    }

    @Test("tick uses latency provider for gateway ping")
    func tickUsesLatencyProvider() async {
        let status = connectedStatus()
        let roamingProvider = MockRoamingProbeProvider(result: status)
        let latencyResult = GatewayLatencyResult(
            timestamp: Date(),
            routerIP: "192.168.1.1",
            latencyMs: 12.5
        )
        let latencyProvider = MockGatewayLatencyProvider(result: latencyResult)
        let vm = RoamingTestViewModel(
            roamingProvider: roamingProvider,
            latencyProvider: latencyProvider
        )
        let state = ObservationWatcher()

        vm.checkReadiness()
        await state.waitUntil { vm.state == .ready }
        #expect(vm.state == .ready)

        vm.startTest()
        await state.waitUntil { vm.state == .running }
        #expect(vm.state == .running)
        vm.stopTest()
    }

    @Test("default init creates real providers")
    func defaultInit() {
        let vm = RoamingTestViewModel()
        #expect(vm.state == .idle)
        #expect(vm.canStart == false)
    }
}

@MainActor
private final class ObservationWatcher {
    private var pending: [(@MainActor () -> Bool, CheckedContinuation<Void, Never>)] = []
    private var isTracking = false

    func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        if predicate() { return }
        await withCheckedContinuation { continuation in
            pending.append((predicate, continuation))
            if !isTracking {
                isTracking = true
                track()
            }
        }
    }

    private func track() {
        withObservationTracking {
            for (predicate, _) in pending {
                _ = predicate()
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                var ready: [(@MainActor () -> Bool, CheckedContinuation<Void, Never>)] = []
                self.pending = self.pending.filter { entry in
                    if entry.0() {
                        ready.append(entry)
                        return false
                    }
                    return true
                }
                ready.forEach { $0.1.resume() }
                if !self.pending.isEmpty {
                    self.track()
                } else {
                    self.isTracking = false
                }
            }
        }
    }
}
