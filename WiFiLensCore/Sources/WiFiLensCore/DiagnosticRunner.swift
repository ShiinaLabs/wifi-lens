import Foundation

enum DiagnosticCheckRerunPolicy: Equatable, Sendable {
    case networkSensitive
    case configurationOnly
}

protocol DiagnosticCheck: Sendable {
    var id: NetworkDiagnosticCheckID { get }
    var rerunPolicy: DiagnosticCheckRerunPolicy { get }
    func run() async throws -> NetworkDiagnosticResult
}

extension DiagnosticCheck {
    var rerunPolicy: DiagnosticCheckRerunPolicy { .networkSensitive }
}

extension NetworkDiagnosticStatus: Hashable {}

private struct DiagnosticDependency {
    let id: NetworkDiagnosticCheckID
    let blockingStatuses: Set<NetworkDiagnosticStatus>
}

private struct DiagnosticCheckRunResult: Sendable {
    let result: NetworkDiagnosticResult?
    let endReason: DiagnosticRunEndReason?
}

private final class DiagnosticCheckCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DiagnosticCheckRunResult, Never>?
    private var operation: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var didFinish = false

    func install(continuation: CheckedContinuation<DiagnosticCheckRunResult, Never>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            continuation.resume(returning: .init(result: nil, endReason: .cancelled))
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func install(
        operation: Task<Void, Never>,
        timeout: Task<Void, Never>
    ) {
        lock.lock()
        self.operation = operation
        self.timeout = timeout
        let shouldCancel = didFinish
        lock.unlock()
        if shouldCancel {
            operation.cancel()
            timeout.cancel()
        }
    }

    func finish(_ result: DiagnosticCheckRunResult) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let operation = self.operation
        let timeout = self.timeout
        self.operation = nil
        self.timeout = nil
        lock.unlock()

        operation?.cancel()
        timeout?.cancel()
        continuation?.resume(returning: result)
    }

    func cancel() {
        finish(.init(result: nil, endReason: .cancelled))
    }
}

struct DiagnosticRunner: Sendable {
    let checks: [any DiagnosticCheck]
    var sessionBudget: Duration = .seconds(30)
    var clock: any DiagnosticClock = ContinuousDiagnosticClock()

    func run(
        runID: UUID = UUID(),
        retaining retainedResults: [NetworkDiagnosticResult] = [],
        deadline: ContinuousClock.Instant? = nil,
        onCheckStarted: (@Sendable (NetworkDiagnosticCheckID) async -> Void)? = nil,
        onResult: @escaping @Sendable (NetworkDiagnosticResult) async -> Void
    ) async -> DiagnosticRunOutcome {
        var results: [NetworkDiagnosticResult] = []
        let retainedByID = Dictionary(uniqueKeysWithValues: retainedResults.map { ($0.id, $0) })
        let sessionDeadline: ContinuousClock.Instant = if let deadline {
            deadline
        } else {
            (await clock.now()).advanced(by: sessionBudget)
        }
        var endReason: DiagnosticRunEndReason = .completed

        for check in checks {
            guard !Task.isCancelled else {
                endReason = .cancelled
                break
            }
            guard await clock.now() < sessionDeadline else {
                endReason = .timedOut
                break
            }
            if let retainedResult = retainedByID[check.id] {
                results.append(retainedResult)
                continue
            }
            if let blocker = blockingResult(for: check.id, from: results) {
                let result = NetworkDiagnosticResult(
                    id: check.id,
                    status: .blocked,
                    summary: blocker.summary,
                    detail: blocker.summary,
                    evidence: [.init(code: "blocked.by", value: blocker.id.rawValue)]
                )
                results.append(result)
                await onResult(result)
                continue
            }
            await onCheckStarted?(check.id)
            let checkResult = await run(check, until: sessionDeadline)
            guard !Task.isCancelled else {
                endReason = .cancelled
                break
            }
            guard let result = checkResult.result else {
                endReason = checkResult.endReason ?? .timedOut
                break
            }
            results.append(result)
            await onResult(result)

            if let checkEndReason = checkResult.endReason {
                endReason = checkEndReason
                break
            }

            if await clock.now() >= sessionDeadline {
                endReason = .timedOut
                break
            }
        }

        if Task.isCancelled {
            endReason = .cancelled
        } else if endReason == .completed, results.count < checks.count {
            endReason = .timedOut
        }
        let resultIDs = Set(results.map(\.id))
        return DiagnosticRunOutcome(
            runID: runID,
            results: results,
            pendingIDs: checks.map(\.id).filter { !resultIDs.contains($0) },
            endReason: endReason
        )
    }

    private func run(
        _ check: any DiagnosticCheck,
        until deadline: ContinuousClock.Instant
    ) async -> DiagnosticCheckRunResult {
        let remaining = (await clock.now()).duration(to: deadline)
        guard remaining > .zero else {
            return .init(result: nil, endReason: .timedOut)
        }
        let gate = DiagnosticCheckCompletionGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation: continuation)
                let operation = Task {
                    do {
                        gate.finish(.init(result: try await check.run(), endReason: nil))
                    } catch {
                        if Task.isCancelled {
                            gate.finish(.init(result: nil, endReason: .cancelled))
                        } else {
                            gate.finish(.init(
                                result: NetworkDiagnosticResult(
                                    id: check.id,
                                    status: .indeterminate,
                                    summary: "The check could not complete.",
                                    evidence: [.init(code: "check.failed", value: nil)]
                                ),
                                endReason: nil
                            ))
                        }
                    }
                }
                let timeout = Task {
                    do {
                        try await clock.sleep(until: deadline)
                        gate.finish(.init(
                            result: NetworkDiagnosticResult(
                                id: check.id,
                                status: .indeterminate,
                                summary: String(
                                    localized: "network_diagnostics.check.timed_out",
                                    comment: "Network self-check individual check timeout summary"
                                ),
                                evidence: [.init(code: "check.timeout", value: nil)]
                            ),
                            endReason: .timedOut
                        ))
                    } catch {
                        // The operation completed or the parent cancelled.
                    }
                }
                gate.install(operation: operation, timeout: timeout)
            }
        } onCancel: {
            gate.cancel()
        }
    }

    private func blockingResult(
        for id: NetworkDiagnosticCheckID,
        from results: [NetworkDiagnosticResult]
    ) -> NetworkDiagnosticResult? {
        let hardFailureStatuses: Set<NetworkDiagnosticStatus> = [.abnormal, .blocked]
        let dependencies: [DiagnosticDependency] = switch id {
        case .path:
            []
        case .gatewayReachability:
            [.init(id: .path, blockingStatuses: hardFailureStatuses)]
        case .dns:
            [.init(id: .path, blockingStatuses: hardFailureStatuses)]
        case .internet, .ipv6:
            [.init(id: .path, blockingStatuses: hardFailureStatuses)]
        case .proxy:
            [.init(id: .path, blockingStatuses: hardFailureStatuses)]
        }
        return dependencies.compactMap { dependency -> NetworkDiagnosticResult? in
            guard let result = results.first(where: { $0.id == dependency.id }),
                  dependency.blockingStatuses.contains(result.status) else {
                return nil
            }
            return result
        }.first
    }
}
