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
        // HT Capabilities (tag 45): complete 26-byte body, bit 1 clear = no 40MHz
        // VHT Operation (tag 192): chWidth 0 = 20/40 only
        let htCapabilities = [UInt8](repeating: 0, count: 26)
        let ieData = Data([45, UInt8(htCapabilities.count)] + htCapabilities)
            + Data([192, 5, 0, 36, 0, 0, 0])
        let ch = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80)
        let nw = WiFiNetwork(ssid: "WideNet", bssid: "AA:BB:CC:DD:EE:FF", rssi: -50, channel: ch, ieData: ieData)
        let obs = NetworkObservationAdapter.adapt(nw)
        #expect(obs.capabilities.channelWidth == 80)
        #expect(obs.capabilities.phyMode == "n")
    }

    @Test("Adapt reports 20 MHz when HT capabilities allow 40 MHz but operation is 20 MHz")
    func adaptUsesOperatingWidthOverCapability() {
        var htCapabilities = [UInt8](repeating: 0, count: 26)
        htCapabilities[0] = 0x02 // 20/40 MHz capable
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 11 // primary channel
        htOperation[1] = 0 // no secondary channel
        let ieData = Data([45, UInt8(htCapabilities.count)] + htCapabilities)
            + Data([61, UInt8(htOperation.count)] + htOperation)
        let channel = WiFiChannel(band: .band24GHz, channelNumber: 11, channelWidthMHz: 80)
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

    @Test("HE Capabilities extension reports ax PHY mode")
    func adaptRecognizesHECapabilitiesAsWiFi6() {
        // Standard HE Capabilities Extension IE: extension ID 35, followed by
        // 17 fixed MAC/PHY bytes and the required <=80 MHz MCS/NSS bytes.
        let heBody = [UInt8](arrayLiteral: 0x23)
            + [UInt8](repeating: 0, count: 21)
        let ieData = Data([255, UInt8(heBody.count)] + heBody)
        let channel = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80)
        let network = WiFiNetwork(
            ssid: "WiFi6",
            bssid: "AA:BB:CC:DD:EE:35",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.phyMode == "ax")
    }

    @Test("Adapt reports 40 MHz only when HT operation has a secondary channel")
    func adaptUsesHT40Operation() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 6 // primary channel
        htOperation[1] = 0x05 // STA Channel Width Any + secondary channel above
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

    @Test("Adapt preserves the CoreWLAN fallback when HT operation is unknown")
    func adaptUsesFallbackForUnknownHTOperation() {
        let malformedHTOperation = Data([61, 1, 6])
        let channel = WiFiChannel(band: .band24GHz, channelNumber: 6, channelWidthMHz: 80)
        let network = WiFiNetwork(
            ssid: "UnknownWidth",
            bssid: "AA:BB:CC:DD:EE:41",
            rssi: -50,
            channel: channel,
            ieData: malformedHTOperation
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 80)
    }

    @Test("Adapt preserves the CoreWLAN fallback for non-contiguous VHT 80+80")
    func adaptUsesFallbackForVHT80Plus80() {
        let vht80plus80 = Data([192, 5, 3, 42, 106, 0, 0])
        let channel = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 80)
        let network = WiFiNetwork(
            ssid: "NonContiguous",
            bssid: "AA:BB:CC:DD:EE:80",
            rssi: -50,
            channel: channel,
            ieData: vht80plus80
        )

        let observation = NetworkObservationAdapter.adapt(network)

        // The scalar observation model cannot represent two disjoint 80 MHz
        // segments; retain CoreWLAN's fallback instead of inventing 160.
        #expect(observation.capabilities.channelWidth == 80)
    }

    @Test("VHT operation remains higher priority than explicit HT 20 MHz")
    func adaptPreservesVHTWidthPriority() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 36
        htOperation[1] = 0
        let ieData = Data([61, UInt8(htOperation.count)] + htOperation)
            + Data([192, 5, 1, 42, 0, 0, 0])
        let channel = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 20)
        let network = WiFiNetwork(
            ssid: "VHTWide",
            bssid: "AA:BB:CC:DD:EE:42",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 80)
    }

    @Test("VHT 160 MHz remains higher priority than explicit HT 20 MHz")
    func adaptPreservesVHT160WidthPriority() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 36
        htOperation[1] = 0
        let ieData = Data([61, UInt8(htOperation.count)] + htOperation)
            + Data([192, 5, 2, 42, 0, 0, 0])
        let channel = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 20)
        let network = WiFiNetwork(
            ssid: "VHT160Wide",
            bssid: "AA:BB:CC:DD:EE:43",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 160)
    }

    @Test("VHT use-HT operation defers to HT 40 MHz")
    func adaptVHTUseHTDefersToHTOperation() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 36
        htOperation[1] = 0x05
        let ieData = Data([61, UInt8(htOperation.count)] + htOperation)
            + Data([192, 5, 0, 42, 0, 0, 0])
        let channel = WiFiChannel(band: .band5GHz, channelNumber: 36, channelWidthMHz: 20)
        let network = WiFiNetwork(
            ssid: "VHTUseHT",
            bssid: "AA:BB:CC:DD:EE:44",
            rssi: -50,
            channel: channel,
            ieData: ieData
        )

        let observation = NetworkObservationAdapter.adapt(network)

        #expect(observation.capabilities.channelWidth == 40)
    }
}
