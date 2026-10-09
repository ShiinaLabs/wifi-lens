import Foundation
import Testing
@testable import WiFiLensCore

@Suite("Observation Providers")
struct ProviderTests {
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
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_750_000_300),
            interfaces: [NetworkInterfaceInfo(
                interfaceName: "en0",
                hardwareMAC: nil,
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
        #expect(status.isConnected == false) // Legacy projection only; Pro consumes linkAssessment.
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

    @Test("ping process outcomes distinguish a confirmed non-response from local failures")
    func pingProcessOutcomeMapping() {
        #expect(GatewayPinger.interpret(.exited(
            status: 0,
            output: "64 bytes from 192.0.2.1: icmp_seq=0 ttl=64 time=12.5 ms"
        )) == .replied(milliseconds: 12.5))
        #expect(GatewayPinger.interpret(.exited(
            status: 2,
            output: "1 packets transmitted, 0 packets received, 100.0% packet loss"
        )) == .noReply)
        #expect(GatewayPinger.interpret(.failedToLaunch) == .executionFailed)
        #expect(GatewayPinger.interpret(.terminatedBySignal(15)) == .executionFailed)
        #expect(GatewayPinger.interpret(.outputReadFailed) == .executionFailed)
        #expect(GatewayPinger.interpret(.cancelled) == .cancelled)
        #expect(GatewayPinger.interpret(.localTimeout) == .localTimeout)
        #expect(GatewayPinger.interpret(.exited(status: 0, output: "unparseable")) == .executionFailed)
        #expect(GatewayPinger.interpret(.exited(status: 2, output: "permission denied")) == .executionFailed)
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
