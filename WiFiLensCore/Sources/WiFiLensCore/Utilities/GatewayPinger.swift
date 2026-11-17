import Darwin
import Foundation
import SwiftFTR

protocol GatewayProbeProviding: Sendable {
    func probe(host: String, attemptID: UUID) async -> GatewayProbeOutcome
    func probe(target: DiagnosticGatewayTarget, attemptID: UUID) async -> GatewayProbeOutcome
}

actor GatewayPinger {
    private static let totalTimeout: Duration = .milliseconds(1500)
    private let performPing: @Sendable (String, PingConfig) async throws -> PingResult
    private let interfaceIndex: @Sendable (String) -> UInt32

    public init() {
        let swiftFTR = SwiftFTR()
        self.performPing = { host, config in
            try await swiftFTR.ping(to: host, config: config)
        }
        self.interfaceIndex = { if_nametoindex($0) }
    }

    init(
        performPing: @escaping @Sendable (String, PingConfig) async throws -> PingResult,
        interfaceIndex: @escaping @Sendable (String) -> UInt32 = { if_nametoindex($0) }
    ) {
        self.performPing = performPing
        self.interfaceIndex = interfaceIndex
    }

    func ping(host: String) async -> Double? {
        guard case .replied(let milliseconds) = await probe(host: host, attemptID: UUID()) else { return nil }
        return milliseconds
    }

    func ping(target: DiagnosticGatewayTarget) async -> Double? {
        guard case .replied(let milliseconds) = await probe(target: target, attemptID: UUID()) else { return nil }
        return milliseconds
    }

    func probe(host: String, attemptID: UUID) async -> GatewayProbeOutcome {
        await probe(host: host, interface: nil)
    }

    func probe(target: DiagnosticGatewayTarget, attemptID: UUID) async -> GatewayProbeOutcome {
        guard interfaceIndex(target.interfaceName) == target.interfaceIndex else {
            return .executionFailed
        }
        return await probe(host: target.address, interface: target.interfaceName)
    }

    private func probe(host: String, interface: String?) async -> GatewayProbeOutcome {
        guard !Task.isCancelled else { return .cancelled }
        let config = PingConfig(
            count: 1,
            interval: 0,
            timeout: 1,
            interface: interface
        )
        let performPing = self.performPing
        return await withTaskGroup(of: GatewayProbeOutcome.self) { group in
            group.addTask {
                do {
                    let result = try await performPing(host, config)
                    guard let response = result.responses.first else { return .executionFailed }
                    guard let seconds = response.rtt else { return .noReply }
                    guard seconds.isFinite, seconds >= 0 else { return .executionFailed }
                    return .replied(milliseconds: seconds * 1000)
                } catch {
                    return Task.isCancelled ? .cancelled : .executionFailed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: Self.totalTimeout)
                    return .localTimeout
                } catch {
                    return .cancelled
                }
            }
            let outcome = await group.next() ?? .executionFailed
            group.cancelAll()
            return outcome
        }
    }
}
