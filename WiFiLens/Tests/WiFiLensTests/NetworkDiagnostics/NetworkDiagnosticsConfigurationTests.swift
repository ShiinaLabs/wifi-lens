import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("all app configurations use the same local-network privacy copy")
    func localNetworkUsageDescriptionIsUnifiedAcrossAppConfigurations() throws {
        let descriptions = try appLocalNetworkUsageDescriptions()
        let expectedDescription = "WiFi Lens uses local networking when you enable its MCP server and when Network Self-Check tests reachability of your configured network proxy. These checks do not collect or transmit your Wi-Fi scan data."

        #expect(descriptions.count == 4)
        #expect(Set(descriptions.map(\.baseConfiguration)) == ["OSS.xcconfig", "PRO.xcconfig"])
        #expect(descriptions.filter { $0.baseConfiguration == "OSS.xcconfig" }.count == 2)
        #expect(descriptions.filter { $0.baseConfiguration == "PRO.xcconfig" }.count == 2)
        #expect(Set(descriptions.map(\.value)) == [expectedDescription])
        #expect(descriptions.allSatisfy { $0.value.contains("MCP server") })
        #expect(descriptions.allSatisfy { $0.value.contains("Network Self-Check") })
    }

    @Test("production checks run path DNS HTTPS and proxy in dependency order")
    @MainActor
    func productionCheckOrder() {
        #expect(NetworkDiagnosticsViewModel().checkIDs == [.path, .gatewayReachability, .dns, .internet, .proxy, .ipv6])
        #expect(NetworkDiagnosticCheckID.allCases == [.path, .gatewayReachability, .dns, .internet, .ipv6, .proxy])
        #expect(NetworkDiagnosticCheckID.path != .internet)
        #expect(Set(NetworkDiagnosticCheckID.allCases).count == 6)
    }
}

