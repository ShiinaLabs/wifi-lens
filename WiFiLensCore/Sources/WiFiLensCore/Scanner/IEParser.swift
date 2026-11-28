import Foundation
import WiFiLensCoreRust

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
    var ehtSupported: Bool = false  // 802.11be / Wi-Fi 7

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
        let wpa3Suites =
            akmSuites
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

        let joined =
            labels.isEmpty
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
    static func parse(data: Data) -> IEData {
        var result = WiFiLensIEParseResult()
        var akmSuites = [WiFiLensIEStringRange](
            repeating: WiFiLensIEStringRange(),
            count: Int(WIFI_LENS_IE_MAX_SUITES)
        )
        var pairwiseCiphers = [WiFiLensIEStringRange](
            repeating: WiFiLensIEStringRange(),
            count: Int(WIFI_LENS_IE_MAX_SUITES)
        )
        var text = [UInt8](repeating: 0, count: Int(WIFI_LENS_IE_MAX_TEXT_BYTES))
        var akmCount = 0
        var pairwiseCount = 0
        var textLength = 0

        let status = data.withUnsafeBytes { bytes in
            akmSuites.withUnsafeMutableBufferPointer { akmBuffer in
                pairwiseCiphers.withUnsafeMutableBufferPointer { cipherBuffer in
                    text.withUnsafeMutableBufferPointer { textBuffer in
                        wifi_lens_parse_information_elements(
                            bytes.bindMemory(to: UInt8.self).baseAddress,
                            bytes.count,
                            &result,
                            akmBuffer.baseAddress,
                            akmBuffer.count,
                            &akmCount,
                            cipherBuffer.baseAddress,
                            cipherBuffer.count,
                            &pairwiseCount,
                            textBuffer.baseAddress,
                            textBuffer.count,
                            &textLength
                        )
                    }
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK,
            akmCount <= akmSuites.count,
            pairwiseCount <= pairwiseCiphers.count,
            textLength <= text.count
        else {
            assertionFailure("Rust information element parser returned status \(status)")
            return IEData()
        }

        var parsed = IEData()
        parsed.supports80211k = result.flags & WIFI_LENS_IE_SUPPORTS_80211K != 0
        parsed.supports80211r = result.flags & WIFI_LENS_IE_SUPPORTS_80211R != 0
        parsed.supports80211v = result.flags & WIFI_LENS_IE_SUPPORTS_80211V != 0
        parsed.supports80211w = result.flags & WIFI_LENS_IE_SUPPORTS_80211W != 0
        parsed.supportsWPA3 = result.flags & WIFI_LENS_IE_SUPPORTS_WPA3 != 0
        parsed.htSupported = result.flags & WIFI_LENS_IE_HT_SUPPORTED != 0
        parsed.vhtSupported = result.flags & WIFI_LENS_IE_VHT_SUPPORTED != 0
        parsed.heSupported = result.flags & WIFI_LENS_IE_HE_SUPPORTED != 0
        parsed.ehtSupported = result.flags & WIFI_LENS_IE_EHT_SUPPORTED != 0
        parsed.supports40MHz = result.flags & WIFI_LENS_IE_SUPPORTS_40_MHZ != 0
        parsed.isHiddenSSID = result.flags & WIFI_LENS_IE_HIDDEN_SSID != 0

        if result.flags & WIFI_LENS_IE_HAS_COUNTRY_CODE != 0 {
            let country = result.country_code
            parsed.countryCode = String(
                bytes: [UInt8((country >> 16) & 0xff), UInt8((country >> 8) & 0xff), UInt8(country & 0xff)],
                encoding: .ascii
            )
        }
        if result.flags & WIFI_LENS_IE_HAS_GROUP_CIPHER != 0 {
            parsed.groupCipher = string(in: text, offset: result.group_cipher_offset, length: result.group_cipher_length)
        }

        parsed.htChannelOperation = switch result.ht_channel_operation {
        case 0: .twentyMHz
        case 1: .fortyMHzAbove
        case 2: .fortyMHzBelow
        default: nil
        }
        parsed.vhtChannelOperation = switch result.vht_channel_operation {
        case 0: .useHT
        case 1: .eightyMHz
        case 2: .oneSixtyMHz
        case 3: .eightyPlusEightyMHz
        default: nil
        }
        parsed.maxMCSIndex = result.max_mcs_index >= 0 ? Int(result.max_mcs_index) : nil
        parsed.spatialStreams = result.spatial_streams >= 0 ? Int(result.spatial_streams) : nil
        parsed.pairwiseCiphers = pairwiseCiphers.prefix(pairwiseCount).map { range in
            string(in: text, offset: range.offset, length: range.length)
        }
        parsed.akmSuites = akmSuites.prefix(akmCount).map { range in
            string(in: text, offset: range.offset, length: range.length)
        }
        return parsed
    }

    private static func string(in buffer: [UInt8], offset: Int, length: Int) -> String {
        String(decoding: buffer[offset..<(offset + length)], as: UTF8.self)
    }
}
