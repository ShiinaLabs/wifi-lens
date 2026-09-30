import Foundation

protocol GatewayPingProcessRunning: Sendable {
    func run(executablePath: String, arguments: [String]) async -> Double?
    func cancel() async
}

public actor GatewayPinger {
    private let processRunner: any GatewayPingProcessRunning

    public init() { self.processRunner = SystemGatewayPingProcessRunner() }

    init(processRunner: any GatewayPingProcessRunning) {
        self.processRunner = processRunner
    }

    public func ping(host: String) async -> Double? {
        await ping(arguments: ["-c", "1", "-W", "1000", host])
    }

    func ping(target: DiagnosticGatewayTarget) async -> Double? {
        await ping(arguments: DiagnosticPingArguments.make(target: target))
    }

    private func ping(arguments: [String]) async -> Double? {
        await processRunner.cancel()
        return await withTaskCancellationHandler {
            await processRunner.run(executablePath: "/sbin/ping", arguments: arguments)
        } onCancel: {
            Task { await processRunner.cancel() }
        }
    }
}

actor SystemGatewayPingProcessRunner: GatewayPingProcessRunning {
    /// Overall budget for a single ping, including process startup. Kept just
    /// above the `-W 1000` ping timeout so an unreachable gateway is normally
    /// reported by the process itself, while still bounding the wait if the
    /// process ever hangs.
    private static let pingTimeout: Duration = .milliseconds(1500)

    private var currentState: PingWaitState?

    func run(executablePath: String, arguments: [String]) async -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        let state = PingWaitState(process: process)
        currentState = state

        do {
            try process.run()
        } catch {
            currentState = nil
            return nil
        }

        let status = await withTaskCancellationHandler {
            await Self.waitForExit(state)
        } onCancel: {
            state.terminate()
        }
        if currentState === state {
            currentState = nil
        }

        guard status == 0, !Task.isCancelled else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseLatency(from: output)
    }

    func cancel() {
        currentState?.terminate()
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

    /// Waits for `process` to finish without blocking the actor executor.
    /// Returns the process termination status. Cancellation terminates the
    /// process immediately so the caller gets `nil` quickly instead of waiting
    /// out the ping timeout; a timeout task is the backstop if the process
    /// hangs.
    private static func waitForExit(_ state: PingWaitState) async -> Int32 {
        let timeoutTask = Task { [state] in
            do {
                try await Task.sleep(for: Self.pingTimeout)
            } catch {
                return // Cancelled; the wait already completed.
            }
            state.terminate()
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            state.process.terminationHandler = { [state] terminatedProcess in
                _ = state.resumeIfNeeded(continuation, status: terminatedProcess.terminationStatus)
            }
            // Cover the race where the process exited before the handler
            // was installed.
            if !state.process.isRunning {
                _ = state.resumeIfNeeded(continuation, status: state.process.terminationStatus)
            }
        }

        timeoutTask.cancel()
        return status
    }
}

/// Thread-safe bridge between the process's `terminationHandler`, the
/// cancellation/timeout paths, and the continuation. `Process` is not
/// `Sendable`, so it is boxed here; every cross-thread access goes through
/// this state object.
private final class PingWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    let process: Process

    init(process: Process) {
        self.process = process
    }

    /// Sends SIGTERM to the ping process. Safe to call from any thread.
    func terminate() {
        process.terminate()
    }

    /// Resumes `continuation` exactly once and clears the termination handler
    /// to break the retain cycle. Returns `true` when this call performed the
    /// resume, `false` when another path already did.
    func resumeIfNeeded(_ continuation: CheckedContinuation<Int32, Never>, status: Int32) -> Bool {
        lock.lock()
        if didResume {
            lock.unlock()
            return false
        }
        didResume = true
        process.terminationHandler = nil
        lock.unlock()
        continuation.resume(returning: status)
        return true
    }
}
