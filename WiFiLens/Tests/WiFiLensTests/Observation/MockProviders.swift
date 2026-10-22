import Foundation

@testable import WiFiLensCore
@testable import WiFi_Lens

struct MockCurrentConnectionProvider: WiFiCurrentConnectionProviding {
    var result: WiFiCurrentStatus
    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus { result }
}

struct MockGatewayLatencyProvider: GatewayLatencyProviding {
    var result: GatewayLatencyResult
    func measure(routerIP: String?) async -> GatewayLatencyResult { result }
}

actor CountingCurrentConnectionProvider: WiFiCurrentConnectionProviding {
    let result: WiFiCurrentStatus
    private(set) var fetchCount = 0

    init(result: WiFiCurrentStatus) {
        self.result = result
    }

    func fetchCurrentStatus(from snapshot: NetworkInterfaceSnapshot) async -> WiFiCurrentStatus {
        fetchCount += 1
        return result
    }
}

actor RecordingGatewayLatencyProvider: GatewayLatencyProviding {
    let result: GatewayLatencyResult
    private(set) var measuredRouterIPs: [String?] = []

    init(result: GatewayLatencyResult) {
        self.result = result
    }

    func measure(routerIP: String?) async -> GatewayLatencyResult {
        measuredRouterIPs.append(routerIP)
        return result
    }
}

struct MockGatewayPinger: GatewayPinging {
    var result: Double?
    func ping(host: String) async -> Double? { result }
}

struct MockGatewayEvidenceSampler: WiFiGatewayEvidenceSamplingWithContext {
    var attribution: WiFiGatewayEvidenceAttribution = .linkNotAssociated
    var rejectionReason: WiFiGatewayEvidenceRejectionReason? = .linkNotAssociated

    func sample(before context: WiFiGatewayEvidenceBefore) async -> WiFiGatewayEvidenceSample {
        let identity = WiFiGatewayEvidenceIdentity(
            snapshotCycleID: context.cycleID,
            interfaceName: context.status.interfaceName,
            interfaceIndex: context.status.interfaceIndex,
            routerIP: context.status.routerIP,
            ssid: context.status.ssid,
            bssid: context.status.bssid,
            linkState: context.status.linkAssessment?.state,
            linkRunSessionID: nil,
            linkSequence: nil,
            linkEpoch: nil
        )
        return WiFiGatewayEvidenceSample(
            attemptID: nil,
            startedAt: context.startedAt,
            endedAt: context.startedAt,
            before: identity,
            after: nil,
            outcome: nil,
            interfaceBound: false,
            latencyMilliseconds: nil,
            reportedLatencyMilliseconds: nil,
            attribution: attribution,
            latencyValidity: .notApplicable,
            rejectionReason: rejectionReason,
            beforeLinkEvidenceFresh: nil,
            afterLinkEvidenceFresh: nil
        )
    }
}

struct MockRoamingProbeProvider: RoamingProbeProviding {
    var result: WiFiCurrentStatus
    func fetchCurrentProbe() async -> WiFiCurrentStatus { result }
}
