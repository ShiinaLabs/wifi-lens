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

extension GatewayPinger: GatewayPinging {}

public protocol DiagnosticGatewayMeasuring: Sendable {
    func measure(target: DiagnosticGatewayTarget) async -> GatewayLatencyResult
}

public struct GatewayLatencyProvider: GatewayLatencyProviding {
    private let pinger: GatewayPinging

    public init() { self.pinger = GatewayPinger() }

    init(pinger: GatewayPinging) {
        self.pinger = pinger
    }

    public func measure(routerIP: String?) async -> GatewayLatencyResult {
        guard let routerIP else {
            return GatewayLatencyResult(
                timestamp: Date(),
                error: .missingRouterIP
            )
        }
        let latency = await pinger.ping(host: routerIP)
        guard let latency else {
            return GatewayLatencyResult(
                timestamp: Date(),
                routerIP: routerIP,
                error: .gatewayPingFailed(routerIP)
            )
        }
        return GatewayLatencyResult(
            timestamp: Date(),
            routerIP: routerIP,
            latencyMs: latency
        )
    }

    public func measure(target: DiagnosticGatewayTarget) async -> GatewayLatencyResult {
        let latency = await pinger.ping(target: target)
        guard let latency else {
            return GatewayLatencyResult(
                timestamp: Date(),
                routerIP: target.address,
                error: .gatewayPingFailed(target.address)
            )
        }
        return GatewayLatencyResult(
            timestamp: Date(),
            routerIP: target.address,
            latencyMs: latency
        )
    }
}

extension GatewayLatencyProvider: DiagnosticGatewayMeasuring {}
