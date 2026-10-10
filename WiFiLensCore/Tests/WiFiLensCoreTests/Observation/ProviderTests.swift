import Foundation
import Testing
@testable import WiFiLensCore

@Suite("Observation Providers")
struct ProviderTests {
    @Test("network identity never infers Wi-Fi interface classification")
    func ssidDoesNotClassifyInterface() {
        let staleIdentity = NetworkInterfaceInfo(interfaceName: "en0", ssid: "Old network")
        let identifiedWiFiInterface = NetworkInterfaceInfo(interfaceName: "en0", isWiFiInterface: true)

        #expect(!staleIdentity.isWiFiInterface)
        #expect(identifiedWiFiInterface.isWiFiInterface)
    }

    @Test("CoreWLAN channel band mapping preserves overlapping 6 GHz channels")
    func coreWLANBandMapping() {
        #expect(NetworkInfoService.channelBand(coreWLANRawValue: 1) == .band24GHz)
        #expect(NetworkInfoService.channelBand(coreWLANRawValue: 2) == .band5GHz)
        #expect(NetworkInfoService.channelBand(coreWLANRawValue: 3) == .band6GHz)
        #expect(NetworkInfoService.channelBand(coreWLANRawValue: 99) == nil)
    }

    @Test("WiFiCurrentConnectionProvider copies the interface band without channel inference")
    func currentConnectionProviderCopiesBand() {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_200)
        let interface = NetworkInterfaceInfo(
            interfaceName: "en0",
            hardwareMAC: "00:11:22:33:44:55",
            ipv4Addresses: ["192.0.2.2"],
            subnetMasks: ["255.255.255.0"],
            router: "192.0.2.1",
            dnsServers: ["192.0.2.1"],
            ssid: "Six",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 5,
            band: .band6GHz,
            rssi: -50,
            txRate: 1200,
            phyMode: "ax",
            security: "WPA3"
        )

        let snapshot = NetworkInterfaceSnapshot(
            cycleID: UUID(),
            capturedAt: timestamp,
            interfaces: [interface]
        )
        let status = WiFiCurrentConnectionProvider.makeStatus(
            from: interface,
            snapshot: snapshot
        )

        #expect(status.channel == 5)
        #expect(status.band == .band6GHz)
    }

    @Test("WiFiCurrentConnectionProvider deterministically projects a connected snapshot")
    func currentConnectionProvider() async {
        let provider = WiFiCurrentConnectionProvider()
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_300)
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: capturedAt,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn,
            linkActive: true
        )
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [NetworkInterfaceInfo(
                interfaceName: "en0",
                hardwareMAC: nil,
                isWiFiInterface: true,
                wifiLinkEvidence: evidence,
                ipv4Addresses: ["192.0.2.2"],
                subnetMasks: ["255.255.255.0"],
                router: "192.0.2.1",
                dnsServers: ["192.0.2.1"],
                ssid: "Deterministic",
                bssid: "AA:BB:CC:DD:EE:FF",
                channel: 36,
                band: .band5GHz,
                rssi: -48,
                txRate: 866,
                phyMode: "ax",
                security: "WPA3"
            )]
        )
        let status = await provider.fetchCurrentStatus(from: snapshot)

        #expect(status.isConnected)
        #expect(status.ssid == "Deterministic")
        #expect(status.bssid == "AA:BB:CC:DD:EE:FF")
    }

    @Test("SSID visibility is not required when current station evidence is available")
    func stationEvidenceSurvivesMissingSSID() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_350)
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: capturedAt,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn,
            linkActive: true
        )
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [NetworkInterfaceInfo(
                interfaceName: "en0",
                interfaceIndex: 4,
                isWiFiInterface: true,
                wifiLinkEvidence: evidence,
                router: "192.0.2.1"
            )]
        )

        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)

        #expect(status.ssid == nil)
        #expect(status.linkAssessment?.state == .associated)
        #expect(status.linkEvidence?.snapshotCycleID == cycleID)
        #expect(status.isConnected)
    }

    @Test("RoamingProbeProvider does not treat a readable SSID as association evidence")
    func roamingProbeUsesVerifiedLinkEvidence() async {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_355)
        let source = FixedNetworkInterfaceSnapshotSource { cycleID in
            let evidence = WiFiLinkRawEvidence(
                snapshotCycleID: cycleID,
                capturedAt: capturedAt,
                interfaceName: "en0",
                mode: .noneOrReadFailure,
                radio: .reportedOn,
                linkActive: false
            )
            return NetworkInterfaceSnapshot(
                cycleID: cycleID,
                capturedAt: capturedAt,
                interfaces: [NetworkInterfaceInfo(
                    interfaceName: "en0",
                    isWiFiInterface: true,
                    wifiLinkEvidence: evidence,
                    ssid: "Visible but unverified"
                )]
            )
        }

        let status = await RoamingProbeProvider(snapshotSource: source).fetchCurrentProbe()

        #expect(status.ssid == "Visible but unverified")
        #expect(status.linkAssessment?.state == .unknown)
        #expect(!status.isConnected)
    }

    @Test("RoamingProbeProvider accepts station evidence when SSID is unavailable")
    func roamingProbeDoesNotRequireSSID() async {
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_356)
        let source = FixedNetworkInterfaceSnapshotSource { cycleID in
            let evidence = WiFiLinkRawEvidence(
                snapshotCycleID: cycleID,
                capturedAt: capturedAt,
                interfaceName: "en0",
                mode: .station,
                radio: .reportedOn,
                linkActive: true
            )
            return NetworkInterfaceSnapshot(
                cycleID: cycleID,
                capturedAt: capturedAt,
                interfaces: [NetworkInterfaceInfo(
                    interfaceName: "en0",
                    isWiFiInterface: true,
                    wifiLinkEvidence: evidence
                )]
            )
        }

        let status = await RoamingProbeProvider(snapshotSource: source).fetchCurrentProbe()

        #expect(status.ssid == nil)
        #expect(status.linkAssessment?.state == .associated)
        #expect(status.isConnected)
    }

    @Test("ambiguous mode and radio values remain unknown")
    func ambiguousLinkEvidenceStaysUnknown() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_360)
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: capturedAt,
            interfaceName: "en0",
            mode: .noneOrReadFailure,
            radio: .reportedOffOrReadFailure
        )
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [NetworkInterfaceInfo(
                interfaceName: "en0",
                isWiFiInterface: true,
                wifiLinkEvidence: evidence
            )]
        )

        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)

        #expect(status.linkAssessment?.state == .unknown)
        #expect(status.linkAssessment?.reason == .modeUnavailable)
    }

    @Test("contradictory link-active evidence prevents a positive association")
    func inactiveLinkIsNotAssociated() {
        let cycleID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_365)
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: timestamp,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn,
            linkActive: false
        )

        let assessment = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: cycleID,
            expectedCapturedAt: timestamp
        )

        #expect(assessment.state == .unknown)
        #expect(assessment.reason == .conflictingLinkEvidence)
    }

    @Test("station mode and radio state without affirmative link evidence remain unknown")
    func missingLinkActiveIsNotAssociated() {
        let cycleID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_368)
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: timestamp,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn
        )

        let assessment = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: cycleID,
            expectedCapturedAt: timestamp
        )

        #expect(assessment.state == .unknown)
        #expect(assessment.reason == .linkStateUnavailable)
    }

    @Test("failed interface enumeration is not represented as a verified disconnect")
    func failedEnumerationStaysUnknown() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_370)
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [],
            interfaceEnumerationSucceeded: false
        )

        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)

        #expect(status.linkAssessment?.state == .unknown)
        #expect(status.linkAssessment?.reason == .interfaceEnumerationFailed)
    }

    @Test("empty interface snapshot preserves provenance without claiming link state")
    func emptyInterfaceSnapshotPreservesDisconnectedProvenance() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_752_000_456)
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: []
        )

        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)

        #expect(status.isConnected == false)
        #expect(status.linkAssessment?.state == .unknown)
        #expect(status.error == .noWiFiConnection)
        #expect(status.interfaceSnapshotCycleID == cycleID)
        #expect(status.timestamp == capturedAt)
    }

    @Test("ping process outcomes require a valid exit-specific interpretation")
    func pingProcessOutcomeMapping() {
        let noReplyOutput = "1 packets transmitted, 0 packets received, 100.0% packet loss"
        #expect(GatewayPinger.interpret(.exited(
            status: 0,
            output: "64 bytes from 192.0.2.1: icmp_seq=0 ttl=64 time=12.5 ms"
        )) == .replied(milliseconds: 12.5))
        #expect(GatewayPinger.interpret(.exited(status: 0, output: "unparseable")) == .executionFailed)
        #expect(GatewayPinger.interpret(.exited(status: 0, output: "64 bytes time=-1 ms")) == .executionFailed)
        #expect(GatewayPinger.interpret(.exited(status: 0, output: "64 bytes time=nan ms")) == .executionFailed)
        #expect(GatewayPinger.interpret(.exited(status: 0, output: "64 bytes time=inf ms")) == .executionFailed)

        #expect(GatewayPinger.interpret(.exited(status: 2, output: noReplyOutput)) == .noReply)
        #expect(GatewayPinger.interpret(.exited(status: 2, output: "")) == .executionFailed)
        #expect(GatewayPinger.interpret(.exited(
            status: 2,
            output: "0 packets received, 100.0% packet loss"
        )) == .executionFailed)
        for localError in [
            "sendto: No buffer space available",
            "sendmsg: Network is unreachable",
            "No route to host",
            "network is unreachable",
            "permission denied",
            "Operation not permitted",
            "can't assign requested address",
            "cannot assign requested address",
            "message too long",
            "invalid argument",
        ] {
            #expect(GatewayPinger.interpret(.exited(
                status: 2,
                output: localError + "\n" + noReplyOutput
            )) == .executionFailed)
        }
        for status: Int32 in [1, 64, 68] {
            #expect(GatewayPinger.interpret(.exited(
                status: status,
                output: noReplyOutput
            )) == .executionFailed)
        }

        #expect(GatewayPinger.interpret(.failedToLaunch) == .executionFailed)
        #expect(GatewayPinger.interpret(.terminatedBySignal(15)) == .executionFailed)
        #expect(GatewayPinger.interpret(.outputReadFailed) == .executionFailed)
        #expect(GatewayPinger.interpret(.cancelled) == .cancelled)
        #expect(GatewayPinger.interpret(.localTimeout) == .localTimeout)
    }

    @Test("a cancelled task does not launch its ping process")
    func cancelledBeforeProbeDoesNotLaunchRunner() async {
        let runner = ControlledGatewayPingProcessRunner()
        let pinger = GatewayPinger(processRunner: runner)
        let gate = AsyncInvocationGate()
        let attemptID = UUID()

        let task = Task {
            await gate.wait()
            return await pinger.probe(host: "gateway.example", attemptID: attemptID)
        }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        #expect(await task.value == .cancelled)
        #expect(await runner.invocationIDs.isEmpty)
    }

    @Test("cancelling one concurrent ping leaves the other attempt independent")
    func concurrentProbeCancellationIsAttemptScoped() async {
        let runner = ControlledGatewayPingProcessRunner()
        let pinger = GatewayPinger(processRunner: runner)
        let firstID = UUID()
        let secondID = UUID()

        let first = Task { await pinger.probe(host: "first.example", attemptID: firstID) }
        await runner.waitUntilInvocationCount(1)
        let second = Task { await pinger.probe(host: "second.example", attemptID: secondID) }
        await runner.waitUntilInvocationCount(2)

        first.cancel()
        #expect(await first.value == .cancelled)
        #expect(await runner.cancelledInvocationIDs == [firstID])

        await runner.complete(secondID, with: .exited(
            status: 0,
            output: "64 bytes from 192.0.2.2: icmp_seq=0 ttl=64 time=4.5 ms"
        ))
        #expect(await second.value == .replied(milliseconds: 4.5))
        #expect(await runner.cancelledInvocationIDs == [firstID])
    }

    @Test("normal ping completion racing cancellation is delivered once")
    func normalCompletionCancellationRaceCompletesOnce() async {
        let runner = ControlledGatewayPingProcessRunner()
        let pinger = GatewayPinger(processRunner: runner)
        let attemptID = UUID()
        let task = Task { await pinger.probe(host: "gateway.example", attemptID: attemptID) }
        await runner.waitUntilInvocationCount(1)

        let finish = Task {
            await runner.complete(attemptID, with: .exited(
                status: 2,
                output: "1 packets transmitted, 0 packets received, 100.0% packet loss"
            ))
        }
        task.cancel()
        await finish.value
        let result = await task.value

        #expect(result == .cancelled || result == .noReply)
        #expect(await runner.invocationIDs == [attemptID])
    }

    @Test("GatewayLatencyProvider returns result with routerIP")
    func gatewayLatencyProvider() async {
        let provider = GatewayLatencyProvider()
        let result = await provider.measure(routerIP: nil)
        #expect(result.error == .missingRouterIP)

        let result2 = await provider.measure(routerIP: "127.0.0.1")
        #expect(result2.latencyMs != nil || result2.error != nil)
    }

    @Test("GatewayLatencyProvider returns gatewayPingFailed when ping returns nil")
    func gatewayLatencyProviderPingFailure() async {
        let provider = GatewayLatencyProvider(pinger: TestMockGatewayPinger(result: nil))
        let result = await provider.measure(routerIP: "192.0.2.1")

        #expect(result.latencyMs == nil)
        #expect(result.error == .gatewayPingFailed("192.0.2.1"))
    }
}

private struct FixedNetworkInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    let makeSnapshot: @Sendable (UUID) -> NetworkInterfaceSnapshot

    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        makeSnapshot(cycleID)
    }
}

private actor AsyncInvocationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didEnter = false

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            didEnter = true
        }
    }

    func waitUntilEntered() async {
        while !didEnter { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ControlledGatewayPingProcessRunner: GatewayPingProcessRunning {
    private(set) var invocationIDs: [UUID] = []
    private(set) var cancelledInvocationIDs: [UUID] = []
    private var continuations: [UUID: CheckedContinuation<GatewayPingProcessOutcome, Never>] = [:]

    func run(executablePath: String, arguments: [String], attemptID: UUID) async -> GatewayPingProcessOutcome {
        await withCheckedContinuation { continuation in
            invocationIDs.append(attemptID)
            continuations[attemptID] = continuation
        }
    }

    func cancel(attemptID: UUID) {
        cancelledInvocationIDs.append(attemptID)
        continuations.removeValue(forKey: attemptID)?.resume(returning: .cancelled)
    }

    func waitUntilInvocationCount(_ count: Int) async {
        while invocationIDs.count < count { await Task.yield() }
    }

    func complete(_ attemptID: UUID, with outcome: GatewayPingProcessOutcome) {
        continuations.removeValue(forKey: attemptID)?.resume(returning: outcome)
    }
}
