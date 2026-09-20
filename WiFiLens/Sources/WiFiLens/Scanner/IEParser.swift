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
    var maxVHTMCSIndex: Int?
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

        // WPA3 variants
        let wpa3Suites = akmSuites.filter { $0.contains("WPA3") }
        if !wpa3Suites.isEmpty {
            labels.append(wpa3Suites.joined(separator: "/"))
        }

        // WPA2 variants (excluding WPA3)
        let wpa2Suites = akmSuites.filter { !$0.contains("WPA3") && ($0.contains("WPA2") || $0.contains("802.1X") || $0.contains("PSK") || $0.contains("FT/") || $0.contains("SHA256") || $0.contains("SuiteB")) }
        if !wpa2Suites.isEmpty {
            labels.append(wpa2Suites.joined(separator: "/"))
        }

        // WPA (legacy)
        let wpaSuites = akmSuites.filter { $0 == "WPA" }
        if !wpaSuites.isEmpty {
            labels.append("WPA")
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

    /// MCS summary: e.g. "7" or "9" (VHT)
    var mcsSummary: String {
        if let vht = maxVHTMCSIndex { return "\(vht)" }
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
    private static let tagHECapabilities: UInt8 = 255  // vendor-specific with WFA OUI

    // Extended Capabilities bit positions (within the IE data bytes)
    // Bit numbering follows 802.11: bit 0 is LSB of byte 0
    private static let extCapBit_BSS_Transition: Int = 19     // 802.11v
    private static let extCapBit_RM_Capable: Int = 32          // 802.11k
    private static let extCapBit_FT_Over_DS: Int = 5           // 802.11r

    // RSN AKM Suite OUI values
    private static let akmSuiteWPA: [UInt8] = [0x00, 0x50, 0xF2, 0x01]
    private static let akmSuiteWPA2: [UInt8] = [0x00, 0x50, 0xF2, 0x02]
    private static let akmSuiteFT8021X: [UInt8] = [0x00, 0x50, 0xF2, 0x03]
    private static let akmSuiteFTPSK: [UInt8] = [0x00, 0x50, 0xF2, 0x04]
    private static let akmSuiteSAE: [UInt8] = [0x00, 0x50, 0xF2, 0x08]      // WPA3
    private static let akmSuiteFT_SAE: [UInt8] = [0x00, 0x50, 0xF2, 0x09]   // WPA3
    private static let akmSuiteOWE: [UInt8] = [0x00, 0x50, 0xF2, 0x12]

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
                result.htSupported = true
                parseHTCapabilities(ieData, into: &result)

            case tagVHTCapabilities:
                result.vhtSupported = true
                // VHT MCS/NSS from CoreWLAN's IE data is unreliable — the
                // MCS Map bytes are replaced with fixed markers.  We rely on
                // HT MCS (which is always present on VHT APs for backwards
                // compatibility) instead of calling parseVHTCapabilities.

            case tagHTOperation:
                parseHTOperation(ieData, into: &result)

            case tagVHTOperation:
                parseVHTOperation(ieData, into: &result)

            case tagRSN:
                parseRSN(ieData, into: &result)

            case tagExtendedCapabilities:
                parseExtendedCapabilities(ieData, into: &result)

            case tagRMEnabled:
                result.supports80211k = true

            case tagMobilityDomain:
                // If Mobility Domain IE is present, 802.11r FT is active
                if length >= 2 {
                    result.supports80211r = true
                }

            case tagHECapabilities:
                // HE Capabilities is vendor-specific with WFA OUI
                if length >= 7 && ieData[0] == 0x00 && ieData[1] == 0x0F && ieData[2] == 0xAC {
                    // WFA OUI, element ID 0x06 = HE Capabilities
                    // The actual HE capabilities start after the vendor header
                    if ieData[3] == 0x06 {
                        result.heSupported = true
                    }
                }

            default:
                break
            }

            offset += length
        }

        // If we have FT AKMs (FT over 802.1X or FT PSK), 802.11r is supported
        if result.akmSuites.contains("FT/802.1X") || result.akmSuites.contains("FT/PSK") {
            result.supports80211r = true
        }

        return result
    }

    // MARK: - HT Capabilities (802.11n)

    private static func parseHTCapabilities(_ data: [UInt8], into result: inout IEData) {
        guard data.count >= 2 else { return }
        let htCapInfo = (UInt16(data[0]) | (UInt16(data[1]) << 8))

        // Channel width: bit 1
        result.supports40MHz = (htCapInfo & (1 << 1)) != 0

        // HT Cap body: Info(2) + A-MPDU(1) = 3 bytes → Supported MCS Set at offset 3.
        // Rx MCS Bitmask occupies the first 10 bytes of the MCS Set (bits 0–79).
        if data.count >= 13 {
            let mcsBytes = Array(data[3..<min(13, data.count)])
            result.maxMCSIndex = maxMCSSpatialStreams(mcsBytes).mcs
            result.spatialStreams = maxMCSSpatialStreams(mcsBytes).streams
        }
    }

    private static func parseHTOperation(_ data: [UInt8], into result: inout IEData) {
        // Byte 0 is the primary channel. Byte 1's HT Operation Information
        // subset carries both the secondary channel offset (bits 0–1) and the
        // STA Channel Width flag (bit 2). An offset of 1 or 3 is an active
        // HT40 secondary channel only when that flag is set; otherwise the
        // operation is explicitly 20 MHz.
        guard data.count >= 2 else { return }
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

    // MARK: - VHT Capabilities (802.11ac)

    private static func parseVHTCapabilities(_ data: [UInt8], into result: inout IEData) {
        guard data.count >= 4 else { return }
        // Max MPDU length, channel width, etc. are in VHT Cap Info
        // For this implementation, we infer channel width from VHT Operation IE

        // Rx VHT-MCS Map (starts at byte 4, after 4-byte VHT Cap Info)
        if data.count >= 6 {
            let vhtMCS = maxVHTMCS(data)
            result.maxVHTMCSIndex = vhtMCS.mcs
            if vhtMCS.streams > (result.spatialStreams ?? 0) {
                result.spatialStreams = vhtMCS.streams
            }
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
            guard segment1 != 0 else {
                result.vhtChannelOperation = .eightyMHz
                return
            }

            let segmentDifference = abs(segment1 - segment0)
            if segmentDifference == 8 {
                result.vhtChannelOperation = .oneSixtyMHz
            } else if segmentDifference > 8 {
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

    // MARK: - RSN (WPA2/WPA3)

    private static func parseRSN(_ data: [UInt8], into result: inout IEData) {
        guard data.count >= 2 else { return }
        var pos = 2

        // Group cipher suite
        if pos + 4 <= data.count {
            result.groupCipher = cipherName(Array(data[pos..<pos+4]))
            pos += 4
        }

        // Pairwise cipher count
        guard pos + 2 <= data.count else { return }
        let pairwiseCount = Int(UInt16(data[pos]) | (UInt16(data[pos+1]) << 8))
        pos += 2

        // Pairwise cipher suites
        for _ in 0..<pairwiseCount {
            guard pos + 4 <= data.count else { break }
            let name = cipherName(Array(data[pos..<pos+4]))
            if !result.pairwiseCiphers.contains(name) {
                result.pairwiseCiphers.append(name)
            }
            pos += 4
        }

        // AKM count
        guard pos + 2 <= data.count else { return }
        let akmCount = Int(UInt16(data[pos]) | (UInt16(data[pos+1]) << 8))
        pos += 2

        // AKM suites
        for _ in 0..<akmCount {
            guard pos + 4 <= data.count else { break }
            let suite = Array(data[pos..<pos+4])
            let name = akmSuiteName(suite)
            if !result.akmSuites.contains(name) {
                result.akmSuites.append(name)
            }
            // Check for WPA3
            if suite == akmSuiteSAE || suite == akmSuiteFT_SAE {
                result.supportsWPA3 = true
            }
            // Check for 802.11r (FT)
            if suite == akmSuiteFT8021X || suite == akmSuiteFTPSK || suite == akmSuiteFT_SAE {
                result.supports80211r = true
            }
            pos += 4
        }

        // PMF (802.11w) capabilities
        if pos + 2 <= data.count {
            let rsnCap = UInt16(data[pos]) | (UInt16(data[pos+1]) << 8)
            // PMF required: bit 6, PMF capable: bit 7
            result.supports80211w = (rsnCap & (1 << 7)) != 0
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

        // 802.11v: BSS Transition bit (19)
        result.supports80211v = isSet(19)

        // 802.11k: RM Capable bit (32)
        if isSet(32) { result.supports80211k = true }

        // 802.11r: FT over DS (5) — complement to FT AKM in RSN
        if isSet(5) { result.supports80211r = true }
    }

    // MARK: - Helpers

    private static func maxMCSSpatialStreams(_ mcsBytes: [UInt8]) -> (mcs: Int, streams: Int) {
        // HT Rx MCS bitmask: 77 bits across 10 bytes.
        // Find the highest supported global MCS index, then derive per-stream
        // MCS (0–7) and spatial-stream count from it.
        var highestGlobal = -1
        for byteIndex in 0..<mcsBytes.count {
            let byte = mcsBytes[byteIndex]
            if byte == 0 { continue }
            for bit in 0..<8 {
                let global = byteIndex * 8 + bit
                if global > 76 { break }
                if (byte & (1 << bit)) != 0 {
                    highestGlobal = max(highestGlobal, global)
                }
            }
        }

        guard highestGlobal >= 0 else { return (mcs: 0, streams: 0) }

        // Number of spatial streams for equal-modulation MCS (0–31)
        let ss: Int
        switch highestGlobal {
        case 0...7:   ss = 1
        case 8...15:  ss = 2
        case 16...23: ss = 3
        case 24...31: ss = 4
        default:      ss = min(highestGlobal / 8 + 1, 4)
        }

        return (mcs: highestGlobal % 8, streams: ss)
    }

    private static func maxVHTMCS(_ data: [UInt8]) -> (mcs: Int?, streams: Int) {
        // VHT Capabilities Info is 4 bytes (data[0..3]).
        // Rx VHT-MCS Map is 2 bytes at data[4..5]: 2 bits per stream (0=not supported,
        // 1=MCS 0–7, 2=MCS 0–8, 3=MCS 0–9).
        guard data.count >= 6 else { return (nil, 0) }
        let rxMcsMap = UInt16(data[4]) | (UInt16(data[5]) << 8)

        // First pass: find the maximum MCS level across all streams.
        var maxMCS = 0
        for stream in 0..<8 {
            let mcsField = (rxMcsMap >> (stream * 2)) & 0x03
            if mcsField > 0 {
                maxMCS = max(maxMCS, 6 + Int(mcsField))  // 1→7, 2→8, 3→9
            }
        }
        guard maxMCS > 0 else { return (nil, 0) }

        // Second pass: count streams that support the max MCS level.
        let requiredField = maxMCS - 6  // 7→1, 8→2, 9→3
        var maxStreams = 0
        for stream in 0..<8 {
            let mcsField = (rxMcsMap >> (stream * 2)) & 0x03
            if mcsField >= requiredField {
                maxStreams = stream + 1
            }
        }
        return (mcs: maxMCS, streams: maxStreams)
    }

    /// Returns true if `suite` starts with a known Wi‑Fi Alliance OUI.
    private static func isWFA(_ suite: [UInt8]) -> Bool {
        suite.count == 4
            && suite[0] == 0x00
            && ((suite[1] == 0x0F && suite[2] == 0xAC)   // WFA OUI (common)
                || (suite[1] == 0x50 && suite[2] == 0xF2)) // WFA OUI (legacy)
    }

    private static func cipherName(_ suite: [UInt8]) -> String {
        guard isWFA(suite) else { return "Unknown" }
        switch suite[3] {
        case 0x02: return "TKIP"
        case 0x04: return "CCMP (AES)"
        case 0x05: return "WEP-104"
        case 0x06: return "BIP-CMAC"
        case 0x07: return "GCMP-128"
        case 0x08: return "GCMP-256"
        case 0x09: return "CCMP-256"
        case 0x0A: return "BIP-GMAC-128"
        case 0x0B: return "BIP-GMAC-256"
        case 0x0C: return "BIP-CMAC-256"
        default: return "Unknown"
        }
    }

    private static func akmSuiteName(_ suite: [UInt8]) -> String {
        guard isWFA(suite) else { return "Unknown" }
        let isLegacy = suite[1] == 0x50 && suite[2] == 0xF2
        switch suite[3] {
        case 0x01: return isLegacy ? "WPA" : "802.1X"
        case 0x02: return isLegacy ? "WPA2" : "PSK"
        case 0x03: return "FT/802.1X"
        case 0x04: return "FT/PSK"
        case 0x05: return isLegacy ? "WPA2-SHA256" : "WPA2"
        case 0x06: return isLegacy ? "PSK-SHA256" : "PSK-SHA256"
        case 0x07: return "TDLS"
        case 0x08: return "SAE (WPA3)"
        case 0x09: return "FT-SAE (WPA3)"
        case 0x0A: return "AP PeerKey"
        case 0x0B: return "WPA2-SuiteB"
        case 0x0C: return "WPA2-SuiteB"
        case 0x12: return "OWE"
        default: return "Unknown"
        }
    }
}
