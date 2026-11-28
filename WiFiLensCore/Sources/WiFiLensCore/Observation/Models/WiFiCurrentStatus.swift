import Foundation
import WiFiLensCoreRust

public enum WiFiModeEvidence: Equatable, Sendable {
    case station
    /// CoreWLAN explicitly reported no mode. This is distinct from the legacy
    /// combined value, which remains ambiguous for source compatibility.
    case none
    case noneOrReadFailure
    case other(rawValue: Int)
    case unavailable
}

public enum WiFiRadioEvidence: Equatable, Sendable {
    case reportedOn
    /// Explicitly confirmed by a CoreWLAN power-change event and an independent
    /// SystemConfiguration link-down read in the same sample.
    case reportedOff
    case reportedOffOrReadFailure
    case unavailable
}

public enum WiFiLinkEvidenceSource: String, Equatable, Sendable {
    case coreWLAN
    case systemConfiguration
    case getifaddrs
}

public enum WiFiLinkEvidenceField: String, Equatable, Sendable {
    case interfaceDiscovery
    case mode
    case radio
    case linkActive
    case serviceActive
    case linkDetaching
    case interfaceFlags
    case ssid
    case bssid
}

public enum WiFiLinkEvidenceReadFailure: String, Equatable, Sendable {
    case unavailable
    case missingValue
    case apiReturnedNoValue
    case interfaceNotFound
    case enumerationFailed
}

public struct WiFiLinkRawEvidence: Equatable, Sendable {
    public let snapshotCycleID: UUID
    public let capturedAt: Date
    public let interfaceName: String
    public let mode: WiFiModeEvidence
    /// CoreWLAN's raw mode value, preserved even when its interpretation is ambiguous.
    public let coreWLANModeRawValue: Int?
    public let radio: WiFiRadioEvidence
    public let linkActive: Bool?
    public let ssid: String?
    public let bssid: String?
    public let modeSource: WiFiLinkEvidenceSource
    public let radioSource: WiFiLinkEvidenceSource
    public let linkSource: WiFiLinkEvidenceSource?
    public let serviceActiveSource: WiFiLinkEvidenceSource?
    public let linkDetachingSource: WiFiLinkEvidenceSource?
    public let interfaceFlagsSource: WiFiLinkEvidenceSource?
    public let interfaceIndex: UInt32?
    /// The raw CoreWLAN `powerOn()` result when the interface was readable.
    /// A false value remains ambiguous and is never interpreted as a confirmed fault.
    public let radioPowerOnRaw: Bool?
    public let serviceActive: Bool?
    public let linkDetaching: Bool?
    public let interfaceFlagsUp: Bool?
    public let interfaceFlagsRunning: Bool?
    public let captureStartedAt: Date
    public let captureEndedAt: Date
    public let readFailures: [WiFiLinkEvidenceField: WiFiLinkEvidenceReadFailure]

    public init(
        snapshotCycleID: UUID,
        capturedAt: Date,
        interfaceName: String,
        mode: WiFiModeEvidence,
        coreWLANModeRawValue: Int? = nil,
        radio: WiFiRadioEvidence,
        linkActive: Bool? = nil,
        ssid: String? = nil,
        bssid: String? = nil,
        modeSource: WiFiLinkEvidenceSource = .coreWLAN,
        radioSource: WiFiLinkEvidenceSource = .coreWLAN,
        linkSource: WiFiLinkEvidenceSource? = nil,
        serviceActiveSource: WiFiLinkEvidenceSource? = nil,
        linkDetachingSource: WiFiLinkEvidenceSource? = nil,
        interfaceFlagsSource: WiFiLinkEvidenceSource? = nil,
        interfaceIndex: UInt32? = nil,
        radioPowerOnRaw: Bool? = nil,
        serviceActive: Bool? = nil,
        linkDetaching: Bool? = nil,
        interfaceFlagsUp: Bool? = nil,
        interfaceFlagsRunning: Bool? = nil,
        captureStartedAt: Date? = nil,
        captureEndedAt: Date? = nil,
        readFailures: [WiFiLinkEvidenceField: WiFiLinkEvidenceReadFailure] = [:]
    ) {
        self.snapshotCycleID = snapshotCycleID
        self.capturedAt = capturedAt
        self.interfaceName = interfaceName
        self.mode = mode
        self.coreWLANModeRawValue = coreWLANModeRawValue
        self.radio = radio
        self.linkActive = linkActive
        self.ssid = ssid
        self.bssid = bssid
        self.modeSource = modeSource
        self.radioSource = radioSource
        self.linkSource = linkSource
        self.serviceActiveSource = serviceActiveSource
        self.linkDetachingSource = linkDetachingSource
        self.interfaceFlagsSource = interfaceFlagsSource
        self.interfaceIndex = interfaceIndex
        self.radioPowerOnRaw = radioPowerOnRaw
        self.serviceActive = serviceActive
        self.linkDetaching = linkDetaching
        self.interfaceFlagsUp = interfaceFlagsUp
        self.interfaceFlagsRunning = interfaceFlagsRunning
        self.captureStartedAt = captureStartedAt ?? capturedAt
        self.captureEndedAt = captureEndedAt ?? capturedAt
        self.readFailures = readFailures
    }
}

public enum VerifiedWiFiLinkState: String, Equatable, Sendable {
    case associated
    case disconnected
    case unknown
}

public enum WiFiLinkEvidenceReason: String, Equatable, Sendable {
    case stationMode
    case cycleMismatch
    case radioUnavailable
    case modeUnavailable
    case unsupportedMode
    case interfaceEnumerationFailed
    case interfaceDiscoveryUnavailable
    case interfaceUnavailable
    case captureTimestampMismatch
    case linkStateUnavailable
    case conflictingLinkEvidence
    case disconnectCandidate
    case disconnectEvidenceNotValidated
    case samplingContinuityLost
}

public struct WiFiLinkAssessment: Equatable, Sendable {
    public let state: VerifiedWiFiLinkState
    public let reason: WiFiLinkEvidenceReason
    public let candidateState: VerifiedWiFiLinkState?

    public init(
        state: VerifiedWiFiLinkState,
        reason: WiFiLinkEvidenceReason,
        candidateState: VerifiedWiFiLinkState? = nil
    ) {
        self.state = state
        self.reason = reason
        self.candidateState = candidateState
    }
}

public enum WiFiLinkInterpreter {
    public static func evaluate(
        _ evidence: WiFiLinkRawEvidence?,
        expectedCycleID: UUID,
        expectedCapturedAt: Date? = nil
    ) -> WiFiLinkAssessment {
        var flags: UInt32 = 0
        var mode = WIFI_LENS_LINK_MODE_UNAVAILABLE
        var coreWLANModeRawValue: Int64 = 0
        var otherModeRawValue: Int64 = 0
        var radio = WIFI_LENS_LINK_RADIO_UNAVAILABLE
        var linkActive = WIFI_LENS_LINK_ACTIVE_UNAVAILABLE

        if let evidence {
            flags |= WIFI_LENS_LINK_HAS_EVIDENCE
            if evidence.snapshotCycleID == expectedCycleID {
                flags |= WIFI_LENS_LINK_CYCLE_MATCHES
            }
            if expectedCapturedAt.map({ evidence.capturedAt == $0 }) ?? true {
                flags |= WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES
            }
            if evidence.captureStartedAt <= evidence.capturedAt,
                evidence.capturedAt <= evidence.captureEndedAt
            {
                flags |= WIFI_LENS_LINK_CAPTURE_WINDOW_VALID
            }
            if let rawValue = evidence.coreWLANModeRawValue {
                flags |= WIFI_LENS_LINK_HAS_CORE_WLAN_MODE
                coreWLANModeRawValue = Int64(rawValue)
            }
            if let rawValue = evidence.radioPowerOnRaw {
                flags |= WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW
                if rawValue {
                    flags |= WIFI_LENS_LINK_RADIO_POWER_ON_RAW
                }
            }
            if !evidence.interfaceName.isEmpty {
                flags |= WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY
            }
            if case .other(let rawValue) = evidence.mode {
                otherModeRawValue = Int64(rawValue)
            }
            mode =
                switch evidence.mode {
                case .station: WIFI_LENS_LINK_MODE_STATION
                case .none: WIFI_LENS_LINK_MODE_NONE
                case .noneOrReadFailure: WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE
                case .other: WIFI_LENS_LINK_MODE_OTHER
                case .unavailable: WIFI_LENS_LINK_MODE_UNAVAILABLE
                }
            radio =
                switch evidence.radio {
                case .reportedOn: WIFI_LENS_LINK_RADIO_REPORTED_ON
                case .reportedOff: WIFI_LENS_LINK_RADIO_REPORTED_OFF
                case .reportedOffOrReadFailure: WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE
                case .unavailable: WIFI_LENS_LINK_RADIO_UNAVAILABLE
                }
            linkActive =
                switch evidence.linkActive {
                case true: WIFI_LENS_LINK_ACTIVE
                case false: WIFI_LENS_LINK_INACTIVE
                case nil: WIFI_LENS_LINK_ACTIVE_UNAVAILABLE
                }
        }

        let input = WiFiLensLinkEvidenceInput(
            flags: flags,
            mode: mode,
            core_wlan_mode_raw_value: coreWLANModeRawValue,
            other_mode_raw_value: otherModeRawValue,
            radio: radio,
            link_active: linkActive
        )
        var output = WiFiLensLinkEvidenceResult()
        let status = withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                wifi_lens_interpret_link_evidence(inputPointer, outputPointer)
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust link evidence interpreter returned status \(status)")
            return WiFiLinkAssessment(state: .unknown, reason: .conflictingLinkEvidence)
        }

        let state: VerifiedWiFiLinkState =
            switch output.state {
            case WIFI_LENS_LINK_STATE_ASSOCIATED: .associated
            case WIFI_LENS_LINK_STATE_DISCONNECTED: .disconnected
            default: .unknown
            }
        let reason: WiFiLinkEvidenceReason =
            switch output.reason {
            case WIFI_LENS_LINK_REASON_STATION_MODE: .stationMode
            case WIFI_LENS_LINK_REASON_CYCLE_MISMATCH: .cycleMismatch
            case WIFI_LENS_LINK_REASON_RADIO_UNAVAILABLE: .radioUnavailable
            case WIFI_LENS_LINK_REASON_MODE_UNAVAILABLE: .modeUnavailable
            case WIFI_LENS_LINK_REASON_UNSUPPORTED_MODE: .unsupportedMode
            case WIFI_LENS_LINK_REASON_CAPTURE_TIMESTAMP_MISMATCH: .captureTimestampMismatch
            case WIFI_LENS_LINK_REASON_LINK_STATE_UNAVAILABLE: .linkStateUnavailable
            case WIFI_LENS_LINK_REASON_CONFLICTING_LINK_EVIDENCE: .conflictingLinkEvidence
            case WIFI_LENS_LINK_REASON_DISCONNECT_CANDIDATE: .disconnectCandidate
            default: .conflictingLinkEvidence
            }
        let candidateState: VerifiedWiFiLinkState? =
            switch output.candidate_state {
            case WIFI_LENS_LINK_CANDIDATE_DISCONNECTED: .disconnected
            default: nil
            }
        return WiFiLinkAssessment(state: state, reason: reason, candidateState: candidateState)
    }
}

public struct WiFiCurrentStatus: Equatable, Sendable {
    public init(
        timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil,
        interfaceIndex: UInt32? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil,
        band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil,
        security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool,
        linkEvidence: WiFiLinkRawEvidence? = nil, linkAssessment: WiFiLinkAssessment? = nil,
        metricsAttribution: WiFiMetricsAttribution = .unverified
    ) {
        self.init(
            timestamp: timestamp, interfaceSnapshotCycleID: interfaceSnapshotCycleID, interfaceName: interfaceName,
            interfaceIndex: interfaceIndex, ssid: ssid, bssid: bssid, channel: channel, band: band, rssi: rssi,
            noise: noise, txRate: txRate, phyMode: phyMode, security: security, routerIP: routerIP,
            isConnected: isConnected, isWiFiPowerOn: isWiFiPowerOn, error: nil, linkEvidence: linkEvidence,
            linkAssessment: linkAssessment, metricsAttribution: metricsAttribution)
    }

    init(
        timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil,
        interfaceIndex: UInt32? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil,
        band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil,
        security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool,
        error: WiFiObservationError?, linkEvidence: WiFiLinkRawEvidence? = nil,
        linkAssessment: WiFiLinkAssessment? = nil, metricsAttribution: WiFiMetricsAttribution = .unverified
    ) {
        self.timestamp = timestamp
        self.interfaceSnapshotCycleID = interfaceSnapshotCycleID
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.band = band
        self.rssi = rssi
        self.noise = noise
        self.txRate = txRate
        self.phyMode = phyMode
        self.security = security
        self.routerIP = routerIP
        self.isConnected = isConnected
        self.isWiFiPowerOn = isWiFiPowerOn
        self.error = error
        self.linkEvidence = linkEvidence
        self.linkAssessment = linkAssessment
        self.metricsAttribution = metricsAttribution
    }
    public var timestamp: Date
    public var interfaceSnapshotCycleID: UUID? = nil
    public var interfaceName: String?
    public var interfaceIndex: UInt32?
    public var ssid: String?
    public var bssid: String?
    public var channel: Int?
    public var band: ChannelBand?
    public var rssi: Int?
    public var noise: Int?
    public var txRate: Double?
    public var phyMode: String?
    public var security: String?
    public var routerIP: String?
    public var isConnected: Bool
    public var isWiFiPowerOn: Bool
    public var linkEvidence: WiFiLinkRawEvidence?
    public var linkAssessment: WiFiLinkAssessment?
    public var metricsAttribution: WiFiMetricsAttribution = .unverified
    var error: WiFiObservationError?
}

/// Validates that a status and its raw link evidence describe the same
/// interface snapshot before a consumer uses the interpreted link state.
public enum WiFiLinkEvidenceValidator {
    public static func assessment(for status: WiFiCurrentStatus) -> WiFiLinkAssessment? {
        guard let cycleID = status.interfaceSnapshotCycleID,
            let interfaceName = status.interfaceName,
            let evidence = status.linkEvidence,
            evidence.snapshotCycleID == cycleID,
            evidence.capturedAt == status.timestamp,
            evidence.interfaceName == interfaceName,
            evidence.ssid == status.ssid,
            evidence.bssid == status.bssid,
            indexesMatch(evidence.interfaceIndex, status.interfaceIndex)
        else {
            return nil
        }

        let interpreted = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: cycleID,
            expectedCapturedAt: status.timestamp
        )
        guard interpreted == status.linkAssessment else { return nil }
        return interpreted
    }

    private static func indexesMatch(_ evidenceIndex: UInt32?, _ statusIndex: UInt32?) -> Bool {
        guard let evidenceIndex, evidenceIndex != 0,
            let statusIndex, statusIndex != 0
        else { return true }
        return evidenceIndex == statusIndex
    }
}
