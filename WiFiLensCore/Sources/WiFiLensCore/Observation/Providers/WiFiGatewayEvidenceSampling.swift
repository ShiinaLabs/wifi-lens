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

/// Caller-owned pre-probe context. The scanning pipeline already captured this
/// snapshot and status for its observation cycle; passing them avoids a second
/// capture and keeps the evidence attributed to the caller's cycle.
struct WiFiGatewayEvidenceBefore: Sendable {
    let cycleID: UUID
    let snapshot: NetworkInterfaceSnapshot
    let status: WiFiCurrentStatus
    /// The agent supplies the link snapshot it fetched before the attempt so
    /// the ordering and freshness window stay identical to `sample()`.
    let linkSnapshot: WiFiLinkStateSnapshot?
    let linkFetchedAt: Date?
    let startedAt: Date
}

protocol WiFiGatewayEvidenceSamplingWithContext: Sendable {
    func sample(before: WiFiGatewayEvidenceBefore) async -> WiFiGatewayEvidenceSample
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
    public let linkPublishedAt: Date?

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
        linkEpoch: UInt64?,
        linkPublishedAt: Date? = nil
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
        self.linkPublishedAt = linkPublishedAt
    }
}

public enum WiFiGatewayEvidenceAttribution: String, Equatable, Sendable {
    /// The probe ran against the confirmed interface, target, and link epoch.
    case attributed
    /// The attempt was cancelled before its result could be attributed.
    case cancelled
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
    /// The link-state evidence used for attribution was too old to prove
    /// anything about this attempt.
    case linkEvidenceStale
    /// The link snapshot contradicted the confirmed association.
    case linkEvidenceUnavailable
    /// The interface could not be enumerated when the probe result was
    /// re-checked; the probe may have run, so this is not a target failure.
    case captureUnavailable
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
    case linkEvidenceStale
    case linkSnapshotNotAssociated
    case resultUnattributed
    case invalidLatency
    case cancelled
}

/// The persisted evidence vocabulary. These raw values are a cross-repository
/// contract: Pro stores them in SQLite and queries them by literal. Changing a
/// raw value requires a new contract version and a migration.
public enum WiFiGatewayEvidenceContract {
    public static let version = 1
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
    /// Whether the link snapshot used on each side of the probe was fresh
    /// enough to prove the attempt's association. Nil when the caller supplied
    /// only a status (the scanning path) and no link snapshot exists.
    public let beforeLinkEvidenceFresh: Bool?
    public let afterLinkEvidenceFresh: Bool?
    public let evidenceContractVersion: Int

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
        rejectionReason: WiFiGatewayEvidenceRejectionReason?,
        beforeLinkEvidenceFresh: Bool?,
        afterLinkEvidenceFresh: Bool?,
        evidenceContractVersion: Int = WiFiGatewayEvidenceContract.version
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
        self.beforeLinkEvidenceFresh = beforeLinkEvidenceFresh
        self.afterLinkEvidenceFresh = afterLinkEvidenceFresh
        self.evidenceContractVersion = evidenceContractVersion
    }
}

/// The production sampler. It composes the existing public interface snapshot,
/// connection interpretation, gateway target validation, and bound pinger
/// without widening their access levels or starting the scanning runtime.
public struct SystemWiFiGatewayEvidenceSampler: WiFiGatewayEvidenceSampling, WiFiGatewayEvidenceSamplingWithContext {
    /// A link snapshot older than this cannot prove which link a probe belonged
    /// to. The center publishes on an internal 5s schedule; 15s tolerates a
    /// missed publication without accepting evidence from an earlier network.
    /// The agent's link track and the probe's attribution must use one window.
    public static let maximumLinkEvidenceAge: TimeInterval = 15

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
        let beforeLinkFetch = Date()
        let beforeCycleID = UUID()
        let beforeSnapshot = captureSnapshot(beforeCycleID, startedAt)
        let beforeStatus = await currentStatus(beforeSnapshot)
        return await sample(
            before: WiFiGatewayEvidenceBefore(
                cycleID: beforeCycleID,
                snapshot: beforeSnapshot,
                status: beforeStatus,
                linkSnapshot: beforeLink,
                linkFetchedAt: beforeLinkFetch,
                startedAt: startedAt
            )
        )
    }

    func sample(before context: WiFiGatewayEvidenceBefore) async -> WiFiGatewayEvidenceSample {
        let startedAt = context.startedAt
        let usesLinkState = context.linkSnapshot != nil
        let beforeLink = context.linkSnapshot
        let beforeLinkFresh = beforeLink.map {
            $0.isFresh(
                at: context.linkFetchedAt ?? startedAt,
                maximumAge: Self.maximumLinkEvidenceAge
            )
        }
        let before = Self.identity(
            snapshot: context.snapshot,
            status: context.status,
            link: beforeLink
        )

        guard context.snapshot.interfaceEnumerationSucceeded else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .targetUnavailable,
                reason: .snapshotUnavailable,
                beforeLinkFresh: beforeLinkFresh
            )
        }
        guard WiFiLinkEvidenceValidator.assessment(for: context.status)?.state == .associated else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .linkNotAssociated,
                reason: .linkNotAssociated,
                beforeLinkFresh: beforeLinkFresh
            )
        }
        guard let target = WiFiGatewayProbeTarget.make(from: context.status, cycleID: context.cycleID) else {
            return Self.untested(
                startedAt: startedAt,
                before: before,
                attribution: .targetUnavailable,
                reason: .missingGatewayTarget,
                beforeLinkFresh: beforeLinkFresh
            )
        }
        if Task.isCancelled {
            return Self.cancelled(
                startedAt: startedAt,
                endedAt: Date(),
                before: before,
                attemptID: nil,
                interfaceBound: false,
                beforeLinkFresh: beforeLinkFresh
            )
        }

        let result = await measure(target)
        let endedAt = result.timestamp
        if Task.isCancelled {
            return Self.cancelled(
                startedAt: startedAt,
                endedAt: endedAt,
                before: before,
                attemptID: result.attemptID,
                interfaceBound: result.interfaceBound,
                beforeLinkFresh: beforeLinkFresh
            )
        }
        let afterCycleID = UUID()
        let afterSnapshot = captureSnapshot(afterCycleID, endedAt)
        let afterStatus = await currentStatus(afterSnapshot)
        let afterLink: WiFiLinkStateSnapshot?
        let afterLinkFresh: Bool?
        if usesLinkState {
            let link = await linkSnapshot()
            afterLink = link
            afterLinkFresh = link.isFresh(at: Date(), maximumAge: Self.maximumLinkEvidenceAge)
        } else {
            afterLink = nil
            afterLinkFresh = nil
        }
        let after = Self.identity(
            snapshot: afterSnapshot,
            status: afterStatus,
            link: afterLink
        )

        let attribution: WiFiGatewayEvidenceAttribution
        let reason: WiFiGatewayEvidenceRejectionReason?
        if !afterSnapshot.interfaceEnumerationSucceeded {
            attribution = .captureUnavailable
            reason = .snapshotUnavailable
        } else if WiFiLinkEvidenceValidator.assessment(for: afterStatus)?.state != .associated {
            attribution = .linkLostDuringAttempt
            reason = .linkLostDuringAttempt
        } else if let beforeLinkFresh, let afterLinkFresh, !beforeLinkFresh || !afterLinkFresh {
            attribution = .linkEvidenceStale
            reason = .linkEvidenceStale
        } else if usesLinkState, beforeLink?.state != .associated || afterLink?.state != .associated {
            attribution = .linkEvidenceUnavailable
            reason = .linkSnapshotNotAssociated
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
        } else if !WiFiGatewayEvidenceValidator.isAttributed(result, to: context.status) {
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
            if WiFiGatewayEvidenceValidator.isValidReply(result, to: context.status) {
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
            rejectionReason: reason ?? (latencyValidity == .invalid ? .invalidLatency : nil),
            beforeLinkEvidenceFresh: beforeLinkFresh,
            afterLinkEvidenceFresh: afterLinkFresh
        )
    }

    private static func identity(
        snapshot: NetworkInterfaceSnapshot,
        status: WiFiCurrentStatus,
        link: WiFiLinkStateSnapshot?
    ) -> WiFiGatewayEvidenceIdentity {
        WiFiGatewayEvidenceIdentity(
            snapshotCycleID: snapshot.cycleID,
            interfaceName: status.interfaceName,
            interfaceIndex: status.interfaceIndex,
            routerIP: status.routerIP,
            ssid: status.ssid,
            bssid: status.bssid,
            linkState: WiFiLinkEvidenceValidator.assessment(for: status)?.state,
            linkRunSessionID: link?.runSessionID,
            linkSequence: link?.sequence,
            linkEpoch: link?.linkEpoch,
            linkPublishedAt: link?.publishedAt ?? status.linkEvidence?.capturedAt
        )
    }

    private static func untested(
        startedAt: Date,
        before: WiFiGatewayEvidenceIdentity,
        attribution: WiFiGatewayEvidenceAttribution,
        reason: WiFiGatewayEvidenceRejectionReason,
        beforeLinkFresh: Bool?
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
            rejectionReason: reason,
            beforeLinkEvidenceFresh: beforeLinkFresh,
            afterLinkEvidenceFresh: nil
        )
    }

    private static func cancelled(
        startedAt: Date,
        endedAt: Date,
        before: WiFiGatewayEvidenceIdentity,
        attemptID: UUID?,
        interfaceBound: Bool,
        beforeLinkFresh: Bool?
    ) -> WiFiGatewayEvidenceSample {
        WiFiGatewayEvidenceSample(
            attemptID: attemptID,
            startedAt: startedAt,
            endedAt: endedAt,
            before: before,
            after: nil,
            outcome: .cancelled,
            interfaceBound: interfaceBound,
            latencyMilliseconds: nil,
            reportedLatencyMilliseconds: nil,
            attribution: .cancelled,
            latencyValidity: .notApplicable,
            rejectionReason: .cancelled,
            beforeLinkEvidenceFresh: beforeLinkFresh,
            afterLinkEvidenceFresh: nil
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

extension WiFiGatewayEvidenceSample {
    /// The legacy transport form. Only an attributed, non-invalid attempt may
    /// carry a real probe outcome; every rejected attempt stays untested so a
    /// stale or re-attributed result can never be read as current evidence.
    func gatewayLatencyResult(for status: WiFiCurrentStatus) -> GatewayLatencyResult {
        let candidate = candidateLatencyResult
        switch candidate.probeOutcome {
        case .some(.notTested), .some(.cancelled):
            return candidate
        default:
            guard WiFiGatewayEvidenceValidator.isAttributed(candidate, to: status) else {
                return untrustedResult
            }
            return candidate
        }
    }

    private var candidateLatencyResult: GatewayLatencyResult {
        switch attribution {
        case .attributed:
            switch (outcome, latencyValidity) {
            case (.some(.replied(let milliseconds)), .valid):
                return GatewayLatencyResult(
                    timestamp: endedAt,
                    routerIP: before.routerIP,
                    latencyMs: milliseconds,
                    error: nil,
                    probeOutcome: .replied(milliseconds: milliseconds),
                    attemptID: attemptID,
                    cycleID: before.snapshotCycleID,
                    interfaceName: before.interfaceName,
                    interfaceBound: true
                )
            case (.some(.notTested), _):
                return untrustedResult
            case (.some(let outcome), .notApplicable):
                let error: WiFiObservationError? = before.routerIP.map {
                    WiFiObservationError.gatewayPingFailed($0)
                }
                return GatewayLatencyResult(
                    timestamp: endedAt,
                    routerIP: before.routerIP,
                    latencyMs: nil,
                    error: error,
                    probeOutcome: outcome,
                    attemptID: attemptID,
                    cycleID: before.snapshotCycleID,
                    interfaceName: before.interfaceName,
                    interfaceBound: true
                )
            default:
                return untrustedResult
            }
        case .cancelled:
            return GatewayLatencyResult(
                timestamp: endedAt,
                routerIP: before.routerIP,
                latencyMs: nil,
                error: nil,
                probeOutcome: .cancelled,
                attemptID: attemptID,
                cycleID: before.snapshotCycleID,
                interfaceName: before.interfaceName,
                interfaceBound: interfaceBound
            )
        default:
            return untrustedResult
        }
    }

    private var untrustedResult: GatewayLatencyResult {
        GatewayLatencyResult(
            timestamp: startedAt,
            routerIP: before.routerIP,
            latencyMs: nil,
            error: nil,
            probeOutcome: .notTested,
            attemptID: nil,
            cycleID: before.snapshotCycleID,
            interfaceName: before.interfaceName,
            interfaceBound: false
        )
    }
}
