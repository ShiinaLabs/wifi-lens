import Foundation
import SwiftFTR

struct DiagnosticNetworkContext: Sendable {
    let runID: UUID
    let capturedAt: Date
    let pathState: NetworkPathState?
    let route: DiagnosticRouteSelection
    let interfaces: NetworkInterfaceSnapshot
}

protocol DiagnosticNetworkContextSourcing: Sendable {
    func capture(runID: UUID, timeout: Duration) async -> DiagnosticNetworkContext?
}

struct SystemDiagnosticNetworkContextSource: DiagnosticNetworkContextSourcing {
    private let routeSource: any DiagnosticRouteSourcing
    private let pathSource: any NetworkPathChecking
    private let interfaceSource: any NetworkInterfaceSnapshotSourcing

    init(
        routeSource: any DiagnosticRouteSourcing = SystemDiagnosticRouteSource(),
        pathSource: any NetworkPathChecking = SystemNetworkPathChecker(),
        interfaceSource: any NetworkInterfaceSnapshotSourcing = SystemNetworkInterfaceSnapshotSource()
    ) {
        self.routeSource = routeSource
        self.pathSource = pathSource
        self.interfaceSource = interfaceSource
    }

    func capture(runID: UUID, timeout: Duration) async -> DiagnosticNetworkContext? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var lastPathState: NetworkPathState?
        var lastInterfaces = NetworkInterfaceSnapshot(
            cycleID: runID,
            capturedAt: Date(),
            interfaces: []
        )

        for attempt in 0..<2 {
            let before = await routeSource.currentRoute(timeout: deadline.remainingDuration())
            let pathState = await pathSource.currentState(timeout: deadline.remainingDuration())
            let interfaces = await interfaceSource.capture(cycleID: runID)
            let after = await routeSource.currentRoute(timeout: deadline.remainingDuration())
            lastPathState = pathState
            lastInterfaces = interfaces

            if before == after {
                return DiagnosticNetworkContext(
                    runID: runID,
                    capturedAt: Date(),
                    pathState: pathState,
                    route: before,
                    interfaces: interfaces
                )
            }
            if attempt == 0 { continue }
        }

        return DiagnosticNetworkContext(
            runID: runID,
            capturedAt: Date(),
            pathState: lastPathState,
            route: .ambiguous,
            interfaces: lastInterfaces
        )
    }
}

extension ContinuousClock.Instant {
    fileprivate func remainingDuration() -> Duration {
        max(.zero, ContinuousClock.now.duration(to: self))
    }
}

struct IPv4NetworkBoundary: Equatable, Sendable {
    let localHops: [String]
    let externalHop: String

    enum AddressScope {
        case local, carrier, external, other

        init(_ address: String) {
            let octets = address.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
            guard octets.count == 4, address.filter({ $0 == "." }).count == 3 else {
                self = .other
                return
            }
            let first = octets[0]
            let second = octets[1]
            let third = octets[2]
            switch (first, second, third) {
            case (10, _, _), (172, 16...31, _), (192, 168, _): self = .local
            case (100, 64...127, _): self = .carrier
            case (0, _, _), (127, _, _), (169, 254, _), (192, 0, 0), (192, 0, 2),
                 (192, 88, 99), (198, 18...19, _), (198, 51, 100), (203, 0, 113),
                 (224...255, _, _): self = .other
            default: self = .external
            }
        }
    }

    init?(hops: [String?], gateway: String) {
        guard hops.first == .some(gateway) else { return nil }
        var localHops = [gateway]
        for hop in hops.dropFirst() {
            guard let hop else { return nil }
            switch AddressScope(hop) {
            case .local:
                localHops.append(hop)
            case .carrier, .external:
                self.localHops = localHops
                self.externalHop = hop
                return
            case .other:
                return nil
            }
        }
        return nil
    }
}

struct IPv4BoundaryObservation: Sendable {
    struct Network: Equatable, Sendable {
        let route: DiagnosticGatewayTarget
        let addresses: [String]
        let masks: [String]
        let wirelessIdentity: String?
    }

    let network: Network
    let hops: [String?]

    var boundary: IPv4NetworkBoundary? {
        IPv4NetworkBoundary(hops: hops, gateway: network.route.address)
    }

    static func capture(context: DiagnosticNetworkContext?) async -> Self? {
        guard let context, case .selected(let route) = context.route,
            let interface = context.interfaces.interfaces.first(where: { $0.interfaceName == route.interfaceName }),
            !interface.ipv4Addresses.isEmpty,
            !interface.isWiFiInterface || interface.bssid != nil
        else { return nil }

        let tracer = SwiftFTR(
            config: SwiftFTRConfig(maxHops: 8, maxWaitMs: 1200, noReverseDNS: true, interface: route.interfaceName)
        )
        guard let trace = try? await tracer.trace(to: "1.1.1.1"), !Task.isCancelled else { return nil }
        var hops = [String?](repeating: nil, count: 8)
        for hop in trace.hops where (1...hops.count).contains(hop.ttl) {
            if case .notSent = hop.outcome { return nil }
            hops[hop.ttl - 1] = hop.ipAddress
        }
        let network = Network(
            route: route,
            addresses: interface.ipv4Addresses.sorted(),
            masks: interface.subnetMasks.sorted(),
            wirelessIdentity: interface.bssid
        )
        return Self(network: network, hops: hops)
    }

    func failure(using knownBoundary: IPv4NetworkBoundary) -> IPv4BoundaryFailure? {
        guard hops.first == .some(network.route.address) else { return nil }
        let matchingCount = zip(hops, knownBoundary.localHops).prefix { $0 == $1 }.count
        if matchingCount < knownBoundary.localHops.count {
            return hops.dropFirst(matchingCount).allSatisfy { $0 == nil } ? .localRoute : nil
        }
        let outside = hops.dropFirst(matchingCount).compactMap { $0 }
        if outside.isEmpty { return .outlet }
        if outside.first == knownBoundary.externalHop,
            outside.allSatisfy({ IPv4NetworkBoundary.AddressScope($0) == .carrier })
        {
            return .carrier
        }
        return nil
    }
}

struct IPv4BoundaryCache {
    private var entry: (network: IPv4BoundaryObservation.Network, boundary: IPv4NetworkBoundary)?
    private var expiresAt: ContinuousClock.Instant?

    mutating func assess(
        _ observation: IPv4BoundaryObservation?,
        internetAvailable: Bool,
        now: ContinuousClock.Instant = .now
    ) -> IPv4BoundaryFailure? {
        guard let observation else {
            entry = nil
            expiresAt = nil
            return nil
        }
        if entry?.network != observation.network || expiresAt.map({ now >= $0 }) == true {
            entry = nil
            expiresAt = nil
        }
        if internetAvailable {
            if let boundary = observation.boundary {
                entry = (observation.network, boundary)
                expiresAt = now + .seconds(3600)
            }
            return nil
        }
        return entry.flatMap { observation.failure(using: $0.boundary) }
    }
}

enum IPv4BoundaryFailure: String, Sendable {
    case localRoute = "boundary.local-route"
    case outlet = "boundary.outlet"
    case carrier = "boundary.carrier"
}
