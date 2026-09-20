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

// Standard RSN suite helper. Legacy WPA OUI is accepted only when explicitly passed.
private func rsnSuite(_ selector: UInt8, oui: [UInt8] = [0x00, 0x0F, 0xAC]) -> [UInt8] {
    oui + [selector]
}

private func rsnIE(
    groupCipher: UInt8 = 0x04,
    pairwiseCiphers: [UInt8] = [0x04],
    akmSuites: [UInt8],
    rsnCapabilities: UInt16 = 0,
    oui: [UInt8] = [0x00, 0x0F, 0xAC]
) -> Data {
    let body = u16le(1)
        + rsnSuite(groupCipher, oui: oui)
        + u16le(UInt16(pairwiseCiphers.count))
        + pairwiseCiphers.flatMap { rsnSuite($0, oui: oui) }
        + u16le(UInt16(akmSuites.count))
        + akmSuites.flatMap { rsnSuite($0, oui: oui) }
        + u16le(rsnCapabilities)
    return singleIE(tag: 48, value: body)
}

/// Little-endian UInt16 → [UInt8].
private func u16le(_ v: UInt16) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8(v >> 8)]
}

/// VHT Operation body: channel width, center segments, basic MCS/NSS set.
private func vhtOperationPayload(
    channelWidth: UInt8,
    segment0: UInt8 = 42,
    segment1: UInt8 = 0
) -> [UInt8] {
    [channelWidth, segment0, segment1, 0xFF, 0xFF]
}

/// HE Capabilities payload after the Extension ID byte.
private func heCapabilitiesPayload(
    phyByte0: UInt8 = 0,
    phyByte6: UInt8 = 0,
    ppeHeader: UInt8? = nil
) -> [UInt8] {
    var payload = [UInt8](repeating: 0, count: 17) // HE MAC (6) + PHY (11)
    payload[6] = phyByte0
    payload[12] = phyByte6
    payload += [UInt8](repeating: 0, count: 4) // <= 80 MHz MCS/NSS

    if (phyByte0 & 0x08) != 0 {
        payload += [UInt8](repeating: 0, count: 4) // 160 MHz MCS/NSS
    }
    if (phyByte0 & 0x10) != 0 {
        payload += [UInt8](repeating: 0, count: 4) // 80+80 MHz MCS/NSS
    }

    if (phyByte6 & 0x80) != 0, let ppeHeader {
        payload.append(ppeHeader)
        let ruCount = (ppeHeader & 0x78).nonzeroBitCount
        let nssCount = Int(ppeHeader & 0x07) + 1
        let ppeBits = 7 + ruCount * nssCount * 6
        let ppeLength = (ppeBits + 7) / 8
        payload += [UInt8](repeating: 0, count: max(0, ppeLength - 1))
    }

    return payload
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
    private func htOperationPayload(
        primaryChannel: UInt8,
        secondaryChannelOffset: UInt8,
        staChannelWidthAny: Bool = false
    ) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 22)
        payload[0] = primaryChannel
        payload[1] = (secondaryChannelOffset & 0x03) | (staChannelWidthAny ? 0x04 : 0)
        return payload
    }

    @Test func htOperation40MHzAbove() {
        // HT Operation: primary channel 6, secondary channel above (offset = 1).
        let data = singleIE(
            tag: 61,
            value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 1, staChannelWidthAny: true)
        )
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.htChannelOperation == .some(.fortyMHzAbove))
        #expect(result.htChannelOperation?.spanDirection == .upper)
    }

    @Test func htOperation40MHzBelow() {
        // HT Operation: primary channel 11, secondary channel below (offset = 3).
        let data = singleIE(
            tag: 61,
            value: htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 3, staChannelWidthAny: true)
        )
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.htChannelOperation == .some(.fortyMHzBelow))
        #expect(result.htChannelOperation?.spanDirection == .lower)
    }

    @Test func htOperation20MHzOnly() {
        // HT Operation: primary channel 6, no secondary channel (offset = 0).
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 0))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.htChannelOperation == .some(.twentyMHz))
    }

    @Test func primaryChannel11DoesNotImply40MHz() {
        // Regression for #99: channel 11 is 0b1011, whose low bits are 3.
        // Those bits belong to the primary channel and must not be parsed as an offset.
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 0))
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == false)
        #expect(result.htChannelOperation == .some(.twentyMHz))
    }

    @Test func htOperationPayloadTooShort() {
        for payload in [[], [UInt8(11)]] {
            let result = IEParser.parse(data: singleIE(tag: 61, value: payload))
            #expect(result.htChannelOperation == nil)
        }
    }

    @Test func htOperationReservedSecondaryChannelOffsetIsUnknown() {
        let data = singleIE(tag: 61, value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 2))
        let result = IEParser.parse(data: data)
        #expect(result.htChannelOperation == nil)
    }

    @Test func htOperation40MHzRequiresSTAChannelWidthBit() {
        let above = IEParser.parse(
            data: singleIE(
                tag: 61,
                value: htOperationPayload(primaryChannel: 6, secondaryChannelOffset: 1)
            )
        )
        let below = IEParser.parse(
            data: singleIE(
                tag: 61,
                value: htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 3)
            )
        )

        #expect(above.htChannelOperation == .some(.twentyMHz))
        #expect(below.htChannelOperation == .some(.twentyMHz))
    }

    @Test func capabilitiesCanSupport40MHzWhileOperationUses20MHz() {
        var htCapabilities = [UInt8](repeating: 0, count: 19)
        htCapabilities[0] = 0x02 // HT Capabilities: 20/40 MHz capable.
        let htOperation = htOperationPayload(primaryChannel: 11, secondaryChannelOffset: 0)
        let data = singleIE(tag: 45, value: htCapabilities) + singleIE(tag: 61, value: htOperation)
        let result = IEParser.parse(data: data)
        #expect(result.supports40MHz == true)
        #expect(result.htChannelOperation == .some(.twentyMHz))
    }

    @Test func capabilityAndOperationRemainIndependentWhenOperating40MHz() {
        let htOperation = htOperationPayload(
            primaryChannel: 6,
            secondaryChannelOffset: 1,
            staChannelWidthAny: true
        )
        let result = IEParser.parse(data: singleIE(tag: 61, value: htOperation))
        #expect(result.supports40MHz == false)
        #expect(result.htChannelOperation == .some(.fortyMHzAbove))
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
        // Channel Width byte = 1 and segment 1 = 0 → 80 MHz.
        let data = singleIE(tag: 192, value: vhtOperationPayload(channelWidth: 1))
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.eightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyMHz))
    }

    @Test func channelWidth160MHz() {
        // Direct/deprecated Channel Width byte = 2 → 160 MHz.
        let data = singleIE(tag: 192, value: vhtOperationPayload(channelWidth: 2))
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.oneSixtyMHz))
        #expect(result.operatingChannelWidth == .some(.oneSixtyMHz))
    }

    @Test func channelWidth80plus80() {
        // Direct/deprecated Channel Width byte = 3 → non-contiguous 80+80.
        let data = singleIE(
            tag: 192,
            value: vhtOperationPayload(channelWidth: 3, segment0: 42, segment1: 106)
        )
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.eightyPlusEightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyPlusEightyMHz))
        #expect(result.operatingChannelWidth?.label == "80+80")
    }

    @Test func channelWidth20Or40() {
        // Channel Width byte = 0 delegates to HT Operation.
        let data = singleIE(tag: 192, value: vhtOperationPayload(channelWidth: 0))
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.useHT))
        #expect(result.operatingChannelWidth == nil)
    }

    @Test func newStyle160MHzUsesEightChannelSegmentSpacing() {
        let data = singleIE(
            tag: 192,
            value: vhtOperationPayload(channelWidth: 1, segment0: 42, segment1: 50)
        )
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.oneSixtyMHz))
        #expect(result.operatingChannelWidth == .some(.oneSixtyMHz))
    }

    @Test func newStyle80MHzKeepsAdjacentSegmentsTogether() {
        let data = singleIE(
            tag: 192,
            value: vhtOperationPayload(channelWidth: 1, segment0: 42, segment1: 58)
        )
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.eightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyMHz))
    }

    @Test func newStyle80plus80UsesWidelySeparatedSegments() {
        let data = singleIE(
            tag: 192,
            value: vhtOperationPayload(channelWidth: 1, segment0: 42, segment1: 106)
        )
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.eightyPlusEightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyPlusEightyMHz))
    }

    @Test func newStyle80MHzRejectsZeroCenterSegmentPair() {
        let data = singleIE(
            tag: 192,
            value: vhtOperationPayload(channelWidth: 1, segment0: 0, segment1: 106)
        )
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.eightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyMHz))
    }

    @Test func malformedVHTOperationDoesNotInventWidth() {
        let data = singleIE(tag: 192, value: [0x01, 42, 0, 0])
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == nil)
        #expect(result.operatingChannelWidth == nil)
    }

    @Test func reservedVHTChannelWidthIsUnknown() {
        let data = singleIE(tag: 192, value: vhtOperationPayload(channelWidth: 4))
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == nil)
        #expect(result.operatingChannelWidth == nil)
    }

    @Test func vhtUseHTPreservesHTOperationWidth() {
        var htOperation = [UInt8](repeating: 0, count: 22)
        htOperation[0] = 36
        htOperation[1] = 0x05
        let data = singleIE(tag: 61, value: htOperation)
            + singleIE(tag: 192, value: vhtOperationPayload(channelWidth: 0))
        let result = IEParser.parse(data: data)
        #expect(result.vhtChannelOperation == .some(.useHT))
        #expect(result.htChannelOperation == .some(.fortyMHzAbove))
        #expect(result.operatingChannelWidth == .some(.fortyMHz))
    }
}

// MARK: - RSN (WPA2/WPA3)

struct IEParserRSNTests {
    @Test func pskWithCCMP() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x02]))
        #expect(result.groupCipher == "CCMP (AES)")
        #expect(result.pairwiseCiphers == ["CCMP (AES)"])
        #expect(result.akmSuites == ["PSK"])
        #expect(result.supportsWPA3 == false)
        #expect(result.supports80211r == false)
        #expect(result.securitySummary == "PSK (CCMP)")
    }

    @Test func saeIsWPA3ButNotFastTransition() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x08]))
        #expect(result.akmSuites == ["SAE"])
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211r == false)
        #expect(result.securitySummary == "SAE (WPA3) (CCMP)")
    }

    @Test func ftSAEIsWPA3AndFastTransition() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x09]))
        #expect(result.akmSuites == ["FT-SAE"])
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211r == true)
    }

    @Test func fastTransitionAKMsSet80211r() {
        for selector: UInt8 in [0x03, 0x04, 0x09, 0x0D, 0x10, 0x11] {
            let result = IEParser.parse(data: rsnIE(akmSuites: [selector]))
            #expect(result.supports80211r == true, "selector 0x\(String(selector, radix: 16))")
        }
    }

    @Test func ordinaryAKMsDoNotSetWPA3OrFastTransition() {
        for selector: UInt8 in [0x01, 0x02, 0x05, 0x06, 0x0B] {
            let result = IEParser.parse(data: rsnIE(akmSuites: [selector]))
            #expect(result.supportsWPA3 == false, "selector 0x\(String(selector, radix: 16))")
            #expect(result.supports80211r == false, "selector 0x\(String(selector, radix: 16))")
        }
    }

    @Test func suiteB192IsWPA3Enterprise() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x0C]))
        #expect(result.akmSuites == ["802.1X-Suite-B-192"])
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211r == false)
    }

    @Test func oweIsEnhancedOpenNotWPA3OrFastTransition() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x12]))
        #expect(result.akmSuites == ["OWE"])
        #expect(result.supportsWPA3 == false)
        #expect(result.supports80211r == false)
        #expect(result.securitySummary == "OWE (CCMP)")
    }

    @Test func transitionModeContainsPSKAndSAE() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x02, 0x08]))
        #expect(result.akmSuites.contains("PSK"))
        #expect(result.akmSuites.contains("SAE"))
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211r == false)
    }

    @Test func legacyWPAOUIInsideRSNIsRejected() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x08], oui: [0x00, 0x50, 0xF2]))
        #expect(result.groupCipher == "Unknown")
        #expect(result.pairwiseCiphers == ["Unknown"])
        #expect(result.akmSuites == ["Unknown"])
        #expect(result.supportsWPA3 == false)
        #expect(result.supports80211r == false)
    }

    @Test func pmfCapable80211w() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x02], rsnCapabilities: 1 << 7))
        #expect(result.supports80211w == true)
    }

    @Test func pmfNotCapable() {
        let result = IEParser.parse(data: rsnIE(akmSuites: [0x02]))
        #expect(result.supports80211w == false)
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

    @Test func qosMapBitDoesNotImply80211k() {
        // Extended Capabilities bit 32 is QoS Map, not 802.11k.
        var ec = [UInt8](repeating: 0, count: 5)
        ec[4] = 0x01
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == false)
    }

    @Test func reservedBit5DoesNotImply80211r() {
        // Extended Capabilities bit 5 is reserved, not 802.11r.
        var ec = [UInt8](repeating: 0, count: 5)
        ec[0] = 1 << 5  // 0x20
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == false)
    }

    @Test func extendedCapabilitiesOnlyDerive80211v() {
        let ec = [UInt8](repeating: 0xFF, count: 5)
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211v == true)
        #expect(result.supports80211k == false)
        #expect(result.supports80211r == false)
    }

    @Test func shortExtendedCapabilitiesDoesNotCrash() {
        // Only 2 bytes — bit 19 is out of range, should gracefully return false
        let ec: [UInt8] = [0xFF, 0xFF]
        let data = singleIE(tag: 127, value: ec)
        let result = IEParser.parse(data: data)
        #expect(result.supports80211v == false)
    }

    @Test func standardIEsProvideKAndRSeparately() {
        var ec = [UInt8](repeating: 0, count: 3)
        ec[2] = 1 << 3 // Extended Capabilities bit 19 → 802.11v
        let extCapabilities = singleIE(tag: 127, value: ec)
        let rmEnabled = singleIE(tag: 70, value: [0x01, 0x00, 0x00, 0x00, 0x00])
        let mobilityDomain = singleIE(tag: 54, value: [0x01, 0x02, 0x00])

        let result = IEParser.parse(data: extCapabilities + rmEnabled + mobilityDomain)

        #expect(result.supports80211v == true)
        #expect(result.supports80211k == true)
        #expect(result.supports80211r == true)
    }
}

// MARK: - 802.11k (RM Enabled Capabilities, tag 70)

struct IEParserRMEnabledTests {
    @Test func rmEnabledTagSets80211k() {
        // RRM Enabled Capabilities IE: five-byte body.
        let data = singleIE(tag: 70, value: [0x01, 0x00, 0x00, 0x00, 0x00])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == true)
    }

    @Test func rmEnabledFourByteBodyIsRejected() {
        let data = singleIE(tag: 70, value: [0x01, 0x00, 0x00, 0x00])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == false)
    }

    @Test func rmEnabledEmptyBodyIsRejected() {
        let data = singleIE(tag: 70, value: [])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211k == false)
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
        // Missing the two-byte MDID and one-byte FT capability/policy.
        let data = singleIE(tag: 54, value: [0x01])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == false)
    }

    @Test func mobilityDomainMissingFTCapabilityIsRejected() {
        // Two-byte MDID without the required FT Capability & Policy byte.
        let data = singleIE(tag: 54, value: [0x01, 0x02])
        let result = IEParser.parse(data: data)
        #expect(result.supports80211r == false)
    }
}

// MARK: - HE Capabilities (802.11ax Extension IE 255, extension ID 35)

struct IEParserHECapabilitiesTests {
    @Test func heCapabilitiesDetected() {
        let body = [0x23] + heCapabilitiesPayload()
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == true)
    }

    @Test func heCapabilitiesSupportsOptional160MHzMCSNSS() {
        let body = [0x23] + heCapabilitiesPayload(phyByte0: 0x08)
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == true)
    }

    @Test func heCapabilitiesSupportsOptional80Plus80MHzMCSNSS() {
        let body = [0x23] + heCapabilitiesPayload(phyByte0: 0x10)
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == true)
    }

    @Test func heCapabilitiesSupportsPPEThreshold() {
        // One RU bit, one spatial stream: header + one packed data byte.
        let payload = heCapabilitiesPayload(phyByte6: 0x80, ppeHeader: 0x08)
        let body = [0x23] + payload
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == true)
    }

    @Test func heCapabilitiesRejectsTruncatedBaseMCSNSS() {
        let body = [0x23] + [UInt8](repeating: 0, count: 20)
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func heCapabilitiesRejectsTruncatedOptionalMCSNSS() {
        let payload = heCapabilitiesPayload(phyByte0: 0x08)
        let body = [0x23] + [UInt8](payload.dropLast())
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func heCapabilitiesRejectsTruncatedPPEThreshold() {
        let payload = heCapabilitiesPayload(phyByte6: 0x80, ppeHeader: 0x08)
        let body = [0x23] + [UInt8](payload.dropLast())
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func heCapabilitiesRejectsMissingPPEHeader() {
        let body = [0x23] + heCapabilitiesPayload(phyByte6: 0x80)
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func nonHEExtensionIsIgnored() {
        let body = [0x25] + heCapabilitiesPayload()
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func heOperationExtensionIsIgnored() {
        let body = [0x24] + heCapabilitiesPayload()
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func legacyPseudoVendorHEFormatIsRejected() {
        // This is the old, incorrect tag-255 vendor/WFA fixture. It must not
        // be accepted as a standard HE Capabilities Extension IE.
        let body: [UInt8] = [0x00, 0x0F, 0xAC, 0x06, 0x00, 0x00, 0x00]
        let data = singleIE(tag: 255, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func vendorSpecificElementIsNotHECapabilities() {
        let body = [0x00, 0x0F, 0xAC, 0x06] + heCapabilitiesPayload()
        let data = singleIE(tag: 221, value: body)
        let result = IEParser.parse(data: data)
        #expect(result.heSupported == false)
    }

    @Test func emptyExtensionIsIgnored() {
        let data = singleIE(tag: 255, value: [])
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

        // VHT Op: 80 MHz (full five-byte payload)
        let vhtOp = Data([192, 5] + vhtOperationPayload(channelWidth: 1))

        // RSN: PSK + SAE (WPA3), PMF capable
        let version = u16le(1)
        let groupCipher: [UInt8] = [0x00, 0x0F, 0xAC, 0x04]  // CCMP
        let pairwiseCount = u16le(1)
        let pairwiseSuite: [UInt8] = [0x00, 0x0F, 0xAC, 0x04]
        let akmCount = u16le(2)
        let akm1: [UInt8] = [0x00, 0x0F, 0xAC, 0x02]  // PSK
        let akm2: [UInt8] = [0x00, 0x0F, 0xAC, 0x08]  // SAE
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
        #expect(result.vhtChannelOperation == .some(.eightyMHz))
        #expect(result.operatingChannelWidth == .some(.eightyMHz))
        #expect(result.maxMCSIndex == 7)   // MCS 15 → per-stream MCS 7
        #expect(result.spatialStreams == 2)
        #expect(result.supportsWPA3 == true)
        #expect(result.supports80211w == true)
        #expect(result.supports80211v == true)
        #expect(result.countryCode == "US ")
        #expect(result.securitySummary == "SAE (WPA3)/PSK (CCMP)")
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
        let result = IEParser.parse(data: rsnIE(
            groupCipher: 0x02,
            pairwiseCiphers: [0x08, 0x04],
            akmSuites: [0x02]
        ))

        #expect(result.groupCipher == "TKIP")
        #expect(result.pairwiseCiphers == ["GCMP-128", "CCMP (AES)"])
    }

    @Test func cipherSelectorsSevenThroughThirteenUseStandardRSNMapping() {
        let result = IEParser.parse(data: rsnIE(
            pairwiseCiphers: [0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D],
            akmSuites: [0x02]
        ))
        #expect(result.pairwiseCiphers == [
            "No Group Addressed",
            "GCMP-128",
            "GCMP-256",
            "CCMP-256",
            "BIP-GMAC-128",
            "BIP-GMAC-256",
            "BIP-CMAC-256"
        ])
    }

    @Test func legacyWPAOUIIsUnknownCipherInRSN() {
        let result = IEParser.parse(data: rsnIE(
            groupCipher: 0x04,
            pairwiseCiphers: [0x04],
            akmSuites: [0x02],
            oui: [0x00, 0x50, 0xF2]
        ))
        #expect(result.groupCipher == "Unknown")
        #expect(result.pairwiseCiphers == ["Unknown"])
    }

    @Test func knownAKMsUseStandardRSNNames() {
        let result = IEParser.parse(data: rsnIE(
            groupCipher: 0x02,
            pairwiseCiphers: [0x02],
            akmSuites: [0x01]
        ))
        #expect(result.akmSuites == ["802.1X"])
        #expect(result.securitySummary == "802.1X (TKIP)")
    }

    @Test func allKnownRSNAKMSelectorsHaveStandardNames() {
        let expected: [(UInt8, String)] = [
            (0x01, "802.1X"),
            (0x02, "PSK"),
            (0x03, "FT/802.1X"),
            (0x04, "FT/PSK"),
            (0x05, "802.1X-SHA256"),
            (0x06, "PSK-SHA256"),
            (0x07, "TDLS"),
            (0x08, "SAE"),
            (0x09, "FT-SAE"),
            (0x0B, "802.1X-Suite-B"),
            (0x0C, "802.1X-Suite-B-192"),
            (0x0D, "FT/802.1X-SHA384"),
            (0x0E, "FILS-SHA256"),
            (0x0F, "FILS-SHA384"),
            (0x10, "FT-FILS-SHA256"),
            (0x11, "FT-FILS-SHA384"),
            (0x12, "OWE")
        ]

        for (selector, name) in expected {
            let result = IEParser.parse(data: rsnIE(akmSuites: [selector]))
            #expect(result.akmSuites == [name], "selector 0x\(String(selector, radix: 16))")
        }
    }
}
