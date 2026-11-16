import Darwin
import Foundation
import Network
import SwiftFTR

protocol NetworkInterfaceInfoSourcing: Sendable {
    func currentInterface() async -> NetworkInterfaceInfo?
}

struct SystemNetworkInterfaceInfoSource: NetworkInterfaceInfoSourcing {
    func currentInterface() async -> NetworkInterfaceInfo? {
        NetworkInfoService.fetch()
    }
}

enum NetworkPathState: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

protocol NetworkPathChecking: Sendable {
    func currentState(timeout: Duration) async -> NetworkPathState?
}

struct SystemNetworkPathChecker: NetworkPathChecking {
    func currentState(timeout: Duration) async -> NetworkPathState? {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<NetworkPathState> { continuation in
            monitor.pathUpdateHandler = { path in
                let state: NetworkPathState =
                    switch path.status {
                    case .satisfied: .satisfied
                    case .unsatisfied: .unsatisfied
                    case .requiresConnection: .requiresConnection
                    @unknown default: .requiresConnection
                    }
                continuation.yield(state)
                continuation.finish()
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "wifi-lens.network-diagnostics.path"))
        }

        return await withTaskGroup(of: NetworkPathState?.self) { group in
            group.addTask {
                for await state in stream {
                    return state
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            monitor.cancel()
            return first
        }
    }

    func diagnosticEvidence(timeout: Duration) async -> [NetworkDiagnosticEvidence] {
        let monitor = NWPathMonitor()
        let stream = AsyncStream<NWPath> { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
                continuation.finish()
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "wifi-lens.network-diagnostics.path-evidence"))
        }
        return await withTaskGroup(of: [NetworkDiagnosticEvidence]?.self) { group in
            group.addTask {
                for await path in stream {
                    let activeInterface = path.availableInterfaces
                        .filter { path.usesInterfaceType($0.type) }
                        .sorted { $0.name < $1.name }
                        .first
                    guard let activeInterface else { return [] }
                    var evidence = [
                        NetworkDiagnosticEvidence(
                            code: "path.interface-type", value: activeInterface.type.pathEvidenceName),
                        NetworkDiagnosticEvidence(code: "path.interface-name", value: activeInterface.name),
                    ]
                    if ["utun", "ipsec", "ppp"].contains(where: { activeInterface.name.hasPrefix($0) }) {
                        evidence.append(.init(code: "path.routed-tunnel", value: activeInterface.name))
                    }
                    return evidence
                }
                return []
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let evidence = await group.next() ?? nil
            group.cancelAll()
            monitor.cancel()
            return evidence ?? []
        }
    }
}

extension NetworkPathChecking {
    func diagnosticEvidence(timeout: Duration) async -> [NetworkDiagnosticEvidence] { [] }
}

struct NetworkConnectivityCheck: DiagnosticCheck {
    let id = NetworkDiagnosticCheckID.path
    private let pathSource: any NetworkPathChecking
    private let interfaceSource: any NetworkInterfaceInfoSourcing
    private let timeout: Duration
    private let context: DiagnosticNetworkContext?

    init(
        pathSource: any NetworkPathChecking = SystemNetworkPathChecker(),
        interfaceSource: any NetworkInterfaceInfoSourcing = SystemNetworkInterfaceInfoSource(),
        timeout: Duration = .seconds(3)
    ) {
        self.pathSource = pathSource
        self.interfaceSource = interfaceSource
        self.timeout = timeout
        self.context = nil
    }

    init(context: DiagnosticNetworkContext) {
        self.pathSource = SystemNetworkPathChecker()
        self.interfaceSource = SystemNetworkInterfaceInfoSource()
        self.timeout = .seconds(3)
        self.context = context
    }

    func run() async -> NetworkDiagnosticResult {
        if let context {
            return contextResult(context)
        }
        let state = await pathSource.currentState(timeout: timeout)
        let pathEvidence = await pathSource.diagnosticEvidence(timeout: timeout)
        let interface = await interfaceSource.currentInterface()
        let evidence = pathEvidence + self.pathEvidence(interface: interface)
        return switch state {
        case .satisfied:
            NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.path.normal.summary",
                    comment: "Network self-check system path success summary"
                ),
                detail: String(
                    localized: "network_diagnostics.path.normal.summary",
                    comment: "Network self-check system path success detail"
                ),
                evidence: evidence
            )
        case .unsatisfied:
            NetworkDiagnosticResult(
                id: id,
                status: .abnormal,
                summary: String(
                    localized: "network_diagnostics.path.abnormal.summary",
                    comment: "Network self-check system path failure summary"),
                evidence: evidence
            )
        case .requiresConnection, nil:
            NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(
                    localized: "network_diagnostics.path.indeterminate.summary",
                    comment: "Network self-check system path indeterminate summary"),
                evidence: evidence
            )
        }
    }

    private func contextResult(_ context: DiagnosticNetworkContext) -> NetworkDiagnosticResult {
        let selectedInterface: NetworkInterfaceInfo? =
            switch context.route {
            case .selected(let target):
                context.interfaces.interfaces.first { $0.interfaceName == target.interfaceName }
            case .tunneled, .unavailable, .ambiguous, .unsupported:
                nil
            }
        var evidence = pathEvidence(interface: selectedInterface)
        if case .selected(let target) = context.route {
            evidence.append(.init(code: "path.interface-index", value: String(target.interfaceIndex)))
            evidence.append(.init(code: "path.gateway", value: target.address))
        }

        return switch context.pathState {
        case .satisfied:
            NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.path.normal.summary",
                    comment: "Network self-check system path success summary"
                ),
                detail: String(
                    localized: "network_diagnostics.path.normal.summary",
                    comment: "Network self-check system path success detail"
                ),
                evidence: evidence
            )
        case .unsatisfied:
            NetworkDiagnosticResult(
                id: id,
                status: .abnormal,
                summary: String(
                    localized: "network_diagnostics.path.abnormal.summary",
                    comment: "Network self-check system path failure summary"),
                evidence: evidence
            )
        case .requiresConnection, nil:
            NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(
                    localized: "network_diagnostics.path.indeterminate.summary",
                    comment: "Network self-check system path indeterminate summary"),
                evidence: evidence
            )
        }
    }

    private func pathEvidence(interface: NetworkInterfaceInfo?) -> [NetworkDiagnosticEvidence] {
        var evidence: [NetworkDiagnosticEvidence] = []
        if let interface {
            evidence.append(.init(code: "path.interface", value: interface.interfaceName))
            if let address = interface.ipv4Addresses.first {
                evidence.append(.init(code: "path.local-ip", value: address))
            }
            if let subnet = interface.subnetMasks.first {
                evidence.append(.init(code: "path.subnet-mask", value: subnet))
            }
            if let router = interface.router {
                evidence.append(.init(code: "path.router", value: router))
            }
            if let dns = interface.dnsServers.first {
                evidence.append(.init(code: "path.dns-server", value: dns))
            }
        }
        return evidence
    }
}

struct GatewayReachabilityCheck: DiagnosticCheck {
    let id = NetworkDiagnosticCheckID.gatewayReachability
    private let interfaceSource: any NetworkInterfaceInfoSourcing
    private let gatewayLatency: any GatewayLatencyProviding
    private let context: DiagnosticNetworkContext?
    private let diagnosticGatewayMeasuring: (any DiagnosticGatewayMeasuring)?
    private let routeSource: (any DiagnosticRouteSourcing)?
    private let interfaceIndexProvider: @Sendable (String) -> UInt32

    init(
        interfaceSource: any NetworkInterfaceInfoSourcing = SystemNetworkInterfaceInfoSource(),
        gatewayLatency: any GatewayLatencyProviding = GatewayLatencyProvider()
    ) {
        self.interfaceSource = interfaceSource
        self.gatewayLatency = gatewayLatency
        self.context = nil
        self.diagnosticGatewayMeasuring = nil
        self.routeSource = nil
        self.interfaceIndexProvider = { _ in 0 }
    }

    init(
        context: DiagnosticNetworkContext,
        gatewayMeasuring: any DiagnosticGatewayMeasuring = GatewayLatencyProvider(),
        routeSource: (any DiagnosticRouteSourcing)? = SystemDiagnosticRouteSource(),
        interfaceIndexProvider: @escaping @Sendable (String) -> UInt32 = { if_nametoindex($0) }
    ) {
        self.interfaceSource = SystemNetworkInterfaceInfoSource()
        self.gatewayLatency = GatewayLatencyProvider()
        self.context = context
        self.diagnosticGatewayMeasuring = gatewayMeasuring
        self.routeSource = routeSource
        self.interfaceIndexProvider = interfaceIndexProvider
    }

    func run() async -> NetworkDiagnosticResult {
        if let context {
            return await contextResult(context)
        }
        let interface = await interfaceSource.currentInterface()
        let gateway = await gatewayLatency.measure(routerIP: interface?.router)
        let outcome = Self.interpretProbeResult(gateway)
        let trustedOutcome: GatewayProbeInterpretation = outcome == .noReply ? .unverified : outcome
        return result(for: trustedOutcome, value: gateway.routerIP)
    }

    private func contextResult(_ context: DiagnosticNetworkContext) async -> NetworkDiagnosticResult {
        guard let diagnosticGatewayMeasuring else {
            return indeterminateRouteResult(for: context.route)
        }

        guard let resolvedTarget = DiagnosticGatewayProbeTargetResolver.resolve(
            route: context.route,
            interfaces: context.interfaces.interfaces,
            interfaceIndexProvider: interfaceIndexProvider
        ) else {
            if case .tunneled(let tunnel) = context.route {
                return skippedTunnelResult(tunnel)
            }
            return indeterminateRouteResult(for: context.route)
        }
        let target = resolvedTarget.target
        let probeScope = resolvedTarget.scope

        let gateway = await diagnosticGatewayMeasuring.measure(target: target)
        if let routeSource,
            await routeSource.currentRoute(timeout: .seconds(1)) != context.route
        {
            return NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(
                    localized: "network_diagnostics.gateway.indeterminate.summary",
                    comment: "Network self-check gateway reachability indeterminate summary"
                ),
                detail: String(
                    localized: "network_diagnostics.gateway.route_changed",
                    comment: "Gateway route changed during the ICMP probe"
                ),
                evidence: [
                    .init(code: "gateway.route-changed", value: nil),
                    .init(code: "gateway.route-selection", value: routeSelectionCode(context.route)),
                    .init(code: "gateway.probe-scope", value: probeScope),
                    .init(code: "gateway.interface", value: target.interfaceName),
                    .init(code: "gateway.interface-index", value: String(target.interfaceIndex)),
                    .init(code: "gateway.address", value: target.address),
                ]
            )
        }
        var targetEvidence = [
            NetworkDiagnosticEvidence(code: "gateway.route-selection", value: routeSelectionCode(context.route)),
            NetworkDiagnosticEvidence(code: "gateway.probe-scope", value: probeScope),
            NetworkDiagnosticEvidence(code: "gateway.interface", value: target.interfaceName),
            NetworkDiagnosticEvidence(code: "gateway.interface-index", value: String(target.interfaceIndex)),
            NetworkDiagnosticEvidence(code: "gateway.address", value: target.address),
        ]
        if case .tunneled(let tunnel) = context.route {
            targetEvidence.append(.init(code: "gateway.route-interface", value: tunnel.interfaceName))
            targetEvidence.append(.init(code: "gateway.route-interface-index", value: String(tunnel.interfaceIndex)))
        }
        let underlayDetail: String? =
            probeScope == "underlying-lan"
            ? String(
                localized: "network_diagnostics.gateway.vpn_underlay.detail",
                comment: "Gateway probe scope when a system VPN owns the default route"
            )
            : nil

        var outcome = Self.interpretProbeResult(gateway)
        if outcome == .noReply,
            !(gateway.interfaceBound
                && gateway.interfaceName == target.interfaceName
                && gateway.routerIP == target.address
                && gateway.attemptID != nil)
        {
            outcome = .unverified
        }


        return result(
            for: outcome,
            value: target.address,
            evidence: targetEvidence,
            detail: underlayDetail
        )
    }

    private enum GatewayProbeInterpretation: Equatable {
        case replied(milliseconds: Double)
        case noReply
        case notTested
        case executionFailed
        case cancelled
        case localTimeout
        case unverified
    }

    private static func interpretProbeResult(
        _ result: GatewayLatencyResult
    ) -> GatewayProbeInterpretation {
        guard let outcome = result.probeOutcome else { return .unverified }
        switch outcome {
        case .replied(let milliseconds):
            guard let latency = result.latencyMs,
                latency.isFinite,
                latency >= 0,
                latency == milliseconds
            else {
                return .unverified
            }
            return .replied(milliseconds: milliseconds)
        case .noReply:
            return result.latencyMs == nil ? .noReply : .unverified
        case .notTested:
            return hasValidSuccessLatency(result.latencyMs) ? .unverified : .notTested
        case .executionFailed:
            return hasValidSuccessLatency(result.latencyMs) ? .unverified : .executionFailed
        case .cancelled:
            return hasValidSuccessLatency(result.latencyMs) ? .unverified : .cancelled
        case .localTimeout:
            return hasValidSuccessLatency(result.latencyMs) ? .unverified : .localTimeout
        }
    }

    private static func hasValidSuccessLatency(_ latency: Double?) -> Bool {
        guard let latency else { return false }
        return latency.isFinite && latency >= 0
    }

    private func result(
        for outcome: GatewayProbeInterpretation,
        value: String?,
        evidence baseEvidence: [NetworkDiagnosticEvidence] = [],
        detail supplementalDetail: String? = nil
    ) -> NetworkDiagnosticResult {
        switch outcome {
        case .replied(let milliseconds):
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.gateway.normal.summary",
                    comment: "Network self-check gateway reachability success summary"
                ),
                detail: supplementalDetail,
                evidence: baseEvidence + [.init(code: "gateway.latency-ms", value: String(milliseconds))]
            )
        case .noReply:
            return NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: indeterminateSummary,
                detail: String(
                    localized: "network_diagnostics.gateway.no_response",
                    comment: "Gateway did not respond to the ICMP probe"
                ),
                evidence: baseEvidence + [.init(code: "gateway.no-response", value: value)]
            )
        case .notTested:
            return indeterminateResult(
                code: "gateway.probe.not-tested",
                evidence: baseEvidence
            )
        case .executionFailed:
            return indeterminateResult(
                code: "gateway.probe.execution-failed",
                evidence: baseEvidence
            )
        case .cancelled:
            return indeterminateResult(
                code: "gateway.probe.cancelled",
                evidence: baseEvidence
            )
        case .localTimeout:
            return indeterminateResult(
                code: "gateway.probe.local-timeout",
                evidence: baseEvidence
            )
        case .unverified:
            return indeterminateResult(
                code: "gateway.probe.unverified",
                evidence: baseEvidence
            )
        }
    }

    private var indeterminateSummary: String {
        String(
            localized: "network_diagnostics.gateway.indeterminate.summary",
            comment: "Network self-check gateway reachability indeterminate summary"
        )
    }

    private func indeterminateResult(
        code: String,
        evidence: [NetworkDiagnosticEvidence]
    ) -> NetworkDiagnosticResult {
        NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: indeterminateSummary,
            evidence: evidence + [.init(code: code, value: nil)]
        )
    }

    private func indeterminateRouteResult(for route: DiagnosticRouteSelection) -> NetworkDiagnosticResult {
        let detailKey: String =
            switch route {
            case .unsupported:
                "network_diagnostics.gateway.unsupported"
            default:
                "network_diagnostics.gateway.route_changed"
            }
        return NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: String(
                localized: "network_diagnostics.gateway.indeterminate.summary",
                comment: "Network self-check gateway reachability indeterminate summary"
            ),
            detail: String(
                localized: .init(stringLiteral: detailKey),
                comment: "Network self-check gateway route selection detail"
            ),
            evidence: [.init(code: "gateway.route-selection", value: routeSelectionCode(route))]
        )
    }

    private func skippedTunnelResult(_ tunnel: DiagnosticTunnelRouteTarget) -> NetworkDiagnosticResult {
        NetworkDiagnosticResult(
            id: id,
            status: .skipped,
            summary: String(
                localized: "network_diagnostics.gateway.skipped.summary",
                comment: "Network self-check gateway check not applicable summary"
            ),
            detail: String(
                localized: "network_diagnostics.gateway.skipped.detail",
                comment: "Network self-check gateway check skipped because the VPN underlay is not identifiable"
            ),
            evidence: [
                .init(code: "gateway.route-selection", value: "tunneled"),
                .init(code: "gateway.probe-scope", value: "underlying-lan-unavailable"),
                .init(code: "gateway.route-interface", value: tunnel.interfaceName),
                .init(code: "gateway.route-interface-index", value: String(tunnel.interfaceIndex)),
            ]
        )
    }

    private func routeSelectionCode(_ route: DiagnosticRouteSelection) -> String {
        switch route {
        case .selected: "selected"
        case .tunneled: "tunneled"
        case .unavailable: "unavailable"
        case .ambiguous: "ambiguous"
        case .unsupported: "unsupported"
        }
    }
}

private struct ResolvedDiagnosticGatewayTarget {
    let target: DiagnosticGatewayTarget
    let scope: String
}

private enum DiagnosticGatewayProbeTargetResolver {
    static func resolve(
        route: DiagnosticRouteSelection,
        interfaces: [NetworkInterfaceInfo],
        interfaceIndexProvider: @Sendable (String) -> UInt32
    ) -> ResolvedDiagnosticGatewayTarget? {
        switch route {
        case .selected(let target):
            return ResolvedDiagnosticGatewayTarget(target: target, scope: "selected-route")
        case .tunneled(let tunnel):
            let candidates = interfaces.compactMap { interface -> DiagnosticGatewayTarget? in
                guard interface.interfaceName != tunnel.interfaceName,
                    !DiagnosticRouteInterface.isTunnel(interface.interfaceName),
                    interface.interfaceType != .virtual,
                    let address = interface.router
                else {
                    return nil
                }
                let interfaceIndex = interfaceIndexProvider(interface.interfaceName)
                guard interfaceIndex != 0 else { return nil }
                return DiagnosticGatewayTarget(
                    interfaceName: interface.interfaceName,
                    interfaceIndex: interfaceIndex,
                    address: address
                )
            }
            guard candidates.count == 1, let target = candidates.first else { return nil }
            return ResolvedDiagnosticGatewayTarget(target: target, scope: "underlying-lan")
        case .unavailable, .ambiguous, .unsupported:
            return nil
        }
    }
}

struct GatewayTCPReachabilityCheck: DiagnosticCheck {
    static let ports = [80, 443]
    static let timeout: TimeInterval = 1

    let id = NetworkDiagnosticCheckID.gatewayTCPReachability
    private let context: DiagnosticNetworkContext?
    private let contextSource: any DiagnosticNetworkContextSourcing
    private let routeSource: any DiagnosticRouteSourcing
    private let interfaceIndexProvider: @Sendable (String) -> UInt32
    private let probe: @Sendable (TCPProbeConfig) async throws -> TCPProbeResult

    init(
        context: DiagnosticNetworkContext? = nil,
        contextSource: any DiagnosticNetworkContextSourcing = SystemDiagnosticNetworkContextSource(),
        routeSource: any DiagnosticRouteSourcing = SystemDiagnosticRouteSource(),
        interfaceIndexProvider: @escaping @Sendable (String) -> UInt32 = { if_nametoindex($0) },
        probe: @escaping @Sendable (TCPProbeConfig) async throws -> TCPProbeResult = { try await tcpProbe(config: $0) }
    ) {
        self.context = context
        self.contextSource = contextSource
        self.routeSource = routeSource
        self.interfaceIndexProvider = interfaceIndexProvider
        self.probe = probe
    }

    func run() async throws -> NetworkDiagnosticResult {
        let networkContext: DiagnosticNetworkContext?
        if let context {
            networkContext = context
        } else {
            networkContext = await contextSource.capture(runID: UUID(), timeout: .seconds(2))
        }
        guard let networkContext,
            let resolved = DiagnosticGatewayProbeTargetResolver.resolve(
                route: networkContext.route,
                interfaces: networkContext.interfaces.interfaces,
                interfaceIndexProvider: interfaceIndexProvider
            )
        else {
            return indeterminateResult(state: "route-unavailable", target: nil)
        }
        let target = resolved.target
        guard interfaceIndexProvider(target.interfaceName) == target.interfaceIndex else {
            return indeterminateResult(state: "interface-changed", target: target)
        }

        async let port80 = runProbe(port: 80, target: target)
        async let port443 = runProbe(port: 443, target: target)
        let probeResults = await [port80, port443]
        guard !Task.isCancelled else { throw CancellationError() }
        guard await routeSource.currentRoute(timeout: .seconds(1)) == networkContext.route else {
            return indeterminateResult(state: "route-changed", target: target)
        }

        var evidence = [
            NetworkDiagnosticEvidence(code: "gateway.interface", value: target.interfaceName),
            NetworkDiagnosticEvidence(code: "gateway.address", value: target.address),
            NetworkDiagnosticEvidence(code: "gateway.probe-scope", value: resolved.scope),
        ]
        for (port, result) in probeResults {
            evidence.append(.init(code: "gateway.tcp.state.\(port)", value: result?.connectionState.rawValue ?? "probe-error"))
            if let rtt = result?.rtt, rtt.isFinite, rtt >= 0 {
                evidence.append(.init(code: "gateway.tcp.rtt-ms.\(port)", value: String((rtt * 1_000).rounded())))
            }
        }

        if let open = probeResults.first(where: { $0.result?.connectionState == .open }) {
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.gateway_tcp.responded.summary",
                    comment: "Gateway TCP response summary"
                ),
                detail: String(
                    localized: "network_diagnostics.gateway_tcp.open.detail",
                    comment: "At least one checked gateway TCP port accepted a connection"
                ),
                evidence: evidence + [.init(code: "gateway.tcp.response.port", value: String(open.port))]
            )
        }
        if let closed = probeResults.first(where: { $0.result?.connectionState == .closed }) {
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.gateway_tcp.responded.summary",
                    comment: "Gateway TCP response summary"
                ),
                detail: String(
                    localized: "network_diagnostics.gateway_tcp.closed.detail",
                    comment: "At least one checked gateway TCP port refused a connection"
                ),
                evidence: evidence + [.init(code: "gateway.tcp.response.port", value: String(closed.port))]
            )
        }

        let hasFilteredPort = probeResults.contains { $0.result?.connectionState == .filtered }
        return NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: String(
                localized: "network_diagnostics.gateway.indeterminate.summary",
                comment: "Gateway TCP reachability unknown summary"
            ),
            detail: String(
                localized: hasFilteredPort
                    ? "network_diagnostics.gateway_tcp.filtered.detail"
                    : "network_diagnostics.gateway_tcp.error.detail",
                comment: "Gateway TCP probes did not confirm gateway reachability"
            ),
            evidence: evidence
        )
    }

    private func runProbe(
        port: Int,
        target: DiagnosticGatewayTarget
    ) async -> (port: Int, result: TCPProbeResult?) {
        guard !Task.isCancelled else { return (port, nil) }
        let config = TCPProbeConfig(
            host: target.address,
            port: port,
            timeout: Self.timeout,
            interface: target.interfaceName
        )
        do {
            return (port, try await probe(config))
        } catch {
            return (port, nil)
        }
    }

    private func indeterminateResult(
        state: String,
        target: DiagnosticGatewayTarget?
    ) -> NetworkDiagnosticResult {
        var evidence = [NetworkDiagnosticEvidence(code: "gateway.tcp.state", value: state)]
        if let target {
            evidence.append(.init(code: "gateway.interface", value: target.interfaceName))
            evidence.append(.init(code: "gateway.address", value: target.address))
        }
        return NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: String(
                localized: "network_diagnostics.gateway.indeterminate.summary",
                comment: "Gateway TCP reachability unknown summary"
            ),
            detail: String(
                localized: "network_diagnostics.gateway_tcp.error.detail",
                comment: "Gateway TCP probe could not determine reachability detail"
            ),
            evidence: evidence
        )
    }
}

extension NWInterface.InterfaceType {
    fileprivate var pathEvidenceName: String {
        switch self {
        case .wifi: "wifi"
        case .wiredEthernet: "wiredEthernet"
        case .cellular: "cellular"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "other"
        }
    }
}
