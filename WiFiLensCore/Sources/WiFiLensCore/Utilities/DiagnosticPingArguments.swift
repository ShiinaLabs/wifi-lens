import Foundation

enum DiagnosticPingArguments {
    static func make(target: DiagnosticGatewayTarget) -> [String] {
        ["-b", target.interfaceName, "-c", "1", "-W", "1000", "-t", "1", target.address]
    }
}
