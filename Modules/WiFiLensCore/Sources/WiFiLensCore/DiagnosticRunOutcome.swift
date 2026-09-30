import Foundation

enum DiagnosticRunEndReason: Equatable, Sendable {
    case completed
    case timedOut
    case cancelled
    case superseded
}

enum DiagnosticRestartReason: String, CaseIterable, Sendable {
    case route
    case address
    case dns
    case proxy
    case path
}

struct DiagnosticRunOutcome: Equatable, Sendable {
    let runID: UUID
    let results: [NetworkDiagnosticResult]
    let pendingIDs: [NetworkDiagnosticCheckID]
    let endReason: DiagnosticRunEndReason

    init(
        runID: UUID,
        results: [NetworkDiagnosticResult],
        pendingIDs: [NetworkDiagnosticCheckID] = [],
        endReason: DiagnosticRunEndReason
    ) {
        self.runID = runID
        self.results = results
        self.pendingIDs = pendingIDs
        self.endReason = endReason
    }
}

struct DiagnosticPublicationGate: Sendable {
    var activeRunID: UUID?

    func accepts(_ runID: UUID) -> Bool {
        activeRunID == runID
    }
}

protocol DiagnosticClock: Sendable {
    func now() async -> ContinuousClock.Instant
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

struct ContinuousDiagnosticClock: DiagnosticClock {
    private let clock = ContinuousClock()

    func now() async -> ContinuousClock.Instant {
        clock.now
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await clock.sleep(until: deadline)
    }
}
