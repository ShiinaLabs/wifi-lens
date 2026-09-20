import Foundation
import Testing
import MCP
@testable import WiFi_Lens

@Suite struct MCPServerTests {

    private func makeNetwork(
        ssid: String? = "TestNet",
        bssid: String = "aa:bb:cc:dd:ee:ff",
        rssi: Int = -50,
        channelNumber: Int = 6,
        band: ChannelBand = .band24GHz,
        ieData: Data? = nil
    ) -> WiFiNetwork {
        let ch = WiFiChannel(band: band, channelNumber: channelNumber)
        return WiFiNetwork(ssid: ssid, bssid: bssid, rssi: rssi, channel: ch, ieData: ieData)
    }

    private func resultText(from result: CallTool.Result) -> String {
        if case .text(let text, _, _) = result.content.first {
            return text
        }
        return ""
    }

    private func resultJSON(from result: CallTool.Result) -> Any? {
        let text = resultText(from: result)
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - scan_networks

    @Test func scanNetworksReturnsAllNetworks() {
        let net = makeNetwork()
        let result = MCPServer.handleCallTool(name: "scan_networks", arguments: nil, networks: [net])

        let json = resultJSON(from: result) as? [[String: Any]]
        #expect(json?.count == 1)
        #expect(json?.first?["ssid"] as? String == "TestNet")
    }

    @Test func scanNetworksBandFilter() {
        let n24 = makeNetwork(bssid: "aa:bb:cc:dd:ee:01", channelNumber: 6, band: .band24GHz)
        let n5 = makeNetwork(bssid: "aa:bb:cc:dd:ee:02", channelNumber: 36, band: .band5GHz)
        let args: [String: Value] = ["band": .string("5")]
        let result = MCPServer.handleCallTool(name: "scan_networks", arguments: args, networks: [n24, n5])

        let json = resultJSON(from: result) as? [[String: Any]]
        #expect(json?.count == 1)
        #expect(json?.first?["bssid"] as? String == "aa:bb:cc:dd:ee:02")
    }

    @Test func scanNetworksEmptyReturnsEmptyArray() {
        let result = MCPServer.handleCallTool(name: "scan_networks", arguments: nil, networks: [])
        let json = resultJSON(from: result) as? [[String: Any]]
        #expect(json?.isEmpty == true)
    }

    @Test func scanNetworksWidthLabelsDistinguishKnown20FromUnknown() {
        var ht20 = [UInt8](repeating: 0, count: 22)
        ht20[0] = 6
        ht20[1] = 0
        var ht40 = [UInt8](repeating: 0, count: 22)
        ht40[0] = 6
        ht40[1] = 0x05 // STA Channel Width Any + secondary channel above

        let known20 = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:20",
            ieData: Data([61, UInt8(ht20.count)] + ht20)
        )
        let unknown = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:21",
            ieData: Data([61, 1, 6])
        )
        let known40 = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:40",
            ieData: Data([61, UInt8(ht40.count)] + ht40)
        )
        let vht80 = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:80",
            channelNumber: 36,
            band: .band5GHz,
            ieData: Data([192, 5, 1, 42, 0, 0, 0])
        )
        let vht80plus80 = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:88",
            channelNumber: 36,
            band: .band5GHz,
            ieData: Data([192, 5, 3, 42, 58, 0, 0])
        )

        let result = MCPServer.handleCallTool(
            name: "scan_networks",
            arguments: nil,
            networks: [known20, unknown, known40, vht80, vht80plus80]
        )
        let json = resultJSON(from: result) as? [[String: Any]]
        let widths: [String: String] = Dictionary(uniqueKeysWithValues: json?.compactMap { entry in
            guard let bssid = entry["bssid"] as? String,
                  let width = entry["channelWidth"] as? String else { return nil }
            return (bssid, width)
        } ?? [])

        #expect(widths[known20.bssid] == "20")
        #expect(widths[unknown.bssid] == "")
        #expect(widths[known40.bssid] == "40")
        #expect(widths[vht80.bssid] == "80")
        #expect(widths[vht80plus80.bssid] == "80+80")
    }

    // MARK: - get_network_detail

    @Test func getNetworkDetailByBSSID() {
        let net = makeNetwork(bssid: "aa:bb:cc:dd:ee:ff", rssi: -42)
        let args: [String: Value] = ["bssid": .string("aa:bb:cc:dd:ee:ff")]
        let result = MCPServer.handleCallTool(name: "get_network_detail", arguments: args, networks: [net])

        let dict = resultJSON(from: result) as? [String: Any]
        #expect(dict?["bssid"] as? String == "aa:bb:cc:dd:ee:ff")
        #expect(dict?["rssi"] as? Int == -42)
    }

    @Test func getNetworkDetailNotFoundReturnsError() {
        let args: [String: Value] = ["bssid": .string("xx:xx:xx:xx:xx:xx")]
        let result = MCPServer.handleCallTool(name: "get_network_detail", arguments: args, networks: [])

        #expect(result.isError == true)
        #expect(resultText(from: result).contains("not found"))
    }

    @Test func getNetworkDetailMissingBSSIDReturnsError() {
        let result = MCPServer.handleCallTool(name: "get_network_detail", arguments: nil, networks: [])

        #expect(result.isError == true)
        #expect(resultText(from: result).contains("missing"))
    }

    // MARK: - get_channel_occupancy

    @Test func channelOccupancyReturnsGroupedCounts() {
        let nets = [
            makeNetwork(bssid: "aa:bb:cc:dd:ee:01", channelNumber: 1),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:02", channelNumber: 1),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:03", channelNumber: 6),
        ]
        let result = MCPServer.handleCallTool(name: "get_channel_occupancy", arguments: nil, networks: nets)

        let json = resultJSON(from: result) as? [String: [String: Int]]
        #expect(json?["24"]?["1"] == 2)
        #expect(json?["24"]?["6"] == 1)
    }

    // MARK: - Unknown tool

    @Test func unknownToolReturnsError() {
        let result = MCPServer.handleCallTool(name: "nonexistent_tool", arguments: nil, networks: [])
        #expect(result.isError == true)
        #expect(resultText(from: result).contains("Unknown tool"))
    }

    // MARK: - Contract: raw-data-only surface

    @Test func scanNetworksInvalidBandTypeDoesNotFilter() {
        let n24 = makeNetwork(bssid: "aa:bb:cc:dd:ee:01", channelNumber: 6, band: .band24GHz)
        let n5 = makeNetwork(bssid: "aa:bb:cc:dd:ee:02", channelNumber: 36, band: .band5GHz)
        let args: [String: Value] = ["band": .int(5)]
        let result = MCPServer.handleCallTool(
            name: "scan_networks",
            arguments: args,
            networks: [n24, n5]
        )

        let json = resultJSON(from: result) as? [[String: Any]]
        #expect(json?.count == 2)
        let bssids = json?.compactMap { $0["bssid"] as? String }
        #expect(bssids?.contains("aa:bb:cc:dd:ee:01") == true)
        #expect(bssids?.contains("aa:bb:cc:dd:ee:02") == true)
    }

    @Test func channelOccupancyGroupsAllBands() {
        let nets = [
            makeNetwork(bssid: "aa:bb:cc:dd:ee:01", channelNumber: 1, band: .band24GHz),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:02", channelNumber: 36, band: .band5GHz),
            makeNetwork(bssid: "aa:bb:cc:dd:ee:03", channelNumber: 6, band: .band6GHz),
        ]
        let result = MCPServer.handleCallTool(name: "get_channel_occupancy", arguments: nil, networks: nets)

        let json = resultJSON(from: result) as? [String: [String: Int]]
        #expect(json?["24"]?["1"] == 1)
        #expect(json?["5"]?["36"] == 1)
        #expect(json?["6"]?["6"] == 1)
    }

    // MARK: - Snapshot dispatch

    @Test func snapshotDispatchPreservesRawNetworkBehavior() {
        let net = makeNetwork(ssid: "SnapshotNet", bssid: "aa:bb:cc:dd:ee:ff", rssi: -47)
        let snapshot = MCPSnapshot(networks: [net])

        let scanResult = MCPServer.handleCallTool(
            name: "scan_networks",
            arguments: nil,
            snapshot: snapshot
        )
        let missingResult = MCPServer.handleCallTool(
            name: "get_network_detail",
            arguments: ["bssid": .string("aa:bb:cc:dd:ee:00")],
            snapshot: snapshot
        )

        let json = resultJSON(from: scanResult) as? [[String: Any]]
        #expect(json?.first?["ssid"] as? String == "SnapshotNet")
        #expect(missingResult.isError == true)
        #expect(resultText(from: missingResult).contains("network not found"))
    }

    // MARK: - get_scan_metadata

    @Test func metadataToolIsAdvertisedAfterRawTools() {
        #expect(
            MCPServer.toolNamesForTesting == [
                "scan_networks",
                "get_network_detail",
                "get_channel_occupancy",
                "get_scan_metadata",
            ]
        )
    }

    @Test func metadataReturnsFactualRuntimeContext() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let snapshot = MCPSnapshot(
            capturedAt: capturedAt,
            interfaceName: "en0",
            isScanning: true,
            powerState: .poweredOn,
            accessState: .scanning,
            supportedBands: ["24", "5"],
            scanIntervalSeconds: 5
        )

        let result = MCPServer.handleCallTool(
            name: "get_scan_metadata",
            arguments: nil,
            snapshot: snapshot
        )
        let json = resultJSON(from: result) as? [String: Any]

        #expect(result.isError != true)
        #expect(json?["interfaceName"] as? String == "en0")
        #expect(json?["isScanning"] as? Bool == true)
        #expect(json?["powerState"] as? String == "poweredOn")
        #expect(json?["accessState"] as? String == "scanning")
        #expect((json?["supportedBands"] as? [String]) == ["24", "5"])
        #expect(json?["scanIntervalSeconds"] as? Int == 5)
        #expect(json?["capturedAt"] != nil)
    }

    @Test func metadataOmitsUnavailableOptionalContext() {
        let result = MCPServer.handleCallTool(
            name: "get_scan_metadata",
            arguments: nil,
            snapshot: .empty
        )
        let json = resultJSON(from: result) as? [String: Any]

        #expect(result.isError != true)
        #expect(json?.keys.contains("capturedAt") == false)
        #expect(json?.keys.contains("interfaceName") == false)
        #expect(json?.keys.contains("supportedBands") == false)
        #expect(json?.keys.contains("scanIntervalSeconds") == false)
    }

    // MARK: - Setup prompt

    @Test func setupPromptUsesConfiguredPort() {
        let prompt = MCPServer.setupPrompt(port: 28461)

        #expect(prompt.contains("wifi-lens"))
        #expect(prompt.contains("http://127.0.0.1:28461/"))
        #expect(!prompt.contains("19840"))
    }

    @Test func setupPromptIncludesClientFormatsAndSafetyBoundaries() {
        let prompt = MCPServer.setupPrompt(port: 19840)

        #expect(prompt.contains("Streamable HTTP"))
        #expect(prompt.lowercased().contains("read-only"))
        #expect(prompt.contains("127.0.0.1"))
        #expect(prompt.contains("Preserve every other setting"))
        #expect(prompt.contains("Do not expose this server"))
        #expect(prompt.contains("verify that the wifi-lens MCP server"))
        #expect(prompt.contains("Use this client's native configuration format"))
    }
}

@Suite("MCP snapshot projection") @MainActor struct MCPScannerViewModelTests {
    @Test func projectsAuthoritativeRuntimeContextWithoutAnalysis() {
        let viewModel = ScannerViewModel()
        let capturedAt = Date(timeIntervalSince1970: 100)
        let network = WiFiNetwork(
            ssid: "ProjectionNet",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -51,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 36)
        )

        viewModel.scanIntervalSeconds = 5
        viewModel.wifiPowerState = .poweredOn
        viewModel.accessState = .scanning
        viewModel.isScanning = true
        viewModel.interfaceName = "en0"
        viewModel.debugApplyNetworksForTesting(
            [network],
            supportedBands: [.band24GHz, .band5GHz],
            timestamp: capturedAt
        )

        let snapshot = viewModel.makeMCPSnapshot()
        #expect(snapshot.networks.map(\.bssid) == ["aa:bb:cc:dd:ee:ff"])
        #expect(snapshot.capturedAt == capturedAt)
        #expect(snapshot.interfaceName == "en0")
        #expect(snapshot.isScanning == true)
        #expect(snapshot.powerState == .poweredOn)
        #expect(snapshot.accessState == .scanning)
        #expect(snapshot.supportedBands == ["24", "5"])
        #expect(snapshot.scanIntervalSeconds == 5)

        viewModel.wifiPowerState = .poweredOff
        let unavailable = viewModel.makeMCPSnapshot()
        #expect(unavailable.networks.isEmpty)
        #expect(unavailable.capturedAt == nil)
        #expect(unavailable.supportedBands.isEmpty)
        #expect(unavailable.powerState == .poweredOff)
    }
}
