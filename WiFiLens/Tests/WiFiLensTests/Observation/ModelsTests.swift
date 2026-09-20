import Foundation
import Testing
@testable import WiFi_Lens

@Suite("Observation Models")
struct ModelsTests {
    @Test("WiFiNetworkObservation uses BSSID-based ID when available")
    func bssidBasedID() {
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 20)
        let obs = WiFiNetworkObservation(ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:FF", rssi: -50, channel: ch)
        #expect(obs.id == "AA:BB:CC:DD:EE:FF-36-2")
    }

    @Test("WiFiNetworkObservation uses local fallback ID when BSSID is unknown")
    func localFallbackID() {
        let ch = WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 20)
        let caps = WiFiNetworkCapabilities(phyMode: "ac", channelWidth: 80, supports80211k: false, supports80211r: false, supports80211v: false, supportsWPA3: true, countryCode: nil, isHiddenSSID: false, mcs: nil, nss: nil, security: "WPA2")
        let obs = WiFiNetworkObservation(ssid: "TestNet", bssid: "unknown", rssi: -60, channel: ch, capabilities: caps)
        #expect(obs.id.hasPrefix("local-"))
        #expect(!obs.id.contains("-60")) // RSSI must not be in ID
    }

    @Test("WiFiNetworkCapabilities empty static")
    func emptyCapabilities() {
        let empty = WiFiNetworkCapabilities.empty
        #expect(empty.phyMode == "")
        #expect(empty.channelWidth == 20)
        #expect(empty.supports80211k == false)
    }

    @Test("WiFiObservation defaults")
    func observationDefaults() {
        let obs = WiFiObservation()
        #expect(obs.currentStatus == nil)
        #expect(obs.errors.isEmpty)
    }

    @Test("DiagnosticResult unknown static")
    func unknownDiagnostic() {
        let diag = DiagnosticResult.unknown
        #expect(diag.severity == .ok)
    }

    @Test("WiFiQualityLevel display names")
    func qualityLevelDisplay() {
        // Locale-independent anti-fallback guards: displayName must resolve to a
        // real catalog value, not the raw key (regression guard for missing
        // localizations; the test host runs under the developer's locale).
        #expect(WiFiQualityLevel.good.displayName != "observation.quality.good")
        #expect(WiFiQualityLevel.poor.displayName != "observation.quality.poor")
        #expect(!WiFiQualityLevel.good.displayName.isEmpty)
        #expect(!WiFiQualityLevel.poor.displayName.isEmpty)
    }
}

@Suite("NetworkObservationAdapter")
struct AdapterTests {
    @Test("Adapt WiFiNetwork to WiFiNetworkObservation preserves fields")
    func adaptPreservesFields() {
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80)
        let nw = WiFiNetwork(ssid: "TestNet", bssid: "AA:BB:CC:DD:EE:FF", rssi: -55, channel: ch)
        let obs = NetworkObservationAdapter.adapt(nw)
        #expect(obs.ssid == "TestNet")
        #expect(obs.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(obs.rssi == -55)
        #expect(obs.channel.channelNumber == 36)
        #expect(obs.rawIEData == nil)
    }

    @Test("Adapt marks current network by BSSID match")
    func adaptMarksCurrent() {
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 20)
        let nw = WiFiNetwork(ssid: "Net", bssid: "AA:BB:CC:DD:EE:FF", rssi: -50, channel: ch)
        let obs = NetworkObservationAdapter.adapt(nw, currentBSSID: "AA:BB:CC:DD:EE:FF")
        #expect(obs.isCurrentNetwork == true)
    }

    @Test("AdaptAll converts array")
    func adaptAllArray() {
        let ch = WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 20)
        let networks = [
            WiFiNetwork(ssid: "A", bssid: "11:22:33:44:55:66", rssi: -60, channel: ch),
            WiFiNetwork(ssid: "B", bssid: "AA:BB:CC:DD:EE:FF", rssi: -70, channel: ch)
        ]
        let observations = NetworkObservationAdapter.adaptAll(networks)
        #expect(observations.count == 2)
        #expect(observations[0].ssid == "A")
        #expect(observations[1].ssid == "B")
    }

    @Test("Adapt uses channelWidthMHz fallback when IE lacks width support")
    func adaptWidthFallback() {
        // HT Capabilities (tag 45): 2 bytes, bit 1 clear = no 40MHz
        // VHT Operation (tag 192): chWidth 0 = 20/40 only
        let ieData = Data([45, 2, 0, 0, 192, 1, 0])
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80)
        let nw = WiFiNetwork(ssid: "WideNet", bssid: "AA:BB:CC:DD:EE:FF", rssi: -50, channel: ch, ieData: ieData)
        let obs = NetworkObservationAdapter.adapt(nw)
        #expect(obs.capabilities.channelWidth == 80)
        #expect(obs.capabilities.phyMode == "n")
    }

    @Test("Adapt reports 20 MHz when HT capabilities allow 40 MHz but operation is 20 MHz")
    func adaptUsesOperatingWidthOverCapability() {
        var htCapabilities = [UInt8](repeating: 0, count: 19)
        htCapabilities[0] = 0x02 // 20/40 MHz capable
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 11 // primary channel
        htOperation[1] = 0 // no secondary channel
        let ieData = Data([45, UInt8(htCapabilities.count)] + htCapabilities)
            + Data([61, UInt8(htOperation.count)] + htOperation)
        let channel = WiFiChannel(band: .band24GHz, channelNumber: 11, channelWidthMHz: 20)
        let network = WiFiNetwork(
            ssid: "TwentyMHz",
            bssid: "AA:BB:CC:DD:EE:11",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 20)
    }

    @Test("Adapt reports 40 MHz only when HT operation has a secondary channel")
    func adaptUsesOperating40MHz() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 6 // primary channel
        htOperation[1] = 1 // secondary channel above
        let ieData = Data([61, UInt8(htOperation.count)] + htOperation)
        let channel = WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 20)
        let network = WiFiNetwork(
            ssid: "FortyMHz",
            bssid: "AA:BB:CC:DD:EE:40",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 40)
    }
}
