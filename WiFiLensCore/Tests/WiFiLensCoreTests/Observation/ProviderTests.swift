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

    @Test("empty interface snapshot preserves disconnected status provenance")
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
        #expect(status.error == .noWiFiConnection)
        #expect(status.interfaceSnapshotCycleID == cycleID)
        #expect(status.timestamp == capturedAt)
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
