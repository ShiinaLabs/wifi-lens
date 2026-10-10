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
           latencyMs == milliseconds {
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
