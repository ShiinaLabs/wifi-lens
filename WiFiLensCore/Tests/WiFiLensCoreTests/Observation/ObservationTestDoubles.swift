import Foundation

@testable import WiFiLensCore

struct TestMockGatewayPinger: GatewayPinging {
    var result: Double?
    func ping(host: String) async -> Double? { result }
}

actor TestCountingCurrentConnectionProvider: WiFiCurrentConnectionProviding {
    let result: WiFiCurrentStatus
    private(set) var fetchCount = 0
    init(result: WiFiCurrentStatus) { self.result = result }
    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus {
        fetchCount += 1
        return result
    }
}

actor TestRecordingWiFiBoundGatewayMeasurer: GatewayLatencyProviding, WiFiBoundGatewayMeasuring {
    let result: GatewayLatencyResult
    private(set) var measuredTargets: [WiFiGatewayProbeTarget] = []

    init(result: GatewayLatencyResult) { self.result = result }

    func measure(routerIP: String?) async -> GatewayLatencyResult { result }

    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult {
        measuredTargets.append(target)
        if case .replied(let milliseconds) = result.probeOutcome,
            let latencyMs = result.latencyMs,
            latencyMs.isFinite, latencyMs >= 0,
            latencyMs == milliseconds
        {
            return GatewayLatencyResult(
                timestamp: result.timestamp, routerIP: target.address, latencyMs: latencyMs,
                probeOutcome: .replied(milliseconds: milliseconds), attemptID: result.attemptID ?? UUID(),
                cycleID: target.snapshotCycleID, interfaceName: target.interfaceName, interfaceBound: true
            )
        }
        return result
    }
}

actor TestRecordingGatewayLatencyProvider: GatewayLatencyProviding {
    let result: GatewayLatencyResult
    private(set) var measuredRouterIPs: [String?] = []
    init(result: GatewayLatencyResult) { self.result = result }
    func measure(routerIP: String?) async -> GatewayLatencyResult {
        measuredRouterIPs.append(routerIP)
        return result
    }
}

actor TestGatewayEvidenceSampler: WiFiGatewayEvidenceSamplingWithContext {
    private let makeSample: @Sendable (WiFiGatewayEvidenceBefore) -> WiFiGatewayEvidenceSample
    private(set) var receivedCycleIDs: [UUID] = []
    private(set) var callCount = 0

    init(_ makeSample: @escaping @Sendable (WiFiGatewayEvidenceBefore) -> WiFiGatewayEvidenceSample) {
        self.makeSample = makeSample
    }

    func sample(before context: WiFiGatewayEvidenceBefore) async -> WiFiGatewayEvidenceSample {
        callCount += 1
        receivedCycleIDs.append(context.cycleID)
        return makeSample(context)
    }
}

enum TestGatewayEvidence {
    static func sample(
        before context: WiFiGatewayEvidenceBefore,
        attribution: WiFiGatewayEvidenceAttribution = .attributed,
        outcome: GatewayProbeOutcome? = nil,
        latencyMilliseconds: Double? = nil,
        latencyValidity: WiFiGatewayEvidenceLatencyValidity = .notApplicable,
        rejectionReason: WiFiGatewayEvidenceRejectionReason? = nil,
        interfaceBound: Bool = true,
        attemptID: UUID? = UUID(),
        endedAt: Date? = nil
    ) -> WiFiGatewayEvidenceSample {
        let identity = WiFiGatewayEvidenceIdentity(
            snapshotCycleID: context.cycleID,
            interfaceName: context.status.interfaceName,
            interfaceIndex: context.status.interfaceIndex,
            routerIP: context.status.routerIP,
            ssid: context.status.ssid,
            bssid: context.status.bssid,
            linkState: context.status.linkAssessment?.state,
            linkRunSessionID: UUID(),
            linkSequence: 1,
            linkEpoch: 1
        )
        return WiFiGatewayEvidenceSample(
            attemptID: attemptID,
            startedAt: context.startedAt,
            endedAt: endedAt ?? Date(),
            before: identity,
            after: nil,
            outcome: outcome,
            interfaceBound: interfaceBound,
            latencyMilliseconds: latencyMilliseconds,
            reportedLatencyMilliseconds: latencyMilliseconds,
            attribution: attribution,
            latencyValidity: latencyValidity,
            rejectionReason: rejectionReason,
            beforeLinkEvidenceFresh: true,
            afterLinkEvidenceFresh: nil
        )
    }
}
