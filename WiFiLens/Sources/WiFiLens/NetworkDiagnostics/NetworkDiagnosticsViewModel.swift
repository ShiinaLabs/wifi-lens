import Foundation
import Observation
import WiFiLensCore

enum NetworkDiagnosticsPagePhase: Equatable, Sendable {
    case idle
    case running
    case completed
}

enum NetworkDiagnosticExecutionPhase: Equatable, Sendable {
    case waiting
    case checking
    case completed
}

enum NetworkDiagnosticsWorkbenchLayoutMode: Equatable, Sendable {
    case compact
    case condensed
    case regular
}

enum NetworkDiagnosticsWorkbenchLayout {
    static func mode(for availableWidth: Double) -> NetworkDiagnosticsWorkbenchLayoutMode {
        if availableWidth >= 720 { return .regular }
        if availableWidth >= 520 { return .condensed }
        return .compact
    }
}

enum NetworkDiagnosticsTablePresentation {
    static let minimumRowHeight = 54.0
    static let usesAlternatingRowBackgrounds = false
}

struct NetworkDiagnosticsWorkbenchRow: Equatable, Identifiable, Sendable {
    let id: NetworkDiagnosticCheckID
    let executionPhase: NetworkDiagnosticExecutionPhase
    let result: NetworkDiagnosticResult?
    let pendingReason: DiagnosticRunEndReason?

    init(
        id: NetworkDiagnosticCheckID,
        executionPhase: NetworkDiagnosticExecutionPhase,
        result: NetworkDiagnosticResult?,
        pendingReason: DiagnosticRunEndReason? = nil
    ) {
        self.id = id
        self.executionPhase = executionPhase
        self.result = result
        self.pendingReason = pendingReason
    }
}

enum NetworkDiagnosticsWorkbenchItem: Equatable, Identifiable {
    case stageHeader(NetworkDiagnosticStage)
    case additionalHeader
    case check(NetworkDiagnosticsWorkbenchRow)

    var id: String {
        switch self {
        case .stageHeader(let stage): "header.\(String(describing: stage))"
        case .additionalHeader: "header.additional"
        case .check(let row): "check.\(row.id.rawValue)"
        }
    }
}

enum NetworkDiagnosticsPresentation {
    static func workbenchRows(
        pagePhase: NetworkDiagnosticsPagePhase,
        executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase],
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        checkIDs: [NetworkDiagnosticCheckID] = NetworkDiagnosticCheckID.allCases,
        endReason: DiagnosticRunEndReason? = nil
    ) -> [NetworkDiagnosticsWorkbenchRow] {
        guard pagePhase != .idle else { return [] }

        return checkIDs.compactMap { id in
            let executionPhase = executionPhases[id] ?? .waiting
            if pagePhase == .running, executionPhase == .waiting {
                return nil
            }
            return NetworkDiagnosticsWorkbenchRow(
                id: id,
                executionPhase: executionPhase,
                result: results[id],
                pendingReason: pagePhase == .completed && results[id] == nil ? endReason : nil
            )
        }
    }

    static func stage(for checkID: NetworkDiagnosticCheckID) -> NetworkDiagnosticStage? {
        switch checkID {
        case .path, .dns, .proxy: .thisMac
        case .gatewayReachability: .lan
        case .internet: .internet
        case .ipv6: nil
        }
    }

    static func workbenchItems(
        pagePhase: NetworkDiagnosticsPagePhase,
        executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase],
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        checkIDs: [NetworkDiagnosticCheckID] = NetworkDiagnosticCheckID.allCases,
        endReason: DiagnosticRunEndReason? = nil
    ) -> [NetworkDiagnosticsWorkbenchItem] {
        let rows = workbenchRows(
            pagePhase: pagePhase,
            executionPhases: executionPhases,
            results: results,
            checkIDs: checkIDs,
            endReason: endReason
        )
        guard !rows.isEmpty else { return [] }

        var items: [NetworkDiagnosticsWorkbenchItem] = []
        for currentStage in NetworkDiagnosticStage.allCases {
            let stageRows = rows.filter { stage(for: $0.id) == currentStage }
            if stageRows.isEmpty { continue }
            items.append(.stageHeader(currentStage))
            items.append(contentsOf: stageRows.map { .check($0) })
        }
        let additionalRows = rows.filter { stage(for: $0.id) == nil }
        if !additionalRows.isEmpty {
            items.append(.additionalHeader)
            items.append(contentsOf: additionalRows.map { .check($0) })
        }
        return items
    }

}

@MainActor
@Observable
final class NetworkDiagnosticsViewModel {
    static let defaultSessionBudget = Duration.seconds(30)

    private(set) var phase = NetworkDiagnosticsPagePhase.idle
    private(set) var executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase]
    private(set) var results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [:]
    private(set) var logStore = NetworkDiagnosticsLogStore()
    private(set) var conclusion: NetworkDiagnosticConclusion?
    private(set) var assessment: NetworkDiagnosticAssessment?
    private(set) var endReason: DiagnosticRunEndReason?
    private(set) var pendingCheckIDs: [NetworkDiagnosticCheckID] = []
    private(set) var automaticRestartCount = 0
    private(set) var currentRunID: UUID?
    private(set) var fingerprintMonitoringAvailable = true
    let checkIDs: [NetworkDiagnosticCheckID]

    var logText: String { logStore.text }

    @ObservationIgnored private let checks: [any DiagnosticCheck]
    @ObservationIgnored private let fingerprintMonitor: any NetworkFingerprintMonitoring
    @ObservationIgnored private let contextSource: any DiagnosticNetworkContextSourcing
    @ObservationIgnored private let diagnosticGatewayMeasuring: any DiagnosticGatewayMeasuring
    @ObservationIgnored private let clock: any DiagnosticClock
    @ObservationIgnored private let usesProductionChecks: Bool
    @ObservationIgnored private let guidance: GuidanceCoordinator
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var runGeneration: UInt64 = 0
    @ObservationIgnored private var logSessionID: UUID?
    @ObservationIgnored private var logSessionStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var logRunNumber = 0
    @ObservationIgnored private var checkStartedAt: [NetworkDiagnosticCheckID: ContinuousClock.Instant] = [:]

    init(
    checks: [any DiagnosticCheck]? = nil,
    fingerprintMonitor: any NetworkFingerprintMonitoring = SystemNetworkFingerprintMonitor(
        routeStateSource: SystemNetworkFingerprintRouteStateSource()
    ),
    contextSource: any DiagnosticNetworkContextSourcing = SystemDiagnosticNetworkContextSource(),
    diagnosticGatewayMeasuring: any DiagnosticGatewayMeasuring = GatewayLatencyProvider(),
    clock: any DiagnosticClock = ContinuousDiagnosticClock(),
    guidance: GuidanceCoordinator = .shared
    ) {
        let productionChecks = checks == nil
        let configuredChecks = checks ?? Self.defaultChecks()
        self.checks = configuredChecks
        self.fingerprintMonitor = fingerprintMonitor
        self.contextSource = contextSource
        self.diagnosticGatewayMeasuring = diagnosticGatewayMeasuring
        self.clock = clock
        self.usesProductionChecks = productionChecks
        self.guidance = guidance
        self.checkIDs = configuredChecks.map(\.id)
        self.executionPhases = Dictionary(
            uniqueKeysWithValues: configuredChecks.map { ($0.id, .waiting) }
        )
    }

    private static func defaultChecks() -> [any DiagnosticCheck] {
        [
            NetworkConnectivityCheck(),
            GatewayReachabilityCheck(),
            DNSResolutionCheck(),
            HTTPSControlEndpointCheck(),
            SystemProxyCheck(),
            IPv6ControlEndpointCheck(),
        ]
    }

    deinit {
        activeTask?.cancel()
    }

    @discardableResult
    func start() -> Bool {
        guard activeTask == nil else { return false }

        results = [:]
        logStore.reset()
        logSessionID = UUID()
        logRunNumber = 0
        checkStartedAt.removeAll()
        logSessionStartedAt = ContinuousClock().now
        appendEvent(.sessionStarted)
        conclusion = nil
        assessment = nil
        endReason = nil
        pendingCheckIDs = checkIDs
        currentRunID = nil
        fingerprintMonitoringAvailable = true
        automaticRestartCount = 0
        phase = .running
        prepareExecutionPhases(retaining: [])
        runGeneration &+= 1
        let generation = runGeneration

        activeTask = Task { [weak self] in
            await self?.runSession(generation: generation)
        }
        return true
    }

    func waitForCompletion() async {
        let task = activeTask
        await task?.value
    }

    func cancel() {
        guard phase == .running else {
            activeTask?.cancel()
            activeTask = nil
            return
        }
        runGeneration &+= 1
        let cancelledRunID = currentRunID
        currentRunID = nil
        activeTask?.cancel()
        activeTask = nil
        endReason = .cancelled
        pendingCheckIDs = checkIDs.filter { results[$0] == nil }
        assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: results,
            complete: false,
            requiredIDs: Set(checkIDs)
        )
        conclusion = nil
        phase = .completed
        appendEvent(.cancelled, runID: cancelledRunID, pendingIDs: pendingCheckIDs)
        checkStartedAt.removeAll()
    }

    func clearLogs() {
        logStore.reset()
    }

    private func accept(_ result: NetworkDiagnosticResult, runID: UUID) {
        guard DiagnosticPublicationGate(activeRunID: currentRunID).accepts(runID) else { return }
        results[result.id] = result
        executionPhases[result.id] = .completed
        assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: results,
            complete: false,
            requiredIDs: Set(checkIDs)
        )
        let duration = checkStartedAt.removeValue(forKey: result.id).map {
            Self.milliseconds($0.duration(to: ContinuousClock().now))
        }
        appendEvent(
            .checkFinished, runID: runID, checkID: result.id,
            result: DiagnosticLogResult(result), durationMilliseconds: duration
        )
    }

    private func runSession(generation: UInt64) async {
        guard isCurrentGeneration(generation) else { return }
        let restartController = NetworkDiagnosticRestartController()
        let sessionDeadline = (await clock.now()).advanced(by: Self.defaultSessionBudget)

        await withTaskCancellationHandler {
            let fingerprintObservation = await boundedFingerprintObservation(
                until: min(
                    sessionDeadline,
                    (await clock.now()).advanced(by: .seconds(1))
                )
            )
            guard isCurrentGeneration(generation) else { return }
            if fingerprintObservation == nil {
                fingerprintMonitoringAvailable = false
            }
            guard !Task.isCancelled else {
                finish(
                    DiagnosticRunOutcome(
                        runID: UUID(),
                        results: [],
                        pendingIDs: checkIDs,
                        endReason: .cancelled
                    ),
                    generation: generation
                )
                return
            }
            await executeSession(
                fingerprintObservation: fingerprintObservation,
                restartController: restartController,
                sessionDeadline: sessionDeadline,
                generation: generation
            )
        } onCancel: {
            Task { await restartController.cancelCurrentRun() }
        }
        if generation == runGeneration {
            activeTask = nil
        }
    }

    private func executeSession(
        fingerprintObservation: NetworkFingerprintObservation?,
        restartController: NetworkDiagnosticRestartController,
        sessionDeadline: ContinuousClock.Instant,
        generation: UInt64
    ) async {
        let fingerprintState: NetworkDiagnosticsFingerprintStreamState? = fingerprintObservation.map {
            NetworkDiagnosticsFingerprintStreamState(baseline: $0.baseline)
        }
        let monitorTask: Task<Void, Never>? = fingerprintObservation.map { observation in
            return Task {
                for await fingerprint in observation.changes {
                    guard isCurrentGeneration(generation) else { break }
                    guard let previous = await fingerprintState?.accept(fingerprint) else { continue }
                    guard isCurrentGeneration(generation) else { break }
                    let now = await clock.now()
                    guard isCurrentGeneration(generation) else { break }
                    let shouldRestart = await restartController.observe(
                        fingerprint,
                        at: now
                    )
                    guard isCurrentGeneration(generation) else { break }
                    let runID = currentRunID ?? logSessionID
                    currentRunID = nil
                    if shouldRestart {
                        guard isCurrentGeneration(generation) else { break }
                        invalidateNetworkResultsForChange()
                        appendEvent(
                            .restarted,
                            runID: runID,
                            reasonCode: fingerprint.restartReason(comparedWith: previous).rawValue
                        )
                    }
                }
            }
        }
        defer { monitorTask?.cancel() }

        var retainedResults: [NetworkDiagnosticResult] = []
        while !Task.isCancelled {
            guard isCurrentGeneration(generation), await clock.now() < sessionDeadline else {
                finish(
                    DiagnosticRunOutcome(
                        runID: UUID(),
                        results: retainedResults,
                        pendingIDs: checkIDs.filter { id in
                            !retainedResults.contains { $0.id == id }
                        },
                        endReason: .timedOut
                    ),
                    generation: generation
                )
                return
            }
            let runID = UUID()
            currentRunID = runID
            logRunNumber += 1
            checkStartedAt.removeAll()
            appendEvent(.runStarted, runID: runID, retainedIDs: retainedResults.map(\.id))
            let context: DiagnosticNetworkContext?
            if usesProductionChecks {
                let remaining = await clock.now().duration(to: sessionDeadline)
                if remaining > .zero {
                    context = await contextSource.capture(
                        runID: runID,
                        timeout: min(remaining, .seconds(1))
                    )
                } else {
                    context = nil
                }
            } else {
                context = nil
            }
            guard isCurrentGeneration(generation) else {
                finish(
                    DiagnosticRunOutcome(
                        runID: runID,
                        results: retainedResults,
                        pendingIDs: checkIDs.filter { id in
                            !retainedResults.contains { $0.id == id }
                        },
                        endReason: .cancelled
                    ),
                    generation: generation
                )
                return
            }
            let checks = checksForRun(context: context)
            let runner = DiagnosticRunner(
                checks: checks,
                sessionBudget: Self.defaultSessionBudget,
                clock: clock
            )
            let retainedSnapshot = retainedResults
            let runTask = Task { [weak self] in
                await runner.run(
                    runID: runID,
                    retaining: retainedSnapshot,
                    deadline: sessionDeadline,
                    onCheckStarted: { [weak self] id in
                        await self?.beginCheck(id, runID: runID)
                    },
                    onResult: { [weak self] result in
                        await self?.accept(result, runID: runID)
                    }
                )
            }
            await restartController.install(runTask)
            let outcome = await runTask.value
            guard isCurrentGeneration(generation) else { return }

            let shouldRestart = await restartController.completeRun()
            guard isCurrentGeneration(generation) else { return }
            if shouldRestart {
                guard await restartController.waitForStability(
                    using: clock,
                    until: sessionDeadline
                ) else {
                    guard isCurrentGeneration(generation) else { return }
                    let retainedResults = configurationOnlyResults(from: outcome.results)
                    finish(
                        DiagnosticRunOutcome(
                            runID: outcome.runID,
                            results: retainedResults,
                            pendingIDs: checkIDs.filter { id in
                                !retainedResults.contains { $0.id == id }
                            },
                            endReason: .superseded
                        ),
                        generation: generation
                    )
                    return
                }
                guard isCurrentGeneration(generation) else { return }
                automaticRestartCount += 1
                retainedResults = configurationOnlyResults(from: outcome.results)
                currentRunID = nil
                results = Dictionary(uniqueKeysWithValues: retainedResults.map { ($0.id, $0) })
                conclusion = nil
                assessment = NetworkDiagnosticAssessmentResolver().resolve(
                    results: results,
                    complete: false,
                    requiredIDs: Set(checkIDs)
                )
                prepareExecutionPhases(retaining: retainedResults)
                continue
            }

            finish(outcome, generation: generation)
            return
        }
        guard generation == runGeneration else { return }
        finish(
            DiagnosticRunOutcome(
                runID: UUID(),
                results: retainedResults,
                pendingIDs: checkIDs.filter { id in
                    !retainedResults.contains { $0.id == id }
                },
                endReason: .cancelled
            ),
            generation: generation
        )
    }

    private func boundedFingerprintObservation(
        until deadline: ContinuousClock.Instant
    ) async -> NetworkFingerprintObservation? {
        let gate = NetworkFingerprintObservationCompletionGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard gate.install(continuation: continuation) else { return }

                let observationTask = Task { [fingerprintMonitor, gate] in
                    gate.finish(await fingerprintMonitor.observation())
                }
                let timeoutTask = Task { [clock, gate] in
                    do {
                        try await clock.sleep(until: deadline)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    gate.finish(nil)
                }
                gate.install(
                    observationTask: observationTask,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            gate.cancel()
        }
    }

    private func beginCheck(_ id: NetworkDiagnosticCheckID, runID: UUID) {
        guard DiagnosticPublicationGate(activeRunID: currentRunID).accepts(runID) else { return }
        executionPhases[id] = .checking
        checkStartedAt[id] = ContinuousClock().now
        appendEvent(.checkStarted, runID: runID, checkID: id)
    }

    private func checksForRun(context: DiagnosticNetworkContext?) -> [any DiagnosticCheck] {
        guard usesProductionChecks, let context else { return checks }
        return [
            NetworkConnectivityCheck(context: context),
            GatewayReachabilityCheck(
                context: context,
                gatewayMeasuring: diagnosticGatewayMeasuring
            ),
            DNSResolutionCheck(),
            HTTPSControlEndpointCheck(),
            SystemProxyCheck(),
            IPv6ControlEndpointCheck(),
        ]
    }

    private func configurationOnlyResults(
        from orderedResults: [NetworkDiagnosticResult]
    ) -> [NetworkDiagnosticResult] {
        let configurationOnlyIDs = Set(
            checks.filter { $0.rerunPolicy == .configurationOnly }.map(\.id)
        )
        return orderedResults.filter { configurationOnlyIDs.contains($0.id) }
    }

    private func prepareExecutionPhases(retaining retainedResults: [NetworkDiagnosticResult]) {
        let retainedIDs = Set(retainedResults.map(\.id))
        executionPhases = Dictionary(uniqueKeysWithValues: checkIDs.map { id in
            (id, retainedIDs.contains(id) ? .completed : .waiting)
        })
    }

    private func invalidateNetworkResultsForChange() {
        let retainedResults = configurationOnlyResults(from: Array(results.values))
        results = Dictionary(uniqueKeysWithValues: retainedResults.map { ($0.id, $0) })
        conclusion = nil
        assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: results,
            complete: false,
            requiredIDs: Set(checkIDs)
        )
        pendingCheckIDs = checkIDs.filter { results[$0] == nil }
        prepareExecutionPhases(retaining: retainedResults)
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generation == runGeneration && !Task.isCancelled
    }

    private func appendEvent(
        _ kind: DiagnosticEventKind,
        runID: UUID? = nil,
        checkID: NetworkDiagnosticCheckID? = nil,
        reasonCode: String? = nil,
        result: DiagnosticLogResult? = nil,
        durationMilliseconds: Int64? = nil,
        conclusion: NetworkDiagnosticConclusion? = nil,
        pendingIDs: [NetworkDiagnosticCheckID] = [],
        retainedIDs: [NetworkDiagnosticCheckID] = []
    ) {
        let eventRunID = runID ?? currentRunID ?? logSessionID ?? UUID()
        let elapsedMilliseconds: Int64
        if let startedAt = logSessionStartedAt {
            elapsedMilliseconds = Self.milliseconds(startedAt.duration(to: ContinuousClock().now))
        } else {
            elapsedMilliseconds = 0
        }
        logStore.append(NetworkDiagnosticEvent(
            runID: eventRunID,
            elapsedMilliseconds: elapsedMilliseconds,
            kind: kind,
            checkID: checkID,
            reasonCode: reasonCode,
            runNumber: logRunNumber,
            result: result,
            durationMilliseconds: durationMilliseconds,
            conclusion: conclusion,
            pendingIDs: pendingIDs,
            retainedIDs: retainedIDs
        ))
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return Int64(max(0, (Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000).rounded()))
    }

    private func finish(_ outcome: DiagnosticRunOutcome, generation: UInt64) {
        guard generation == runGeneration else { return }
        currentRunID = nil
        endReason = outcome.endReason
        pendingCheckIDs = outcome.pendingIDs
        results = Dictionary(uniqueKeysWithValues: outcome.results.map { ($0.id, $0) })
        assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: results,
            complete: outcome.endReason == .completed,
            requiredIDs: Set(checkIDs)
        )
        conclusion = assessment?.conclusion
        phase = .completed
        let endEvent: DiagnosticEventKind = switch outcome.endReason {
        case .completed: .completed
        case .timedOut, .superseded: .timedOut
        case .cancelled: .cancelled
        }
        appendEvent(
            endEvent,
            runID: outcome.runID,
            reasonCode: outcome.endReason == .superseded ? "network-change" : nil,
            conclusion: conclusion,
            pendingIDs: outcome.pendingIDs
        )
        if outcome.endReason == .completed, conclusion != nil {
            guidance.record(.diagnosticsCompleted)
        }
    }
}

private final class NetworkFingerprintObservationCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NetworkFingerprintObservation?, Never>?
    private var observationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var storedResult: NetworkFingerprintObservation?
    private var didFinish = false

    func install(
        continuation: CheckedContinuation<NetworkFingerprintObservation?, Never>
    ) -> Bool {
        lock.lock()
        guard !didFinish else {
            let result = storedResult
            lock.unlock()
            continuation.resume(returning: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(
        observationTask: Task<Void, Never>,
        timeoutTask: Task<Void, Never>
    ) {
        lock.lock()
        self.observationTask = observationTask
        self.timeoutTask = timeoutTask
        let shouldCancel = didFinish
        lock.unlock()

        if shouldCancel {
            observationTask.cancel()
            timeoutTask.cancel()
        }
    }

    func finish(_ result: NetworkFingerprintObservation?) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        storedResult = result
        let continuation = self.continuation
        self.continuation = nil
        let observationTask = self.observationTask
        let timeoutTask = self.timeoutTask
        self.observationTask = nil
        self.timeoutTask = nil
        lock.unlock()

        observationTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(returning: result)
    }

    func cancel() {
        finish(nil)
    }
}

private actor NetworkDiagnosticsFingerprintStreamState {
    private var latest: NetworkFingerprint

    init(baseline: NetworkFingerprint) {
        latest = baseline
    }

    func accept(_ fingerprint: NetworkFingerprint) -> NetworkFingerprint? {
        guard fingerprint != latest else { return nil }
        let previous = latest
        latest = fingerprint
        return previous
    }
}

actor NetworkDiagnosticRestartController {
    private var currentRunCancellation: (@Sendable () -> Void)?
    private var restartRequested = false
    private var restartInstallPending = false
    private var cancellationRequested = false
    private var finalized = false
    private var lastFingerprint: NetworkFingerprint?
    private var lastChangeAt: ContinuousClock.Instant?

    func install<Success: Sendable>(_ task: Task<Success, Never>) {
        currentRunCancellation = { task.cancel() }
        restartInstallPending = false
        if restartRequested || cancellationRequested {
            task.cancel()
        }
    }

    @discardableResult
    func observe(
        _ fingerprint: NetworkFingerprint,
        at now: ContinuousClock.Instant = ContinuousClock().now
    ) -> Bool {
        guard !finalized, !cancellationRequested else { return false }
        guard fingerprint != lastFingerprint else { return true }
        lastFingerprint = fingerprint
        lastChangeAt = now
        if restartInstallPending { return true }
        restartRequested = true
        currentRunCancellation?()
        return true
    }

    func waitForStability(
        using clock: any DiagnosticClock,
        until deadline: ContinuousClock.Instant
    ) async -> Bool {
        while !cancellationRequested, !finalized {
            guard let latestChangeAt = lastChangeAt else { return false }
            let stableAt = latestChangeAt.advanced(by: .milliseconds(500))
            let waitUntil = min(stableAt, deadline)
            try? await clock.sleep(until: waitUntil)
            if cancellationRequested || finalized { return false }
            let now = await clock.now()
            guard let latestChangeAt = lastChangeAt else { return false }
            let latestStableAt = latestChangeAt.advanced(by: .milliseconds(500))
            if now >= latestStableAt {
                restartInstallPending = false
                return true
            }
            if now >= deadline { return false }
        }
        return false
    }

    func completeRun() -> Bool {
        currentRunCancellation = nil
        if cancellationRequested {
            finalized = true
            return false
        }
        if restartRequested {
            restartRequested = false
            restartInstallPending = true
            return true
        }
        finalized = true
        return false
    }

    func cancelCurrentRun() {
        cancellationRequested = true
        restartRequested = false
        restartInstallPending = false
        currentRunCancellation?()
        currentRunCancellation = nil
    }
}

#if DEBUG
extension NetworkDiagnosticsViewModel {
    /// Debug-only: publishes a synthetic completed result so the real
    /// diagnostics host renders its production conclusion strip and the
    /// production invitation card, without running a real diagnostic. Never
    /// writes Timeline, diagnostic history, or user data; the production
    /// `record(.diagnosticsCompleted)` path is not invoked (Debug triggers
    /// schedule invitations explicitly).
    func debugStageCompletedResult() {
        activeTask?.cancel()
        activeTask = nil
        let staged = checkIDs.map { id in
            NetworkDiagnosticResult(id: id, status: .normal, summary: "Debug staged result")
        }
        results = Dictionary(uniqueKeysWithValues: staged.map { ($0.id, $0) })
        executionPhases = Dictionary(uniqueKeysWithValues: staged.map { ($0.id, .completed) })
        conclusion = NetworkDiagnosticConclusion.evaluate(
            staged,
            requiredIDs: Set(checkIDs)
        )
        phase = .completed
    }
}
#endif
