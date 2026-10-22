import Foundation

public protocol GatewayLatencyProviding: Sendable {
    func measure(routerIP: String?) async -> GatewayLatencyResult
}

protocol GatewayPinging: Sendable {
    func ping(host: String) async -> Double?
    func ping(target: DiagnosticGatewayTarget) async -> Double?
}

extension GatewayPinging {
    /// Address-only callers cannot safely provide interface binding. Diagnostics
    /// must inject a target-aware implementation instead of falling back here.
    func ping(target: DiagnosticGatewayTarget) async -> Double? { nil }
}

extension GatewayPinger: GatewayPinging, GatewayProbeProviding {}

struct WiFiGatewayProbeTarget: Equatable, Sendable {
    let interfaceName: String
    let interfaceIndex: UInt32
    let address: String
    let snapshotCycleID: UUID
    let capturedAt: Date

    var diagnosticTarget: DiagnosticGatewayTarget {
        DiagnosticGatewayTarget(
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex,
            address: address
        )
    }

    static func make(from status: WiFiCurrentStatus, cycleID: UUID) -> WiFiGatewayProbeTarget? {
        guard let evidence = status.linkEvidence,
            evidence.snapshotCycleID == cycleID,
            evidence.capturedAt == status.timestamp,
            status.interfaceSnapshotCycleID == cycleID,
            let interfaceName = status.interfaceName,
            evidence.interfaceName == interfaceName,
            let interfaceIndex = status.interfaceIndex,
            interfaceIndex != 0,
            evidence.interfaceIndex == interfaceIndex,
            let address = status.routerIP,
            !address.isEmpty
        else { return nil }
        guard WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated else { return nil }
        return WiFiGatewayProbeTarget(
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex,
            address: address,
            snapshotCycleID: cycleID,
            capturedAt: status.timestamp
        )
    }
}

protocol WiFiBoundGatewayMeasuring: Sendable {
    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult
}

/// One interpretation of a gateway result against the status it was delivered
/// with. Every consumer that needs to know whether a latency is current uses
/// this, so the rule cannot drift between quality, analysis, and display.
public enum WiFiGatewayEvidenceVerdict: Equatable, Sendable {
    case notTested
    case failed
    case noReply
    case replied(milliseconds: Double)
}

public enum WiFiGatewayEvidenceValidator {
    /// The result belongs to the exact link and interface snapshot carried by
    /// `status`, and is recent enough to describe it.
    public static func isAttributed(
        _ result: GatewayLatencyResult,
        to status: WiFiCurrentStatus
    ) -> Bool {
        guard WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated,
            let cycleID = status.interfaceSnapshotCycleID,
            status.linkEvidence?.snapshotCycleID == cycleID,
            let interfaceName = status.interfaceName, !interfaceName.isEmpty,
            let routerIP = status.routerIP, !routerIP.isEmpty,
            result.interfaceBound,
            result.attemptID != nil,
            result.cycleID == cycleID,
            result.cycleID == status.linkEvidence?.snapshotCycleID,
            result.interfaceName == interfaceName,
            result.routerIP == routerIP,
            result.timestamp >= status.timestamp
        else { return false }
        return true
    }

    public static func isValidReply(
        _ result: GatewayLatencyResult,
        to status: WiFiCurrentStatus
    ) -> Bool {
        guard isAttributed(result, to: status),
            case .replied(let reportedLatency) = result.probeOutcome,
            let latency = result.latencyMs,
            latency.isFinite, latency >= 0,
            reportedLatency.isFinite, reportedLatency >= 0,
            latency.bitPattern == reportedLatency.bitPattern
        else { return false }
        return true
    }

    public static func verdict(
        for result: GatewayLatencyResult?,
        currentStatus: WiFiCurrentStatus
    ) -> WiFiGatewayEvidenceVerdict {
        guard let result, isAttributed(result, to: currentStatus) else {
            return .notTested
        }
        switch result.probeOutcome {
        case .some(.replied(let reportedLatency)):
            guard isValidReply(result, to: currentStatus) else { return .notTested }
            return .replied(milliseconds: reportedLatency)
        case .some(.noReply):
            guard result.latencyMs == nil else { return .notTested }
            return .noReply
        case .some(.executionFailed), .some(.localTimeout), .some(.cancelled):
            return .failed
        case .some(.notTested), .none:
            return .notTested
        }
    }
}

protocol DiagnosticGatewayMeasuring: Sendable {
    func measure(target: DiagnosticGatewayTarget) async -> GatewayLatencyResult
}

public struct GatewayLatencyProvider: GatewayLatencyProviding {
    private let pinger: GatewayPinging

    public init() { self.pinger = GatewayPinger() }

    init(pinger: GatewayPinging) {
        self.pinger = pinger
    }

    public func measure(routerIP: String?) async -> GatewayLatencyResult {
        guard let routerIP, !routerIP.isEmpty else {
            return GatewayLatencyResult(
                timestamp: Date(),
                error: .missingRouterIP,
                probeOutcome: .notTested
            )
        }
        let attemptID = UUID()
        let outcome: GatewayProbeOutcome
        if let typedPinger = pinger as? GatewayProbeProviding {
            outcome = await typedPinger.probe(host: routerIP, attemptID: attemptID)
        } else if let latency = await pinger.ping(host: routerIP) {
            outcome = .replied(milliseconds: latency)
        } else {
            outcome = .executionFailed
        }
        return Self.result(
            outcome,
            timestamp: Date(),
            routerIP: routerIP,
            attemptID: attemptID,
            errorAddress: routerIP
        )
    }

    func measure(target: DiagnosticGatewayTarget) async -> GatewayLatencyResult {
        let attemptID = UUID()
        let outcome: GatewayProbeOutcome
        if let typedPinger = pinger as? GatewayProbeProviding {
            outcome = await typedPinger.probe(target: target, attemptID: attemptID)
        } else if let latency = await pinger.ping(target: target) {
            outcome = .replied(milliseconds: latency)
        } else {
            outcome = .executionFailed
        }
        return Self.result(
            outcome,
            timestamp: Date(),
            routerIP: target.address,
            attemptID: attemptID,
            interfaceName: target.interfaceName,
            interfaceBound: true,
            errorAddress: target.address
        )
    }

    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult {
        let attemptID = UUID()
        guard let typedPinger = pinger as? GatewayProbeProviding else {
            return GatewayLatencyResult(
                timestamp: Date(),
                routerIP: target.address,
                probeOutcome: .notTested,
                attemptID: attemptID,
                cycleID: target.snapshotCycleID,
                interfaceName: target.interfaceName
            )
        }
        let outcome = await typedPinger.probe(target: target.diagnosticTarget, attemptID: attemptID)
        return Self.result(
            outcome,
            timestamp: Date(),
            routerIP: target.address,
            attemptID: attemptID,
            cycleID: target.snapshotCycleID,
            interfaceName: target.interfaceName,
            interfaceBound: true,
            errorAddress: target.address
        )
    }

    private static func result(
        _ outcome: GatewayProbeOutcome,
        timestamp: Date,
        routerIP: String,
        attemptID: UUID,
        cycleID: UUID? = nil,
        interfaceName: String? = nil,
        interfaceBound: Bool = false,
        errorAddress: String
    ) -> GatewayLatencyResult {
        let latency: Double?
        if case .replied(let milliseconds) = outcome {
            latency = milliseconds
        } else {
            latency = nil
        }
        let error: WiFiObservationError? = latency == nil ? .gatewayPingFailed(errorAddress) : nil
        return GatewayLatencyResult(
            timestamp: timestamp,
            routerIP: routerIP,
            latencyMs: latency,
            error: error,
            probeOutcome: outcome,
            attemptID: attemptID,
            cycleID: cycleID,
            interfaceName: interfaceName,
            interfaceBound: interfaceBound
        )
    }
}

extension GatewayLatencyProvider: DiagnosticGatewayMeasuring, WiFiBoundGatewayMeasuring {}
