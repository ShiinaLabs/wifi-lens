import Foundation
import Testing
@testable import WiFi_Lens

/// Helper to build raw IE data in TLV format: each IE is [tag][length][value...].
private func buildIEData(_ ies: [[UInt8]]) -> Data {
    Data(ies.flatMap { $0 })
}

/// Convenience: single IE as Data.
private func singleIE(tag: UInt8, value: [UInt8]) -> Data {
    Data([tag, UInt8(value.count)] + value)
}

/// Little-endian UInt16 → [UInt8].
private func u16le(_ v: UInt16) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8(v >> 8)]
}

// MARK: - SSID

struct IEParserSSIDTests {
    @Test func normalSSID() {
        let data = singleIE(tag: 0, value: [0x4D, 0x79, 0x57, 0x69, 0x66, 0x69]) // "MyWifi"
        let result = IEParser.parse(data: data)
        #expect(result.isHiddenSSID == false)
    }

    @Test func hiddenSSID() {
        let data = singleIE(tag: 0, value: [])
        let result = IEParser.parse(data: data)
        #expect(result.isHiddenSSID == true)
    }
}

// MARK: - Country

struct IEParserCountryTests {
    @Test func countryCode() {
        let data = singleIE(tag: 7, value: [0x55, 0x53, 0x20]) // "US "
        let result = IEParser.parse(data: data)
        #expect(result.countryCode == "US ")
    }

    @Test func countryCodeWithExtraData() {
        let data = singleIE(tag: 7, value: [0x4A, 0x50, 0x20, 0x01, 0x0D]) // "JP " + extra
        let result = IEParser.parse(data: data)
        #expect(result.countryCode == "JP ")
    }

    @Test func countryTooShort() {
        let data = singleIE(tag: 7, value: [0x55, 0x53]) // only 2 bytes
        let result = IEParser.parse(data: data)
        #expect(result.countryCode == nil)
    }
}

// MARK: - HT Capabilities (802.11n)

struct IEParserHTCapabilitiesTests {
    @Test func htSupportedFlag() {
        // HT Cap body: Info(2) + A-MPDU(1) + MCS Set(16) = 19 bytes min
        let body = [UInt8](repeating: 0, count: 19)
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.htSupported == true)
    }

    @Test func supports40MHz() {
        var body = [UInt8](repeating: 0, count: 19)
        // HT Cap Info bytes 0-1: set bit 1 (Supported Channel Width Set)
        body[0] = 0x02  // bit 1 = 1
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == true)
    }

    @Test func no40MHz() {
        var body = [UInt8](repeating: 0, count: 19)
        body[0] = 0x00  // bit 1 = 0
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
    }

    @Test func mcsAndStreamsSingleStream() {
        // IE body: Info(2) + A-MPDU(1) + MCS Set(16)
        var body = [UInt8](repeating: 0, count: 19)
        // Rx MCS bitmask at offset 3: set MCS 0-7 (all 8 bits in byte 3)
        body[3] = 0xFF  // per-stream MCS 7, 1 spatial stream
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.maxMCSIndex == 7)
        #expect(result.spatialStreams == 1)
    }

    @Test func mcsAndStreamsTwoStreams() {
        var body = [UInt8](repeating: 0, count: 19)
        body[3] = 0xFF  // MCS 0-7
        // byte 4 (MCS 8-15): set bit 4 → global MCS 12 → per-stream MCS 4, 2 streams
        body[4] = 0x10
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.maxMCSIndex == 4)   // 12 % 8
        #expect(result.spatialStreams == 2) // MCS 12 → 2 streams
    }

    @Test func mcsAndStreamsThreeStreams() {
        var body = [UInt8](repeating: 0, count: 19)
        body[3] = 0xFF  // MCS 0-7
        body[4] = 0xFF  // MCS 8-15
        // byte 5: MCS 16-23 — set bit 7 → global MCS 23 → per-stream MCS 7, 3 streams
        body[5] = 0x80
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.maxMCSIndex == 7)   // 23 % 8
        #expect(result.spatialStreams == 3) // MCS 23 → 3 streams
    }

    @Test func htCapBodyTooShort() {
        let body = [UInt8](repeating: 0, count: 2)  // only 2 bytes
        let data = singleIE(tag: 45, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.htSupported == true)  // flag set before parsing depth
        #expect(result.maxMCSIndex == nil)
    }
}

// MARK: - HT Operation

struct IEParserHTOperationTests {
    private func htOperationPayload(primaryChannel: UInt8, secondaryChannelOffset: UInt8) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 22)
        payload[0] = primaryChannel
        payload[1] = secondaryChannelOffset & 0x03
        return payload
    }

    @Test func htOperation40MHzAbove() {
        // HT Operation: primary channel 6, secondary channel above (offset = 1).
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 1))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.operating40MHz == true)
    }

    @Test func htOperation40MHzBelow() {
        // HT Operation: primary channel 11, secondary channel below (offset = 3).
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 3))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.operating40MHz == true)
    }

    @Test func htOperation20MHzOnly() {
        // HT Operation: primary channel 6, no secondary channel (offset = 0).
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 0))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.operating40MHz == false)
    }

    @Test func primaryChannel11DoesNotImply40MHz() {
        // Regression for #99: channel 11 is 0b1011, whose low bits are 3.
        // Those bits belong to the primary channel and must not be parsed as an offset.
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 0))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.operating40MHz == false)
    }

    @Test func htOperationPayloadTooShort() {
        for payload in [[], [UInt8(11)]] {
            let result = IEParser.parse(data: singleIE(tag: 61, value: payload))
            #expect(result.operating40MHz == false)
        }
    }

    @Test func capabilitiesCanSupport40MHzWhileOperationUses20MHz() {
        var htCapabilities = [UInt8](repeating: 0, count: 19)
        htCapabilities[0] = 0x02 // HT Capabilities: 20/40 MHz capable.
        let htOperation = htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 0)
        let data = singleIE(tag: 45, value: htCapabilities) + singleIE(tag: 61, value: htOperation)
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == true)
        #expect(result.operating40MHz == false)
    }
}

// MARK: - VHT Capabilities (802.11ac)

struct IEParserVHTCapabilitiesTests {
    @Test func vhtSupportedFlag() {
        // VHT Cap body: Info(4) + MCS Set(8) = 12 bytes
        let body = [UInt8](repeating: 0, count: 12)
        let data = singleIE(tag: 191, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.vhtSupported == true)
    }

    @Test func vhtMCSNotParsed() {
        // VHT MCS/NSS is not parsed from IE data (CoreWLAN replaces MCS Map
        // bytes with fixed markers).  HT MCS is used as fallback instead.
        var body = [UInt8](repeating: 0, count: 12)
        body[4] = 0x0F
        let data = singleIE(tag: 191, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.vhtSupported == true)
        #expect(result.maxVHTMCSIndex == nil)
        #expect(result.spatialStreams == nil)  // no HT IE, so no NSS either
    }

    @Test func vhtBodyTooShort() {
        let body = [UInt8](repeating: 0, count: 5)  // too short for Rx MCS Map
        let data = singleIE(tag: 191, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.vhtSupported == true)
        #expect(result.maxVHTMCSIndex == nil)
    }
}

// MARK: - VHT Operation

struct IEParserVHTOperationTests {
    @Test func channelWidth80MHz() {
        // Channel Width byte = 1 → 80 MHz
        let data = singleIE(tag: 192, value: [0x01])
        let result = IEParser.parse(data: data)
        #expect(result.supports80MHz == true)
        #expect(result.supports160MHz == false)
    }

    @Test func channelWidth160MHz() {
        // Channel Width byte = 2 → 160 MHz
        let data = singleIE(tag: 192, value: [0x02])
        let result = IEParser.parse(data: data)
        #expect(result.supports80MHz == false)
        #expect(result.supports160MHz == true)
    }

    @Test func channelWidth80plus80() {
        // Channel Width byte = 3 → 80+80 (implies both 80 and 160)
        let data = singleIE(tag: 192, value: [0x03])
        let result = IEParser.parse(data: data)
        #expect(result.supports80MHz == true)
        #expect(result.supports160MHz == true)
    }

    @Test func channelWidth20Or40() {
        // Channel Width byte = 0 → 20/40 MHz only
        let data = singleIE(tag: 192, value: [0x00])
        let result = IEParser.parse(data: data)
        #expect(result.supports80MHz == false)
        #expect(result.supports160MHz == false)
    }
}

// MARK: - RSN (WPA2/WPA3)

struct IEParserRSNTests {
    // Build RSN IE body:
    // Version(2) + GroupCipher(4) + PairwiseCount(2) + PairwiseList(...) + AKMCount(2) + AKMList(...) + RSNCap(2)

    @Test func wpa2WithCCMP() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // CCMP (AES)
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // CCMP
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // WPA2
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.groupCipher == "CCMP (AES)")
        #expect(result.pairwiseCiphers == ["CCMP (AES)"])
        #expect(result.akmSuites == ["WPA2"])
        #expect(result.supportsWPA3 == false)
        #expect(result.securitySummary == "WPA2 (CCMP)")
    }

    @Test func wpa3SAE() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // CCMP
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x08]  // SAE (WPA3)
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supportsWPA3 == true)
        #expect(result.securitySummary == "SAE (WPA3) (CCMP)")
        #expect(result.akmSuites == ["SAE (WPA3)"])
    }

    @Test func wpa3FT_SAE() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x09]  // FT-SAE (WPA3)
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211r == true)  // FT variants imply 802.11r
        #expect(result.akmSuites == ["FT-SAE (WPA3)"])
    }

    @Test func fastTransition8021X() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x03]  // FT/802.1X
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == true)
        #expect(result.supportsWPA3 == false)
    }

    @Test func fastTransitionPSK() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // FT/PSK
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == true)
    }

    @Test func pmfCapable80211w() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x02]
        // RSN Capabilities: bit 7 = PMF capable
        let rsnCap = u16le(1 << 7)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211w == true)
    }

    @Test func pmfNotCapable() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akmSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x02]
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akmSuite + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211w == false)
    }

    @Test func multipleAKMSuites() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(2)
        let akm1: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // WPA2
        let akm2: [UInt8] = [0x00, 0x50, 0xF2, 0x08]  // SAE (WPA3)
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akm1 + akm2 + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.akmSuites.count == 2)
        #expect(result.akmSuites.contains("WPA2"))
        #expect(result.akmSuites.contains("SAE (WPA3)"))
        #expect(result.supportsWPA3 == true)
    }

    @Test func rsnBodyTooShort() {
        let body: [UInt8] = [0x01]  // only 1 byte, need 2 for version
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.akmSuites.isEmpty)
        #expect(result.groupCipher == nil)
    }
}

// MARK: - Extended Capabilities

struct IEParserExtendedCapabilitiesTests {
    @Test func supports80211v() {
        // bit 19 → byte 2 (19/8=2), bit position 3 (19%8=3)
        var ec = [UInt8](repeating: 0, count: 5)
        ec[2] = 1 << 3  // 0x08
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211v == true)
    }

    @Test func no80211v() {
        let ec = [UInt8](repeating: 0, count: 5)
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211v == false)
    }

    @Test func supports80211k() {
        // bit 32 → byte 4 (32/8=4), bit position 0 (32%8=0)
        var ec = [UInt8](repeating: 0, count: 5)
        ec[4] = 0x01
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == true)
    }

    @Test func supports80211rViaFT_Over_DS() {
        // bit 5 → byte 0 (5/8=0), bit position 5 (5%8=5)
        var ec = [UInt8](repeating: 0, count: 5)
        ec[0] = 1 << 5  // 0x20
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == true)
    }

    @Test func allBitsSet() {
        var ec = [UInt8](repeating: 0xFF, count: 5)
        // Fix: 802.11v bit 19 check doesn't need clearing, but 802.11k from
        // RM tag needs the tag present. We only test Extended Cap bits here.
        // Clear the 802.11k from bit 32 since it's covered by its own test.
        ec[4] = 0xFE  // clear bit 32 to isolate ext cap detection
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211v == true)
        #expect(result.supports80211r == true)
    }

    @Test func shortExtendedCapabilitiesDoesNotCrash() {
        // Only 2 bytes — bit 32 (byte 4) is out of range, should gracefully return false
        let ec: [UInt8] = [0xFF, 0xFF]
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == false)  // can't check bit 32
    }
}

// MARK: - 802.11k (RM Enabled Capabilities, tag 70)

struct IEParserRMEnabledTests {
    @Test func rmEnabledTagSets80211k() {
        // RM Enabled Capabilities IE: any body
        let data = singleIE(tag: 70, value: [0x01, 0x00, 0x00, 0x00, 0x00])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == true)
    }
}

// MARK: - 802.11r (Mobility Domain, tag 54)

struct IEParserMobilityDomainTests {
    @Test func mobilityDomainSets80211r() {
        // Mobility Domain IE: MDID(2) + FT Capability(1)
        let data = singleIE(tag: 54, value: [0x01, 0x02, 0x00])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == true)
    }

    @Test func mobilityDomainTooShort() {
        // Length < 2 → no FT
        let data = singleIE(tag: 54, value: [0x01])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == false)
    }
}

// MARK: - HE Capabilities (802.11ax, tag 255)

struct IEParserHECapabilitiesTests {
    @Test func heCapabilitiesDetected() {
        // Vendor-specific IE: OUI(3) + OUI type(1) + data
        // WFA OUI = 00:0F:AC, HE Capabilities type = 0x06
        let body: [UInt8] = [0x00, 0x0F, 0xAC, 0x06, 0x00, 0x00, 0x00]
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == true)
    }

    @Test func wrongOUINoHE() {
        // Different OUI
        let body: [UInt8] = [0x00, 0x10, 0x18, 0x06, 0x00, 0x00, 0x00]
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func wrongOUITypeNoHE() {
        // WFA OUI but wrong type (not 0x06)
        let body: [UInt8] = [0x00, 0x0F, 0xAC, 0x04, 0x00, 0x00, 0x00]
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func tooShortNoHE() {
        // Too short for OUI + type check
        let body: [UInt8] = [0x00, 0x0F, 0xAC]
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }
}

// MARK: - Combined multi-IE beacon

struct IEParserCombinedTests {
    @Test func fullBeacon() {
        // A realistic-ish beacon with multiple IEs
        let ssid = singleIE(tag: 0, value: [0x48, 0x6F, 0x6D, 0x65])  // "Home"

        // HT Cap: 40 MHz, MCS 0-15 (2 streams)
        var htBody = [UInt8](repeating: 0, count: 19)
        htBody[0] = 0x02  // 40 MHz capable
        htBody[3] = 0xFF  // MCS 0-7
        htBody[4] = 0xFF  // MCS 8-15
        let htCap = Data([45, UInt8(htBody.count)] + htBody)

        // VHT Op: 80 MHz
        let vhtOp = Data([192, 1, 1])

        // RSN: WPA2 + SAE (WPA3), PMF capable
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // CCMP
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(2)
        let akm1: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // WPA2
        let akm2: [UInt8] = [0x00, 0x50, 0xF2, 0x08]  // SAE (WPA3)
        let rsnCap = u16le(1 << 7)  // PMF capable
        let rsnBody = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akm1 + akm2 + rsnCap
        let rsn = Data([48, UInt8(rsnBody.count)] + rsnBody)

        // Extended Cap: 802.11v
        var ec = [UInt8](repeating: 0, count: 3)
        ec[2] = 1 << 3  // bit 19
        let extCap = Data([127, UInt8(ec.count)] + ec)

        // Country
        let country = Data([7, 3, 0x55, 0x53, 0x20])  // "US "

        // Combine all IEs
        let data = ssid + htCap + vhtOp + rsn + extCap + country

        let result = IEParser.parse(data: data)

        #expect(result.isHiddenSSID == false)
        #expect(result.htSupported == true)
        #expect(result.vhtSupported == false)  // VHT Op but no VHT Cap
        #expect(result.supports40MHz == true)
        #expect(result.supports80MHz == true)
        #expect(result.maxMCSIndex == 7)   // MCS 15 → per-stream MCS 7
        #expect(result.spatialStreams == 2)
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211w == true)
        #expect(result.supports80211v == true)
        #expect(result.countryCode == "US ")
        #expect(result.securitySummary == "SAE (WPA3)/WPA2 (CCMP)")
    }

    @Test func emptyData() {
        let data = Data()
        let result = IEParser.parse(data: data)
        #expect(result.htSupported == false)
        #expect(result.vhtSupported == false)
        #expect(result.akmSuites.isEmpty)
    }

    @Test func truncatedIE() {
        // IE says length=10 but only has 3 bytes of value
        var bytes = Data([0, 10])  // SSID tag, length 10
        bytes.append(contentsOf: [0x41, 0x42])  // only 2 bytes of SSID
        let result = IEParser.parse(data: bytes)
        // Should not crash; should stop parsing at guard
        #expect(result.isHiddenSSID == false)  // never reached the SSID handler
    }

    @Test func unknownTagSkipped() {
        // Unknown tag (e.g., tag 99) should be skipped gracefully
        let data = singleIE(tag: 99, value: [0x01, 0x02, 0x03])
        let result = IEParser.parse(data: data)
        // All defaults preserved
        #expect(result.htSupported == false)
        #expect(result.supports80211k == false)
    }
}

// MARK: - Cipher and AKM naming

struct IEParserCipherAKMTests {
    @Test func knownCiphers() {
        // Test that RSN parsing produces correct cipher names
        let version = u16le(1)
        // Group: TKIP
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x02]
        let pairwiseCount = u16le(2)
        let pairwise1: [UInt8] = [0x00, 0x50, 0xF2, 0x07]  // GCMP-128
        let pairwise2: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // CCMP (AES)
        let akmCount = u16le(1)
        let akm: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // WPA2
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwise1 + pairwise2 + akmCount + akm + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)

        #expect(result.groupCipher == "TKIP")
        #expect(result.pairwiseCiphers == ["GCMP-128", "CCMP (AES)"])
    }

    @Test func knownAKMs() {
        // WPA (not WPA2)
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // TKIP
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x02]  // TKIP
        let akmCount = u16le(1)
        let akm: [UInt8] = [0x00, 0x50, 0xF2, 0x01]  // WPA
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akm + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)

        #expect(result.akmSuites == ["WPA"])
        #expect(result.securitySummary == "WPA (TKIP)")
    }

    @Test func oweAKM() {
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
        let akmCount = u16le(1)
        let akm: [UInt8] = [0x00, 0x50, 0xF2, 0x12]  // OWE
        let rsnCap = u16le(0)
        let body = version + groupCipher + pairwiseCount + pairwiseSuite + akmCount + akm + rsnCap
        let data = singleIE(tag: 48, value: body)
        let result = IEParser.parse(data: data)

        #expect(result.akmSuites == ["OWE"])
        #expect(result.supportsWPA3 == false)
    }
}
