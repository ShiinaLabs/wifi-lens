import Foundation

/// One constrained, interface-bound gateway evidence attempt.
///
/// The sampler deliberately does not scan for nearby networks and does not
/// create an observation cycle. It captures the Wi-Fi interface snapshot,
/// confirms the association and gateway target, performs one bound probe, then
/// captures a second snapshot to verify that the attempt still belongs to the
/// same interface and network. Callers persist the returned immutable facts;
/// they must not reinterpret an unattributed attempt as a network response.
public protocol WiFiGatewayEvidenceSampling: Sendable {
    func sample() async -> WiFiGatewayEvidenceSample
}

/// The interface and link identity observed on one side of a probe attempt.
public struct WiFiGatewayEvidenceIdentity: Equatable, Sendable {
    public let snapshotCycleID: UUID?
    public let interfaceName: String?
    public let interfaceIndex: UInt32?
    public let routerIP: String?
    public let ssid: String?
    public let bssid: String?
    public let linkState: VerifiedWiFiLinkState?
    public let linkRunSessionID: UUID?
    public let linkSequence: UInt64?
    public let linkEpoch: UInt64?

    public init(
        snapshotCycleID: UUID?,
        interfaceName: String?,
        interfaceIndex: UInt32?,
        routerIP: String?,
        ssid: String?,
        bssid: String?,
        linkState: VerifiedWiFiLinkState?,
        linkRunSessionID: UUID?,
        linkSequence: UInt64?,
        linkEpoch: UInt64?
    ) {
        self.snapshotCycleID = snapshotCycleID
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.routerIP = routerIP
        self.ssid = ssid
        self.bssid = bssid
        self.linkState = linkState
        self.linkRunSessionID = linkRunSessionID
        self.linkSequence = linkSequence
        self.linkEpoch = linkEpoch
    }
}

public enum WiFiGatewayEvidenceAttribution: String, Equatable, Sendable {
    /// The probe ran against the confirmed interface, target, and link epoch.
    case attributed
    /// No probe was attempted because the link was not confirmed associated.
    case linkNotAssociated
    /// No probe was attempted because no usable gateway target was available.
    case targetUnavailable
    /// The Wi-Fi interface changed during the attempt.
    case interfaceChanged
    /// The gateway address or network identity changed during the attempt.
    case targetChanged
    /// The link run session, sequence, or epoch changed during the attempt.
    case linkEpochChanged
    /// The link became unassociated while the probe was in flight.
    case linkLostDuringAttempt
    /// The probe result does not carry the source identity of the target.
    case resultUnattributed
}

public enum WiFiGatewayEvidenceLatencyValidity: String, Equatable, Sendable {
    /// The probe replied with a finite, non-negative latency consistent with its outcome.
    case valid
    /// No latency is expected for this outcome (for example, no reply or execution failure).
    case notApplicable
    /// The probe reported a reply whose latency cannot be trusted.
    case invalid
}

public enum WiFiGatewayEvidenceRejectionReason: String, Equatable, Sendable {
    case snapshotUnavailable
    case linkNotAssociated
    case missingGatewayTarget
    case interfaceChanged
    case networkIdentityChanged
    case linkEpochChanged
    case linkLostDuringAttempt
    case resultUnattributed
    case invalidLatency
}

/// Immutable facts from one gateway evidence attempt.
public struct WiFiGatewayEvidenceSample: Equatable, Sendable {
    public let attemptID: UUID?
    public let startedAt: Date
    public let endedAt: Date
    public let before: WiFiGatewayEvidenceIdentity
    public let after: WiFiGatewayEvidenceIdentity?
    public let outcome: GatewayProbeOutcome?
    public let interfaceBound: Bool
    /// The validated latency. Nil unless `latencyValidity` is `.valid`.
    public let latencyMilliseconds: Double?
    /// The raw latency reported by the probe, when one was reported.
    public let reportedLatencyMilliseconds: Double?
    public let attribution: WiFiGatewayEvidenceAttribution
    public let latencyValidity: WiFiGatewayEvidenceLatencyValidity
    public let rejectionReason: WiFiGatewayEvidenceRejectionReason?

    public init(
        attemptID: UUID?,
        startedAt: Date,
        endedAt: Date,
        before: WiFiGatewayEvidenceIdentity,
        after: WiFiGatewayEvidenceIdentity?,
        outcome: GatewayProbeOutcome?,
        interfaceBound: Bool,
        latencyMilliseconds: Double?,
        reportedLatencyMilliseconds: Double?,
        attribution: WiFiGatewayEvidenceAttribution,
        latencyValidity: WiFiGatewayEvidenceLatencyValidity,
        rejectionReason: WiFiGatewayEvidenceRejectionReason?
    ) {
        self.attemptID = attemptID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.before = before
        self.after = after
        self.outcome = outcome
        self.interfaceBound = interfaceBound
        self.latencyMilliseconds = latencyMilliseconds
        self.reportedLatencyMilliseconds = reportedLatencyMilliseconds
        self.attribution = attribution
        self.latencyValidity = latencyValidity
        self.rejectionReason = rejectionReason
    }
}

/// The production sampler. It composes the existing public interface snapshot,
/// connection interpretation, gateway target validation, and bound pinger
/// without widening their access levels or starting the scanning runtime.
public struct SystemWiFiGatewayEvidenceSampler: WiFiGatewayEvidenceSampling {
    private let linkSnapshot: @Sendable () async -> WiFiLinkStateSnapshot
    private let captureSnapshot: @Sendable (UUID, Date) -> NetworkInterfaceSnapshot
    private let currentStatus: @Sendable (NetworkInterfaceSnapshot) async -> WiFiCurrentStatus
    private let measure: @Sendable (WiFiGatewayProbeTarget) async -> GatewayLatencyResult

    public init(linkStateCenter: WiFiLinkStateCenter = .shared) {
        let provider = GatewayLatencyProvider()
        self.init(
            linkSnapshot: { await linkStateCenter.snapshot() },
            captureSnapshot: { cycleID, capturedAt in
                NetworkInfoService.captureSnapshot(cycleID: cycleID, capturedAt: capturedAt)
            },
            currentStatus: { snapshot in
                await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
            },
            measure: { target in
                await provider.measure(target: target)
            }
        )
    }

    init(
        linkSnapshot: @escaping @Sendable () async -> WiFiLinkStateSnapshot,
        captureSnapshot: @escaping @Sendable (UUID, Date) -> NetworkInterfaceSnapshot,
        currentStatus: @escaping @Sendable (NetworkInterfaceSnapshot) async -> WiFiCurrentStatus,
        measure: @escaping @Sendable (WiFiGatewayProbeTarget) async -> GatewayLatencyResult
    ) {
        self.linkSnapshot = linkSnapshot
        self.captureSnapshot = captureSnapshot
        self.currentStatus = currentStatus
        self.measure = measure
    }

    public func sample() async -> WiFiGatewayEvidenceSample {
        let startedAt = Date()
        let beforeLink = await linkSnapshot()
        let beforeCycleID = UUID()
        let beforeSnapshot = captureSnapshot(beforeCycleID, startedAt)
        let beforeStatus = await currentStatus(beforeSnapshot)
        let before = Self.identity(
            snapshot: beforeSnapshot,
            status: beforeStatus,
            link: beforeLink
        )

        guard beforeSnapshot.interfaceEnumerationSucceeded else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .targetUnavailable,
                reason: .snapshotUnavailable
            )
        }
        guard beforeStatus.linkAssessment?.state == .associated else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .linkNotAssociated,
                reason: .linkNotAssociated
            )
        }
        guard let target = WiFiGatewayProbeTarget.make(from: beforeStatus, cycleID: beforeCycleID) else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .targetUnavailable,
                reason: .missingGatewayTarget
            )
        }

        let result = await measure(target)
        let endedAt = result.timestamp
        let afterCycleID = UUID()
        let afterSnapshot = captureSnapshot(afterCycleID, endedAt)
        let afterStatus = await currentStatus(afterSnapshot)
        let afterLink = await linkSnapshot()
        let after = Self.identity(
            snapshot: afterSnapshot,
            status: afterStatus,
            link: afterLink
        )

        let attribution: WiFiGatewayEvidenceAttribution
        let reason: WiFiGatewayEvidenceRejectionReason?
        if !afterSnapshot.interfaceEnumerationSucceeded {
            attribution = .targetUnavailable
            reason = .snapshotUnavailable
        } else if afterStatus.linkAssessment?.state != .associated {
            attribution = .linkLostDuringAttempt
            reason = .linkLostDuringAttempt
        } else if after.interfaceName != before.interfaceName || after.interfaceIndex != before.interfaceIndex {
            attribution = .interfaceChanged
            reason = .interfaceChanged
        } else if after.routerIP != before.routerIP
            || after.ssid != before.ssid
            || !Self.sameBSSID(after.bssid, before.bssid)
        {
            attribution = .targetChanged
            reason = .networkIdentityChanged
        } else if after.linkRunSessionID != before.linkRunSessionID || after.linkEpoch != before.linkEpoch {
            attribution = .linkEpochChanged
            reason = .linkEpochChanged
        } else if !WiFiGatewayProbeTarget.isAttributedToWiFiTarget(result, target) {
            attribution = .resultUnattributed
            reason = .resultUnattributed
        } else {
            attribution = .attributed
            reason = nil
        }

        let latencyValidity: WiFiGatewayEvidenceLatencyValidity
        let validatedLatency: Double?
        let reportedLatency = result.latencyMs
        if attribution == .attributed, case .replied = result.probeOutcome {
            if WiFiGatewayProbeTarget.isValidWiFiGatewayResult(result, for: target) {
                latencyValidity = .valid
                validatedLatency = reportedLatency
            } else {
                latencyValidity = .invalid
                validatedLatency = nil
            }
        } else {
            latencyValidity = .notApplicable
            validatedLatency = nil
        }

        return WiFiGatewayEvidenceSample(
            attemptID: result.attemptID,
            startedAt: startedAt,
            endedAt: endedAt,
            before: before,
            after: after,
            outcome: result.probeOutcome,
            interfaceBound: result.interfaceBound,
            latencyMilliseconds: validatedLatency,
            reportedLatencyMilliseconds: reportedLatency,
            attribution: attribution,
            latencyValidity: latencyValidity,
            rejectionReason: reason ?? (latencyValidity == .invalid ? .invalidLatency : nil)
        )
    }

    private static func identity(
        snapshot: NetworkInterfaceSnapshot,
        status: WiFiCurrentStatus,
        link: WiFiLinkStateSnapshot
    ) -> WiFiGatewayEvidenceIdentity {
        WiFiGatewayEvidenceIdentity(
            snapshotCycleID: snapshot.cycleID,
            interfaceName: status.interfaceName,
            interfaceIndex: status.interfaceIndex,
            routerIP: status.routerIP,
            ssid: status.ssid,
            bssid: status.bssid,
            linkState: status.linkAssessment?.state,
            linkRunSessionID: link.runSessionID,
            linkSequence: link.sequence,
            linkEpoch: link.linkEpoch
        )
    }

    private static func untested(
        startedAt: Date,
        before: WiFiGatewayEvidenceIdentity,
        attribution: WiFiGatewayEvidenceAttribution,
        reason: WiFiGatewayEvidenceRejectionReason
    ) -> WiFiGatewayEvidenceSample {
        WiFiGatewayEvidenceSample(
            attemptID: nil,
            startedAt: startedAt,
            endedAt: startedAt,
            before: before,
            after: nil,
            outcome: nil,
            interfaceBound: false,
            latencyMilliseconds: nil,
            reportedLatencyMilliseconds: nil,
            attribution: attribution,
            latencyValidity: .notApplicable,
            rejectionReason: reason
        )
    }

    private static func sameBSSID(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (let lhs?, let rhs?): return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default: return false
        }
    }
}
