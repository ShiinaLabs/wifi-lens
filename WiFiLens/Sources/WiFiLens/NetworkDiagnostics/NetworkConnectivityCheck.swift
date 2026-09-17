import Foundation
import Darwin
import Network

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
                let state: NetworkPathState = switch path.status {
                case .satisfied: .satisfied
                case .unsatisfied: .unsatisfied
                case .requiresConnection: .requiresConnection
                @unknown default: .requiresConnection
                }
                continuation.yield(state)
                continuation.finish()
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.path"))
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
            monitor.start(queue: DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.path-evidence"))
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
                        NetworkDiagnosticEvidence(code: "path.interface-type", value: activeInterface.type.pathEvidenceName),
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
                summary: String(localized: "network_diagnostics.path.abnormal.summary", comment: "Network self-check system path failure summary"),
                evidence: evidence
            )
        case .requiresConnection, nil:
            NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(localized: "network_diagnostics.path.indeterminate.summary", comment: "Network self-check system path indeterminate summary"),
                evidence: evidence
            )
        }
    }

    private func contextResult(_ context: DiagnosticNetworkContext) -> NetworkDiagnosticResult {
        let selectedInterface: NetworkInterfaceInfo? = switch context.route {
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
                summary: String(localized: "network_diagnostics.path.abnormal.summary", comment: "Network self-check system path failure summary"),
                evidence: evidence
            )
        case .requiresConnection, nil:
            NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(localized: "network_diagnostics.path.indeterminate.summary", comment: "Network self-check system path indeterminate summary"),
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

        if let latency = gateway.latencyMs {
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.gateway.normal.summary",
                    comment: "Network self-check gateway reachability success summary"
                ),
                evidence: [.init(code: "gateway.latency-ms", value: String(latency))]
            )
        }
        if let router = gateway.routerIP {
            if case .gatewayPingFailed = gateway.error {
                return NetworkDiagnosticResult(
                    id: id,
                    status: .indeterminate,
                    summary: String(
                        localized: "network_diagnostics.gateway.indeterminate.summary",
                        comment: "Network self-check gateway reachability indeterminate summary"
                    ),
                    detail: String(
                        localized: "network_diagnostics.gateway.no_response",
                        comment: "Gateway did not respond to the ICMP probe"
                    ),
                    evidence: [.init(code: "gateway.no-response", value: router)]
                )
            }
            return NetworkDiagnosticResult(
                id: id,
                status: .abnormal,
                summary: String(
                    localized: "network_diagnostics.gateway.abnormal.summary",
                    comment: "Network self-check gateway reachability failure summary"
                ),
                evidence: [.init(code: "gateway.unreachable", value: router)]
            )
        }
        return NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: String(
                localized: "network_diagnostics.gateway.indeterminate.summary",
                comment: "Network self-check gateway reachability indeterminate summary"
            ),
            evidence: [.init(code: "gateway.unavailable", value: nil)]
        )
    }

    private func contextResult(_ context: DiagnosticNetworkContext) async -> NetworkDiagnosticResult {
        guard let diagnosticGatewayMeasuring else {
            return indeterminateRouteResult(for: context.route)
        }

        let target: DiagnosticGatewayTarget
        let probeScope: String
        switch context.route {
        case .selected(let selectedTarget):
            target = selectedTarget
            probeScope = "selected-route"
        case .tunneled(let tunnel):
            guard let underlayTarget = underlyingGatewayTarget(
                for: tunnel,
                interfaces: context.interfaces.interfaces
            ) else {
                return skippedTunnelResult(tunnel)
            }
            target = underlayTarget
            probeScope = "underlying-lan"
        case .unavailable, .ambiguous, .unsupported:
            return indeterminateRouteResult(for: context.route)
        }

        let gateway = await diagnosticGatewayMeasuring.measure(target: target)
        if let routeSource,
           await routeSource.currentRoute(timeout: .seconds(1)) != context.route {
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
        let underlayDetail: String? = probeScope == "underlying-lan"
            ? String(
                localized: "network_diagnostics.gateway.vpn_underlay.detail",
                comment: "Gateway probe scope when a system VPN owns the default route"
            )
            : nil

        if let latency = gateway.latencyMs {
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(
                    localized: "network_diagnostics.gateway.normal.summary",
                    comment: "Network self-check gateway reachability success summary"
                ),
                detail: underlayDetail,
                evidence: targetEvidence + [.init(code: "gateway.latency-ms", value: String(latency))]
            )
        }
        if case .gatewayPingFailed = gateway.error {
            return NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(
                    localized: "network_diagnostics.gateway.indeterminate.summary",
                    comment: "Network self-check gateway reachability indeterminate summary"
                ),
                detail: String(
                    localized: "network_diagnostics.gateway.no_response",
                    comment: "Gateway did not respond to the ICMP probe"
                ),
                evidence: targetEvidence + [.init(code: "gateway.no-response", value: target.address)]
            )
        }
        return NetworkDiagnosticResult(
            id: id,
            status: .abnormal,
            summary: String(
                localized: "network_diagnostics.gateway.abnormal.summary",
                comment: "Network self-check gateway reachability failure summary"
            ),
            detail: underlayDetail,
            evidence: targetEvidence + [.init(code: "gateway.unreachable", value: target.address)]
        )
    }

    private func indeterminateRouteResult(for route: DiagnosticRouteSelection) -> NetworkDiagnosticResult {
        let detailKey: String = switch route {
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

    private func underlyingGatewayTarget(
        for tunnel: DiagnosticTunnelRouteTarget,
        interfaces: [NetworkInterfaceInfo]
    ) -> DiagnosticGatewayTarget? {
        let candidates = interfaces.compactMap { interface -> DiagnosticGatewayTarget? in
            guard interface.interfaceName != tunnel.interfaceName,
                  !DiagnosticRouteInterface.isTunnel(interface.interfaceName),
                  interface.interfaceType != .virtual,
                  let address = interface.router else {
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
        guard candidates.count == 1 else { return nil }
        return candidates[0]
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

private extension NWInterface.InterfaceType {
    var pathEvidenceName: String {
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
