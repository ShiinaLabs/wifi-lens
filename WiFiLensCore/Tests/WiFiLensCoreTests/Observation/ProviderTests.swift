import Foundation
import Testing
import SwiftFTR

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
            metricsAttribution: .verified,
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

        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
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

    @Test("Unverified detail metrics are removed without downgrading link association")
    func unverifiedMetricsAreSanitizedIndependently() {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_201)
        let cycleID = UUID()
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID, capturedAt: timestamp, interfaceName: "en0",
            mode: .station, radio: .reportedOn, linkActive: true,
            ssid: "Lab", bssid: "AP-1", interfaceIndex: 4
        )
        let interface = NetworkInterfaceInfo(
            interfaceName: "en0", interfaceIndex: 4, isWiFiInterface: true,
            wifiLinkEvidence: evidence, metricsAttribution: .inconsistent,
            ssid: "Lab", bssid: "AP-1", channel: 36, band: .band5GHz,
            rssi: -42, txRate: 600, phyMode: "ax", security: "WPA3"
        )
        let status = WiFiCurrentConnectionProvider.makeStatus(
            from: interface,
            snapshot: WiFiLensCore.NetworkInterfaceSnapshot(cycleID: cycleID, capturedAt: timestamp, interfaces: [interface])
        )

        #expect(WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated)
        #expect(status.metricsAttribution == .inconsistent)
        #expect(status.channel == nil)
        #expect(status.band == nil)
        #expect(status.rssi == nil)
        #expect(status.txRate == nil)
        #expect(status.phyMode == nil)
        #expect(status.security == nil)
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
            linkActive: true,
            ssid: "Deterministic",
            bssid: "AA:BB:CC:DD:EE:FF"
        )
        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [
                NetworkInterfaceInfo(
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
                )
            ]
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
        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [
                NetworkInterfaceInfo(
                    interfaceName: "en0",
                    interfaceIndex: 4,
                    isWiFiInterface: true,
                    wifiLinkEvidence: evidence,
                    router: "192.0.2.1"
                )
            ]
        )

        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)

        #expect(status.ssid == nil)
        #expect(status.linkAssessment?.state == .associated)
        #expect(status.linkEvidence?.snapshotCycleID == cycleID)
        #expect(status.isConnected)
    }

    @Test("status generation rejects identity that changed during the interface snapshot")
    func statusGenerationRejectsConflictingIdentity() {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_360)
        let cycleID = UUID()
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: timestamp,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn,
            linkActive: true,
            ssid: "Network A",
            bssid: "AA:BB:CC:DD:EE:01",
            interfaceIndex: 4
        )
        let interface = NetworkInterfaceInfo(
            interfaceName: "en0",
            interfaceIndex: 4,
            isWiFiInterface: true,
            wifiLinkEvidence: evidence,
            ssid: "Network B",
            bssid: "AA:BB:CC:DD:EE:02"
        )
        let status = WiFiCurrentConnectionProvider.makeStatus(
            from: interface,
            snapshot: WiFiLensCore.NetworkInterfaceSnapshot(cycleID: cycleID, capturedAt: timestamp, interfaces: [interface])
        )

        #expect(status.linkAssessment?.state == .unknown)
        #expect(status.linkAssessment?.reason == .conflictingLinkEvidence)
        #expect(!status.isConnected)
        #expect(WiFiLinkEvidenceValidator.assessment(for: status) == nil)
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
            return WiFiLensCore.NetworkInterfaceSnapshot(
                cycleID: cycleID,
                capturedAt: capturedAt,
                interfaces: [
                    NetworkInterfaceInfo(
                        interfaceName: "en0",
                        isWiFiInterface: true,
                        wifiLinkEvidence: evidence,
                        ssid: "Visible but unverified"
                    )
                ]
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
            return WiFiLensCore.NetworkInterfaceSnapshot(
                cycleID: cycleID,
                capturedAt: capturedAt,
                interfaces: [
                    NetworkInterfaceInfo(
                        interfaceName: "en0",
                        isWiFiInterface: true,
                        wifiLinkEvidence: evidence
                    )
                ]
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
        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [
                NetworkInterfaceInfo(
                    interfaceName: "en0",
                    isWiFiInterface: true,
                    wifiLinkEvidence: evidence
                )
            ]
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
        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
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
        let snapshot = WiFiLensCore.NetworkInterfaceSnapshot(
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

    @Test("SwiftFTR ping results map to gateway probe outcomes")
    func swiftFTRResultMapping() async {
        let replying = GatewayPinger { _, _ in pingResult(rtt: 0.0125) }
        #expect(await replying.probe(host: "192.0.2.1", attemptID: UUID()) == .replied(milliseconds: 12.5))

        let unanswered = GatewayPinger { _, _ in pingResult(rtt: nil) }
        #expect(await unanswered.probe(host: "192.0.2.1", attemptID: UUID()) == .noReply)

        let failed = GatewayPinger { _, _ in throw TestPingError.failed }
        #expect(await failed.probe(host: "192.0.2.1", attemptID: UUID()) == .executionFailed)
    }

    @Test("host probes use one packet without interface binding")
    func hostProbeUsesSingleUnboundPacket() async {
        let recorder = GatewayPingRequestRecorder()
        let pinger = GatewayPinger { host, config in
            await recorder.record(host: host, config: config)
            return pingResult(rtt: 0.0045)
        }

        #expect(await pinger.probe(host: "192.0.2.1", attemptID: UUID()) == .replied(milliseconds: 4.5))
        let request = await recorder.requests.first
        #expect(request?.host == "192.0.2.1")
        #expect(request?.config.count == 1)
        #expect(request?.config.interval == 0)
        #expect(request?.config.interface == nil)
    }

    @Test("gateway probes bind by interface name only when its index still matches")
    func gatewayProbeBindsMatchingInterface() async {
        let recorder = GatewayPingRequestRecorder()
        let pinger = GatewayPinger(
            performPing: { host, config in
                await recorder.record(host: host, config: config)
                return pingResult(rtt: 0.0045)
            },
            interfaceIndex: { _ in 4 }
        )
        let target = DiagnosticGatewayTarget(interfaceName: "en0", interfaceIndex: 4, address: "192.0.2.1")

        #expect(await pinger.probe(target: target, attemptID: UUID()) == .replied(milliseconds: 4.5))
        #expect(await recorder.requests.first?.config.interface == "en0")

        let mismatched = GatewayPinger(
            performPing: { _, _ in
                Issue.record("A stale interface index must not start a ping")
                return pingResult(rtt: 0.0045)
            },
            interfaceIndex: { _ in 5 }
        )
        #expect(await mismatched.probe(target: target, attemptID: UUID()) == .executionFailed)
    }

    @Test("cancelling one concurrent probe leaves another attempt independent")
    func concurrentProbeCancellationIsAttemptScoped() async {
        let pinger = GatewayPinger { host, _ in
            if host == "slow.example" { try await Task.sleep(for: .seconds(60)) }
            return pingResult(rtt: 0.0045)
        }
        let first = Task { await pinger.probe(host: "slow.example", attemptID: UUID()) }
        let second = Task { await pinger.probe(host: "fast.example", attemptID: UUID()) }

        first.cancel()
        #expect(await first.value == .cancelled)
        #expect(await second.value == .replied(milliseconds: 4.5))
    }

    @Test("ping has an overall local timeout")
    func pingHasOverallLocalTimeout() async {
        let pinger = GatewayPinger { _, _ in
            try await Task.sleep(for: .seconds(60))
            return pingResult(rtt: 0.0045)
        }

        #expect(await pinger.probe(host: "slow.example", attemptID: UUID()) == .localTimeout)
    }

    private func pingResult(rtt: TimeInterval?) -> PingResult {
        PingResult(
            target: "192.0.2.1",
            resolvedIP: "192.0.2.1",
            responses: [PingResponse(sequence: 1, rtt: rtt, ttl: nil, timestamp: Date())],
            statistics: PingStatistics(
                sent: 1,
                received: rtt == nil ? 0 : 1,
                packetLoss: rtt == nil ? 1 : 0,
                minRTT: rtt,
                avgRTT: rtt,
                maxRTT: rtt,
                jitter: nil
            )
        )
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
    let makeSnapshot: @Sendable (UUID) -> WiFiLensCore.NetworkInterfaceSnapshot

    func capture(cycleID: UUID) async -> WiFiLensCore.NetworkInterfaceSnapshot {
        makeSnapshot(cycleID)
    }
}

private enum TestPingError: Error {
    case failed
}

private actor GatewayPingRequestRecorder {
    struct Request {
        let host: String
        let config: PingConfig
    }

    private(set) var requests: [Request] = []

    func record(host: String, config: PingConfig) {
        requests.append(Request(host: host, config: config))
    }
}
