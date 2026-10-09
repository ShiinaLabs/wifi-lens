import Foundation

public enum WiFiModeEvidence: Equatable, Sendable {
    case station
    case noneOrReadFailure
    case other(rawValue: Int)
    case unavailable
}

public enum WiFiRadioEvidence: Equatable, Sendable {
    case reportedOn
    case reportedOffOrReadFailure
    case unavailable
}

public enum WiFiLinkEvidenceSource: String, Equatable, Sendable {
    case coreWLAN
    case systemConfiguration
}

public struct WiFiLinkRawEvidence: Equatable, Sendable {
    public let snapshotCycleID: UUID
    public let capturedAt: Date
    public let interfaceName: String
    public let mode: WiFiModeEvidence
    public let radio: WiFiRadioEvidence
    public let linkActive: Bool?
    public let ssid: String?
    public let bssid: String?
    public let modeSource: WiFiLinkEvidenceSource
    public let radioSource: WiFiLinkEvidenceSource
    public let linkSource: WiFiLinkEvidenceSource?

    public init(
        snapshotCycleID: UUID,
        capturedAt: Date,
        interfaceName: String,
        mode: WiFiModeEvidence,
        radio: WiFiRadioEvidence,
        linkActive: Bool? = nil,
        ssid: String? = nil,
        bssid: String? = nil,
        modeSource: WiFiLinkEvidenceSource = .coreWLAN,
        radioSource: WiFiLinkEvidenceSource = .coreWLAN,
        linkSource: WiFiLinkEvidenceSource? = nil
    ) {
        self.snapshotCycleID = snapshotCycleID
        self.capturedAt = capturedAt
        self.interfaceName = interfaceName
        self.mode = mode
        self.radio = radio
        self.linkActive = linkActive
        self.ssid = ssid
        self.bssid = bssid
        self.modeSource = modeSource
        self.radioSource = radioSource
        self.linkSource = linkSource
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
}

public struct WiFiLinkAssessment: Equatable, Sendable {
    public let state: VerifiedWiFiLinkState
    public let reason: WiFiLinkEvidenceReason

    public init(state: VerifiedWiFiLinkState, reason: WiFiLinkEvidenceReason) {
        self.state = state
        self.reason = reason
    }
}

public enum WiFiLinkInterpreter {
    public static func evaluate(
        _ evidence: WiFiLinkRawEvidence?,
        expectedCycleID: UUID,
        expectedCapturedAt: Date? = nil
    ) -> WiFiLinkAssessment {
        guard let evidence else {
            return WiFiLinkAssessment(state: .unknown, reason: .modeUnavailable)
        }
        guard evidence.snapshotCycleID == expectedCycleID else {
            return WiFiLinkAssessment(state: .unknown, reason: .cycleMismatch)
        }
        if let expectedCapturedAt, evidence.capturedAt != expectedCapturedAt {
            return WiFiLinkAssessment(state: .unknown, reason: .captureTimestampMismatch)
        }
        guard evidence.mode == .station else {
            if case .other = evidence.mode {
                return WiFiLinkAssessment(state: .unknown, reason: .unsupportedMode)
            }
            return WiFiLinkAssessment(state: .unknown, reason: .modeUnavailable)
        }
        guard evidence.radio == .reportedOn else {
            return WiFiLinkAssessment(state: .unknown, reason: .radioUnavailable)
        }
        switch evidence.linkActive {
        case true:
            return WiFiLinkAssessment(state: .associated, reason: .stationMode)
        case false:
            return WiFiLinkAssessment(state: .unknown, reason: .conflictingLinkEvidence)
        case nil:
            return WiFiLinkAssessment(state: .unknown, reason: .linkStateUnavailable)
        }
    }
}

public struct WiFiCurrentStatus: Equatable, Sendable {
    public init(timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil, interfaceIndex: UInt32? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil, band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil, security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool, linkEvidence: WiFiLinkRawEvidence? = nil, linkAssessment: WiFiLinkAssessment? = nil) {
        self.init(timestamp: timestamp, interfaceSnapshotCycleID: interfaceSnapshotCycleID, interfaceName: interfaceName, interfaceIndex: interfaceIndex, ssid: ssid, bssid: bssid, channel: channel, band: band, rssi: rssi, noise: noise, txRate: txRate, phyMode: phyMode, security: security, routerIP: routerIP, isConnected: isConnected, isWiFiPowerOn: isWiFiPowerOn, error: nil, linkEvidence: linkEvidence, linkAssessment: linkAssessment)
    }

    init(timestamp: Date, interfaceSnapshotCycleID: UUID? = nil, interfaceName: String? = nil, interfaceIndex: UInt32? = nil, ssid: String? = nil, bssid: String? = nil, channel: Int? = nil, band: ChannelBand? = nil, rssi: Int? = nil, noise: Int? = nil, txRate: Double? = nil, phyMode: String? = nil, security: String? = nil, routerIP: String? = nil, isConnected: Bool, isWiFiPowerOn: Bool, error: WiFiObservationError?, linkEvidence: WiFiLinkRawEvidence? = nil, linkAssessment: WiFiLinkAssessment? = nil) {
        self.timestamp = timestamp; self.interfaceSnapshotCycleID = interfaceSnapshotCycleID; self.interfaceName = interfaceName; self.interfaceIndex = interfaceIndex
        self.ssid = ssid; self.bssid = bssid; self.channel = channel; self.band = band; self.rssi = rssi; self.noise = noise
        self.txRate = txRate; self.phyMode = phyMode; self.security = security; self.routerIP = routerIP
        self.isConnected = isConnected; self.isWiFiPowerOn = isWiFiPowerOn; self.error = error
        self.linkEvidence = linkEvidence; self.linkAssessment = linkAssessment
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
    var error: WiFiObservationError?
}
