import Foundation

enum GatewayPingProcessOutcome: Equatable, Sendable {
    case exited(status: Int32, output: String)
    case terminatedBySignal(Int32)
    case failedToLaunch
    case outputReadFailed
    case cancelled
    case localTimeout
}

protocol GatewayPingProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String], attemptID: UUID) async -> GatewayPingProcessOutcome
    func cancel(attemptID: UUID) async
}

protocol GatewayProbeProviding: Sendable {
    func probe(host: String, attemptID: UUID) async -> GatewayProbeOutcome
    func probe(target: DiagnosticGatewayTarget, attemptID: UUID) async -> GatewayProbeOutcome
}

actor GatewayPinger {
    private let processRunner: any GatewayPingProcessRunning

    public init() { self.processRunner = SystemGatewayPingProcessRunner() }

    init(processRunner: any GatewayPingProcessRunning) {
        self.processRunner = processRunner
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
        await probe(arguments: ["-c", "1", "-W", "1000", host], attemptID: attemptID)
    }

    func probe(target: DiagnosticGatewayTarget, attemptID: UUID) async -> GatewayProbeOutcome {
        await probe(arguments: DiagnosticPingArguments.make(target: target), attemptID: attemptID)
    }

    private func probe(arguments: [String], attemptID: UUID) async -> GatewayProbeOutcome {
        let result = await withTaskCancellationHandler {
            await processRunner.run(
                executablePath: "/sbin/ping",
                arguments: arguments,
                attemptID: attemptID
            )
        } onCancel: {
            Task { await processRunner.cancel(attemptID: attemptID) }
        }
        return Self.interpret(result)
    }

    static func interpret(_ outcome: GatewayPingProcessOutcome) -> GatewayProbeOutcome {
        switch outcome {
        case .failedToLaunch, .terminatedBySignal, .outputReadFailed:
            return .executionFailed
        case .cancelled:
            return .cancelled
        case .localTimeout:
            return .localTimeout
        case .exited(let status, let output):
            if status == 0, let milliseconds = parseLatency(from: output), milliseconds.isFinite, milliseconds >= 0 {
                return .replied(milliseconds: milliseconds)
            }
            if status != 0, confirmsNoReply(output) {
                return .noReply
            }
            return .executionFailed
        }
    }

    private static func parseLatency(from output: String) -> Double? {
        for line in output.components(separatedBy: "\n") {
            guard let range = line.range(of: "time=") else { continue }
            let rest = line[range.upperBound...]
            let milliseconds = rest.components(separatedBy: " ").first ?? ""
            return Double(milliseconds)
        }
        return nil
    }

    private static func confirmsNoReply(_ output: String) -> Bool {
        let normalized = output.lowercased().replacingOccurrences(of: "\n", with: " ")
        return normalized.contains("0 packets received") && normalized.contains("100.0% packet loss")
    }
}

actor SystemGatewayPingProcessRunner: GatewayPingProcessRunning {
    /// Overall budget for a single ping, including process startup.
    private static let pingTimeout: Duration = .milliseconds(1500)
    private var states: [UUID: PingWaitState] = [:]

    func run(executablePath: String, arguments: [String], attemptID: UUID) async -> GatewayPingProcessOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let state = PingWaitState(process: process)
        states[attemptID] = state

        do {
            try process.run()
        } catch {
            if states[attemptID] === state { states[attemptID] = nil }
            return .failedToLaunch
        }

        let exit = await Self.waitForExit(state)
        if states[attemptID] === state { states[attemptID] = nil }
        switch exit.stopReason {
        case .cancelled:
            return .cancelled
        case .localTimeout:
            return .localTimeout
        case nil:
            break
        }
        if exit.terminatedBySignal {
            return .terminatedBySignal(exit.status)
        }

        do {
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            guard let output = String(data: data, encoding: .utf8) else { return .outputReadFailed }
            return .exited(status: exit.status, output: output)
        } catch {
            return .outputReadFailed
        }
    }

    func cancel(attemptID: UUID) {
        states[attemptID]?.terminate(reason: .cancelled)
    }

    private static func waitForExit(_ state: PingWaitState) async -> PingProcessExit {
        let timeoutTask = Task { [state] in
            do {
                try await Task.sleep(for: Self.pingTimeout)
            } catch {
                return
            }
            state.terminate(reason: .localTimeout)
        }

        let exit = await withCheckedContinuation { (continuation: CheckedContinuation<PingProcessExit, Never>) in
            state.process.terminationHandler = { [state] terminatedProcess in
                _ = state.resumeIfNeeded(continuation, process: terminatedProcess)
            }
            if !state.process.isRunning {
                _ = state.resumeIfNeeded(continuation, process: state.process)
            }
        }
        timeoutTask.cancel()
        return exit
    }
}

private enum PingStopReason: Equatable, Sendable {
    case cancelled
    case localTimeout
}

private struct PingProcessExit: Sendable {
    let status: Int32
    let terminatedBySignal: Bool
    let stopReason: PingStopReason?
}

/// Thread-safe bridge between process termination, cancellation, timeout, and the continuation.
private final class PingWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private var stopReason: PingStopReason?

    let process: Process

    init(process: Process) {
        self.process = process
    }

    func terminate(reason: PingStopReason) {
        lock.lock()
        if stopReason == nil { stopReason = reason }
        lock.unlock()
        if process.isRunning { process.terminate() }
    }

    func resumeIfNeeded(
        _ continuation: CheckedContinuation<PingProcessExit, Never>,
        process: Process
    ) -> Bool {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return false
        }
        didResume = true
        let exit = PingProcessExit(
            status: process.terminationStatus,
            terminatedBySignal: process.terminationReason == .uncaughtSignal,
            stopReason: stopReason
        )
        process.terminationHandler = nil
        lock.unlock()
        continuation.resume(returning: exit)
        return true
    }
}
