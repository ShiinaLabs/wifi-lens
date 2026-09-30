import Foundation
import WiFiLensCore

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

private extension ContinuousClock.Instant {
    func remainingDuration() -> Duration {
        max(.zero, ContinuousClock.now.duration(to: self))
    }
}
