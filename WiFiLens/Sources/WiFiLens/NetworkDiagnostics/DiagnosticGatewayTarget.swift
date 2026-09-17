import Foundation

struct DiagnosticGatewayTarget: Equatable, Sendable {
    let interfaceName: String
    let interfaceIndex: UInt32
    let address: String
}

struct DiagnosticTunnelRouteTarget: Equatable, Sendable {
    let interfaceName: String
    let interfaceIndex: UInt32
}

enum DiagnosticRouteInterface {
    private static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    static func isTunnel(_ interfaceName: String) -> Bool {
        tunnelPrefixes.contains { interfaceName.hasPrefix($0) }
    }
}

enum DiagnosticRouteSelection: Equatable, Sendable {
    case selected(DiagnosticGatewayTarget)
    case tunneled(DiagnosticTunnelRouteTarget)
    case unavailable
    case ambiguous
    case unsupported
}

protocol DiagnosticRouteSourcing: Sendable {
    func currentRoute(timeout: Duration) async -> DiagnosticRouteSelection
}
