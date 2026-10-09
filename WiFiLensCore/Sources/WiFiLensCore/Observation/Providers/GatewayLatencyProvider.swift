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
              let address = status.routerIP,
              !address.isEmpty else { return nil }
        let assessment = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: cycleID,
            expectedCapturedAt: status.timestamp
        )
        guard assessment == status.linkAssessment, assessment.state == .associated else { return nil }
        return WiFiGatewayProbeTarget(
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex,
            address: address,
            snapshotCycleID: cycleID
        )
    }
}

protocol WiFiBoundGatewayMeasuring: Sendable {
    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult
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
