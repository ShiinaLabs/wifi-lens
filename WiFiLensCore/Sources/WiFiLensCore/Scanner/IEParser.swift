import Foundation

/// The BSS channel operation advertised by the HT Operation element.
///
/// An absent value on `IEData` means that the HT Operation element was not
/// present or could not be parsed. This is intentionally separate from
/// `.twentyMHz`, which is an explicit secondary-channel offset of zero.
enum HTChannelOperation: Equatable, Sendable {
    case twentyMHz
    case fortyMHzAbove
    case fortyMHzBelow

    var widthMHz: Int {
        switch self {
        case .twentyMHz: 20
        case .fortyMHzAbove, .fortyMHzBelow: 40
        }
    }

    var spanDirection: SpanDirection? {
        switch self {
        case .twentyMHz: nil
        case .fortyMHzAbove: .upper
        case .fortyMHzBelow: .lower
        }
    }
}

/// The current channel operation advertised by the VHT Operation element.
///
/// `useHT` delegates the effective 20/40 MHz width to HT Operation. The
/// remaining cases describe VHT operation directly, including the
/// non-contiguous 80+80 MHz layout.
enum VHTChannelOperation: Equatable, Sendable {
    case useHT
    case eightyMHz
    case oneSixtyMHz
    case eightyPlusEightyMHz
}

/// A user-facing operating width derived from HT and VHT Operation elements.
///
/// The scalar MHz value is intentionally unavailable for 80+80 MHz because
/// two non-contiguous 80 MHz segments cannot be represented by one span.
enum IEOperatingChannelWidth: Equatable, Sendable {
    case twentyMHz
    case fortyMHz
    case eightyMHz
    case oneSixtyMHz
    case eightyPlusEightyMHz

    var label: String {
        switch self {
        case .twentyMHz: "20"
        case .fortyMHz: "40"
        case .eightyMHz: "80"
        case .oneSixtyMHz: "160"
        case .eightyPlusEightyMHz: "80+80"
        }
    }

    /// Width for scalar observation models. 80+80 needs segment-aware data.
    var widthMHz: Int? {
        switch self {
        case .twentyMHz: 20
        case .fortyMHz: 40
        case .eightyMHz: 80
        case .oneSixtyMHz: 160
        case .eightyPlusEightyMHz: nil
        }
    }
}

/// Parsed 802.11 information elements and derived capabilities from beacon/probe response data.
struct IEData {
    /// Whether 802.11k (Radio Measurement) is supported
    var supports80211k: Bool = false
    /// Whether 802.11r (Fast BSS Transition) is supported
    var supports80211r: Bool = false
    /// Whether 802.11v (BSS Transition Management) is supported
    var supports80211v: Bool = false
    /// Whether 802.11w (Protected Management Frames) is supported
    var supports80211w: Bool = false
    /// Whether WPA3 is supported (via RSN AKM suite)
    var supportsWPA3: Bool = false

    // High-throughput capabilities
    var htSupported: Bool = false
    var vhtSupported: Bool = false
    var heSupported: Bool = false  // 802.11ax / Wi-Fi 6
    var ehtSupported: Bool = false // 802.11be / Wi-Fi 7

    // Channel width capability and current operation
    /// Whether HT Capabilities advertise 20/40 MHz support.
    var supports40MHz: Bool = false
    /// The current BSS channel operation from HT Operation, when available.
    /// A missing value means the operation is unknown, not that it is 20 MHz.
    var htChannelOperation: HTChannelOperation?
    /// The current BSS channel operation from VHT Operation, when available.
    /// A missing value means the element was absent or malformed.
    var vhtChannelOperation: VHTChannelOperation?

    /// Effective operating width, with VHT Operation taking precedence when
    /// it advertises a VHT width and falling back to HT Operation for
    /// `useHT` or when VHT Operation is absent.
    var operatingChannelWidth: IEOperatingChannelWidth? {
        switch vhtChannelOperation {
        case .eightyMHz:
            return .eightyMHz
        case .oneSixtyMHz:
            return .oneSixtyMHz
        case .eightyPlusEightyMHz:
            return .eightyPlusEightyMHz
        case .useHT, nil:
            break
        }

        switch htChannelOperation {
        case .twentyMHz:
            return .twentyMHz
        case .fortyMHzAbove, .fortyMHzBelow:
            return .fortyMHz
        case nil:
            return nil
        }
    }

    // Raw info
    var maxMCSIndex: Int?
    var spatialStreams: Int?

    // Security
    var akmSuites: [String] = []
    var pairwiseCiphers: [String] = []
    var groupCipher: String?

    // Country
    var countryCode: String?

    // Hidden SSID
    var isHiddenSSID: Bool = false

    /// Security summary for table display
    var securitySummary: String {
        if akmSuites.isEmpty { return "" }

        // Collect distinct security levels present
        var labels: [String] = []

        // WPA3 variants. The AKM names themselves stay protocol-accurate;
        // the WPA3 display label is added only in this user-facing summary.
        let wpa3AKMNames: Set<String> = ["SAE", "FT-SAE", "802.1X-Suite-B-192"]
        let wpa3Suites = akmSuites
            .filter { wpa3AKMNames.contains($0) }
            .map { "\($0) (WPA3)" }
        if !wpa3Suites.isEmpty {
            labels.append(wpa3Suites.joined(separator: "/"))
        }

        // RSN variants (excluding WPA3). These are the names produced by the
        // RSN parser; legacy WPA labels are intentionally not synthesized here.
        let rsnSuites = akmSuites.filter { suite in
            !wpa3AKMNames.contains(suite)
                && (suite == "802.1X"
                    || suite == "PSK"
                    || suite.hasPrefix("FT/")
                    || suite.contains("SHA256")
                    || suite.contains("SHA384")
                    || suite.contains("Suite-B")
                    || suite.contains("FILS"))
        }
        if !rsnSuites.isEmpty {
            labels.append(rsnSuites.joined(separator: "/"))
        }

        // OWE / other
        let otherSuites = akmSuites.filter { $0 == "OWE" || $0 == "TDLS" || $0 == "AP PeerKey" }
        if !otherSuites.isEmpty {
            labels.append(contentsOf: otherSuites)
        }

        let joined = labels.isEmpty
            ? (akmSuites.first?.components(separatedBy: " ").first ?? akmSuites.first ?? "")
            : labels.joined(separator: "/")

        // Append encryption cipher when available
        let cipher = pairwiseCiphers.first.map { $0.replacingOccurrences(of: " (AES)", with: "") } ?? ""
        if !cipher.isEmpty && !cipher.contains("Unknown") {
            return "\(joined) (\(cipher))"
        }
        return joined
    }

    /// MCS summary derived from the trusted HT MCS bitmask.
    var mcsSummary: String {
        if let ht = maxMCSIndex { return "\(ht)" }
        return ""
    }

    /// Spatial streams: e.g. "2" or ""
    var nssSummary: String {
        spatialStreams.map { "\($0)" } ?? ""
    }

    init() {}
}

enum IEParser {
    // IE Tag constants
    private static let tagSSID: UInt8 = 0
    private static let tagCountry: UInt8 = 7
    private static let tagHTCapabilities: UInt8 = 45
    private static let tagRSN: UInt8 = 48
    private static let tagHTOperation: UInt8 = 61
    private static let tagRMEnabled: UInt8 = 70  // 802.11k
    private static let tagMobilityDomain: UInt8 = 54  // 802.11r
    private static let tagExtendedCapabilities: UInt8 = 127
    private static let tagVHTCapabilities: UInt8 = 191
    private static let tagVHTOperation: UInt8 = 192
    private static let tagExtension: UInt8 = 255

    // Extension Element IDs (Element ID Extension, tag 255)
    private static let extensionIDHECapabilities: UInt8 = 35
    private static let extensionIDHEOperation: UInt8 = 36

    // Extended Capabilities bit positions (within the IE data bytes)
    // Bit numbering follows 802.11: bit 0 is LSB of byte 0
    private static let extCapBit_BSS_Transition: Int = 19     // 802.11v

    // RSN suite OUI. Legacy WPA's 00:50:F2 OUI belongs to Vendor Specific
    // elements and must not be accepted inside an RSN element.
    private static let rsnOUI: [UInt8] = [0x00, 0x0F, 0xAC]

    static func parse(data: Data) -> IEData {
        var result = IEData()
        var offset = 0
        let bytes = [UInt8](data)

        while offset + 2 <= bytes.count {
            let tag = bytes[offset]
            let length = Int(bytes[offset + 1])
            offset += 2

            guard offset + length <= bytes.count else { break }
            let ieData = Array(bytes[offset..<offset + length])

            switch tag {
            case tagSSID:
                result.isHiddenSSID = (length == 0)

            case tagCountry:
                if ieData.count >= 3 {
                    result.countryCode = String(bytes: ieData[0..<3], encoding: .ascii)
                }

            case tagHTCapabilities:
                guard ieData.count >= 26 else { break }
                result.htSupported = true
                parseHTCapabilities(ieData, into: &result)

            case tagVHTCapabilities:
                guard ieData.count >= 12 else { break }
                result.vhtSupported = true
                // VHT MCS/NSS from CoreWLAN's IE data is unreliable — the
                // MCS Map bytes are replaced with fixed markers.  We rely on
                // trusted HT MCS (which is normally present on VHT APs for
                // backwards compatibility) and intentionally do not parse the
                // unreliable VHT MCS map.

            case tagHTOperation:
                parseHTOperation(ieData, into: &result)

            case tagVHTOperation:
                parseVHTOperation(ieData, into: &result)

            case tagRSN:
                parseRSN(ieData, into: &result)

            case tagExtendedCapabilities:
                parseExtendedCapabilities(ieData, into: &result)

            case tagRMEnabled:
                // RRM Enabled Capabilities is a five-byte IE. Do not infer
                // 802.11k from an empty or truncated element.
                if ieData.count >= 5 {
                    result.supports80211k = true
                }

            case tagMobilityDomain:
                // If Mobility Domain IE is present, 802.11r FT is active
                if ieData.count >= 3 {
                    result.supports80211r = true
                }

            case tagExtension:
                parseExtensionElement(ieData, into: &result)

            default:
                break
            }

            offset += length
        }

        return result
    }

    // MARK: - HT Capabilities (802.11n)

    private static func parseHTCapabilities(_ data: [UInt8], into result: inout IEData) {
        guard data.count >= 26 else { return }
        let htCapInfo = (UInt16(data[0]) | (UInt16(data[1]) << 8))

        // Channel width: bit 1
        result.supports40MHz = (htCapInfo & (1 << 1)) != 0

        // HT Cap body: Info(2) + A-MPDU(1) = 3 bytes → Supported MCS Set at offset 3.
        // Rx MCS Bitmask occupies the first 10 bytes of the MCS Set (bits 0–79).
        if data.count >= 13 {
            let mcsBytes = Array(data[3..<min(13, data.count)])
            let mcs = maxMCSSpatialStreams(mcsBytes)
            result.maxMCSIndex = mcs.mcs
            result.spatialStreams = mcs.streams
        }
    }

    private static func parseHTOperation(_ data: [UInt8], into result: inout IEData) {
        // Byte 0 is the primary channel. Byte 1's HT Operation Information
        // subset carries both the secondary channel offset (bits 0–1) and the
        // STA Channel Width flag (bit 2). An offset of 1 or 3 is an active
        // HT40 secondary channel only when that flag is set; otherwise the
        // operation is explicitly 20 MHz.
        guard data.count >= 22 else { return }
        let operationInfo = data[1]
        let secondaryChannelOffset = operationInfo & 0x03
        let staChannelWidthAny = (operationInfo & 0x04) != 0
        switch secondaryChannelOffset {
        case 0:
            result.htChannelOperation = .twentyMHz
        case 1 where staChannelWidthAny:
            result.htChannelOperation = .fortyMHzAbove
        case 3 where staChannelWidthAny:
            result.htChannelOperation = .fortyMHzBelow
        case 1, 3:
            result.htChannelOperation = .twentyMHz
        default:
            // Offset 2 is reserved. Keep the operation unknown rather than
            // treating a malformed/reserved value as an explicit 20 MHz state.
            result.htChannelOperation = nil
        }
    }

    private static func parseVHTOperation(_ data: [UInt8], into result: inout IEData) {
        // VHT Operation is 5 bytes:
        // channel width, center frequency segment 0, center frequency
        // segment 1, and the two-byte basic VHT-MCS/NSS set.
        guard data.count >= 5 else { return }

        let channelWidth = data[0]
        let segment0 = Int(data[1])
        let segment1 = Int(data[2])

        switch channelWidth {
        case 0:
            // 20/40 MHz operation is defined by HT Operation.
            result.vhtChannelOperation = .useHT
        case 1:
            // Linux/mac80211 uses this encoding for 80 MHz and for the
            // interop form of 160/80+80. Segment spacing disambiguates them.
            // A zero center segment is the ordinary 80 MHz encoding. Treat
            // either zero segment as 80 MHz rather than inferring a
            // non-contiguous pair from an incomplete operation element.
            guard segment0 != 0, segment1 != 0 else {
                result.vhtChannelOperation = .eightyMHz
                return
            }

            let segmentDifference = abs(segment1 - segment0)
            if segmentDifference == 8 {
                result.vhtChannelOperation = .oneSixtyMHz
            } else if segmentDifference > 16 {
                result.vhtChannelOperation = .eightyPlusEightyMHz
            } else {
                result.vhtChannelOperation = .eightyMHz
            }
        case 2:
            // Deprecated/direct encoding retained for interoperability.
            result.vhtChannelOperation = .oneSixtyMHz
        case 3:
            // Deprecated/direct encoding retained for interoperability.
            result.vhtChannelOperation = .eightyPlusEightyMHz
        default:
            // Reserved channel-width values are unknown.
            result.vhtChannelOperation = nil
        }
    }

    // MARK: - Extension Elements

    private static func parseExtensionElement(_ data: [UInt8], into result: inout IEData) {
        guard let extensionID = data.first else { return }

        switch extensionID {
        case extensionIDHECapabilities:
            let payload = Array(data.dropFirst())
            if isValidHECapabilities(payload) {
                result.heSupported = true
            }
        case extensionIDHEOperation:
            // HE Operation is intentionally left for a later parsing round.
            break
        default:
            break
        }
    }

    /// Checks the variable-length HE Capabilities payload without interpreting
    /// its individual capability bits. The fixed HE MAC/PHY fields are
    /// followed by MCS/NSS fields selected by PHY capability bits and an
    /// optional PPE Threshold field.
    private static func isValidHECapabilities(_ data: [UInt8]) -> Bool {
        let fixedCapabilitiesLength = 17  // 6-byte MAC + 11-byte PHY
        let baseMCSNSSLength = 4          // MCS/NSS for <= 80 MHz

        guard data.count >= fixedCapabilitiesLength else { return false }

        // PHY Capabilities byte 0 is at payload offset 6. Its width bits
        // select optional 160 MHz and 80+80 MHz MCS/NSS fields.
        let phyCapabilitiesByte0 = data[6]
        var requiredLength = fixedCapabilitiesLength + baseMCSNSSLength
        if (phyCapabilitiesByte0 & 0x08) != 0 {
            requiredLength += 4  // 160 MHz MCS/NSS
        }
        if (phyCapabilitiesByte0 & 0x10) != 0 {
            requiredLength += 4  // 80+80 MHz MCS/NSS
        }
        guard data.count >= requiredLength else { return false }

        // PHY Capabilities byte 6 is at payload offset 12. If PPE Threshold
        // information is present, the first byte is its header and the rest
        // is a bit-packed field whose size depends on RU and NSS counts.
        let phyCapabilitiesByte6 = data[12]
        guard (phyCapabilitiesByte6 & 0x80) != 0 else { return true }
        guard data.count > requiredLength else { return false }

        let ppeHeader = data[requiredLength]
        let ruCount = (ppeHeader & 0x78).nonzeroBitCount
        let nssCount = Int(ppeHeader & 0x07) + 1
        let ppeBits = 7 + ruCount * nssCount * 6
        let ppeLength = (ppeBits + 7) / 8
        return data.count >= requiredLength + ppeLength
    }

    // MARK: - RSN (WPA2/WPA3)

    private static func parseRSN(_ data: [UInt8], into result: inout IEData) {
        guard data.count >= 2 else { return }
        var pos = 2

        // Parse into locals first. A declared suite count that cannot fit in
        // the remaining payload invalidates the whole RSN element, so a
        // truncated element cannot leave partial cipher or security state.
        guard pos + 4 <= data.count else { return }
        let parsedGroupCipher = cipherName(Array(data[pos..<pos + 4]))
        pos += 4

        // Pairwise cipher count
        guard pos + 2 <= data.count else { return }
        let pairwiseCount = Int(UInt16(data[pos]) | (UInt16(data[pos+1]) << 8))
        pos += 2
        guard pairwiseCount > 0, pairwiseCount <= (data.count - pos) / 4 else { return }

        // Pairwise cipher suites
        var parsedPairwiseCiphers: [String] = []
        for _ in 0..<pairwiseCount {
            let name = cipherName(Array(data[pos..<pos + 4]))
            if !parsedPairwiseCiphers.contains(name) {
                parsedPairwiseCiphers.append(name)
            }
            pos += 4
        }

        // AKM count
        guard pos + 2 <= data.count else { return }
        let akmCount = Int(UInt16(data[pos]) | (UInt16(data[pos+1]) << 8))
        pos += 2
        guard akmCount > 0, akmCount <= (data.count - pos) / 4 else { return }

        // AKM suites
        var parsedAKMSuites: [String] = []
        var parsedSupportsWPA3 = false
        var parsedSupports80211r = false
        for _ in 0..<akmCount {
            let suite = Array(data[pos..<pos + 4])
            let name = akmSuiteName(suite)
            if !parsedAKMSuites.contains(name) {
                parsedAKMSuites.append(name)
            }
            if isWPA3AKM(suite) {
                parsedSupportsWPA3 = true
            }
            if isFastTransitionAKM(suite) {
                parsedSupports80211r = true
            }
            pos += 4
        }

        // PMF (802.11w) capabilities
        var parsedSupports80211w: Bool?
        if pos + 2 <= data.count {
            let rsnCap = UInt16(data[pos]) | (UInt16(data[pos+1]) << 8)
            // PMF required: bit 6, PMF capable: bit 7
            parsedSupports80211w = (rsnCap & (1 << 7)) != 0
        }

        result.groupCipher = parsedGroupCipher
        for cipher in parsedPairwiseCiphers where !result.pairwiseCiphers.contains(cipher) {
            result.pairwiseCiphers.append(cipher)
        }
        for suite in parsedAKMSuites where !result.akmSuites.contains(suite) {
            result.akmSuites.append(suite)
        }
        result.supportsWPA3 = result.supportsWPA3 || parsedSupportsWPA3
        result.supports80211r = result.supports80211r || parsedSupports80211r
        if let parsedSupports80211w {
            result.supports80211w = parsedSupports80211w
        }
    }

    // MARK: - Extended Capabilities

    private static func parseExtendedCapabilities(_ data: [UInt8], into result: inout IEData) {
        // Each byte holds 8 bits (bit 0 = LSB)

        func isSet(_ bit: Int) -> Bool {
            let byteIdx = bit / 8
            let bitInByte = bit % 8
            guard byteIdx < data.count else { return false }
            return (data[byteIdx] & (1 << bitInByte)) != 0
        }

        // Extended Capabilities currently contributes only 802.11v.
        // 802.11k comes from the RRM Enabled Capabilities IE and 802.11r
        // comes from Mobility Domain or FT AKM sources.
        result.supports80211v = isSet(extCapBit_BSS_Transition)
    }

    // MARK: - Helpers

    private static func maxMCSSpatialStreams(_ mcsBytes: [UInt8]) -> (mcs: Int?, streams: Int?) {
        // Only the normal HT MCS 0...31 range maps cleanly to the compact
        // per-stream UI model. MCS 32 and higher use encodings this model does
        // not represent, so ignore them instead of guessing an NSS.
        var highestGlobal = -1
        for byteIndex in 0..<min(mcsBytes.count, 4) {
            let byte = mcsBytes[byteIndex]
            for bit in 0..<8 where (byte & (1 << bit)) != 0 {
                highestGlobal = max(highestGlobal, byteIndex * 8 + bit)
            }
        }

        guard highestGlobal >= 0 else { return (mcs: nil, streams: nil) }

        let streams: Int
        switch highestGlobal {
        case 0...7:   streams = 1
        case 8...15:  streams = 2
        case 16...23: streams = 3
        case 24...31: streams = 4
        default:      return (mcs: nil, streams: nil)
        }

        return (mcs: highestGlobal % 8, streams: streams)
    }

    private static func isRSNSuite(_ suite: [UInt8]) -> Bool {
        suite.count == 4
            && suite[0] == rsnOUI[0]
            && suite[1] == rsnOUI[1]
            && suite[2] == rsnOUI[2]
    }

    private static func cipherName(_ suite: [UInt8]) -> String {
        guard isRSNSuite(suite) else { return "Unknown" }
        switch suite[3] {
        case 0x00: return "None"
        case 0x01: return "WEP-40"
        case 0x02: return "TKIP"
        case 0x04: return "CCMP (AES)"
        case 0x05: return "WEP-104"
        case 0x06: return "BIP-CMAC-128"
        case 0x07: return "No Group Addressed"
        case 0x08: return "GCMP-128"
        case 0x09: return "GCMP-256"
        case 0x0A: return "CCMP-256"
        case 0x0B: return "BIP-GMAC-128"
        case 0x0C: return "BIP-GMAC-256"
        case 0x0D: return "BIP-CMAC-256"
        default: return "Unknown"
        }
    }

    private static func akmSuiteName(_ suite: [UInt8]) -> String {
        guard isRSNSuite(suite) else { return "Unknown" }
        switch suite[3] {
        case 0x01: return "802.1X"
        case 0x02: return "PSK"
        case 0x03: return "FT/802.1X"
        case 0x04: return "FT/PSK"
        case 0x05: return "802.1X-SHA256"
        case 0x06: return "PSK-SHA256"
        case 0x07: return "TDLS"
        case 0x08: return "SAE"
        case 0x09: return "FT-SAE"
        case 0x0A: return "AP PeerKey"
        case 0x0B: return "802.1X-Suite-B"
        case 0x0C: return "802.1X-Suite-B-192"
        case 0x0D: return "FT/802.1X-SHA384"
        case 0x0E: return "FILS-SHA256"
        case 0x0F: return "FILS-SHA384"
        case 0x10: return "FT-FILS-SHA256"
        case 0x11: return "FT-FILS-SHA384"
        case 0x12: return "OWE"
        default: return "Unknown"
        }
    }

    private static func isWPA3AKM(_ suite: [UInt8]) -> Bool {
        guard isRSNSuite(suite) else { return false }
        switch suite[3] {
        case 0x08, 0x09, 0x0C:
            return true
        default:
            return false
        }
    }

    private static func isFastTransitionAKM(_ suite: [UInt8]) -> Bool {
        guard isRSNSuite(suite) else { return false }
        switch suite[3] {
        case 0x03, 0x04, 0x09, 0x0D, 0x10, 0x11:
            return true
        default:
            return false
        }
    }
}
