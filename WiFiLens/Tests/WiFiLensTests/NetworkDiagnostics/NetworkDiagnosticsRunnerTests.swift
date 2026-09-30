import CFNetwork
import Foundation
import Network
import Testing
import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("remediation follows result status and final proxy facts")
    func remediationDecisionTable() {
        let result = NetworkDiagnosticResult(
            id: .proxy,
            status: .abnormal,
            summary: "Proxy authentication required",
            evidence: [.init(code: "proxy.authentication-required", value: "407")]
        )

        let remediation = NetworkDiagnosticRemediation.forResult(result)

        #expect(remediation.actionKey == "network_diagnostics.remediation.proxy_authentication.action")
        #expect(remediation.rerunKey == "network_diagnostics.remediation.rerun")

        let indeterminateResult = NetworkDiagnosticResult(
            id: .dns,
            status: .indeterminate,
            summary: "DNS could not be determined"
        )

        let indeterminateRemediation = NetworkDiagnosticRemediation.forResult(indeterminateResult)

        #expect(indeterminateRemediation.causeKey == "network_diagnostics.remediation.indeterminate.cause")
        #expect(indeterminateRemediation.actionKey == "network_diagnostics.remediation.indeterminate.action")

        let recoveredProxy = NetworkDiagnosticResult(
            id: .proxy,
            status: .indeterminate,
            summary: "proxy route recovered",
            evidence: [.init(code: "proxy.authentication-required", value: "407")],
            proxyFacts: .init(http: .available, https: .available)
        )

        #expect(NetworkDiagnosticRemediation.forResult(recoveredProxy).actionKey
            == "network_diagnostics.remediation.indeterminate.action")
    }

    @Test("runner applies the path and DNS dependency matrix")
    func runnerDependencyMatrix() async {
        let cases: [(overrides: [NetworkDiagnosticCheckID: NetworkDiagnosticStatus], statuses: [NetworkDiagnosticStatus], invocations: [NetworkDiagnosticCheckID])] = [
            (
                [.path: .abnormal],
                [.abnormal, .blocked, .blocked, .blocked, .blocked, .blocked],
                [.path]
            ),
            (
                [.path: .indeterminate],
                [.indeterminate, .normal, .normal, .normal, .normal, .normal],
                NetworkDiagnosticCheckID.allCases
            ),
            (
                [.dns: .indeterminate],
                [.normal, .normal, .indeterminate, .normal, .normal, .normal],
                NetworkDiagnosticCheckID.allCases
            ),
            (
                [.dns: .abnormal],
                [.normal, .normal, .abnormal, .normal, .normal, .normal],
                NetworkDiagnosticCheckID.allCases
            ),
            (
                [.gatewayReachability: .abnormal],
                [.normal, .abnormal, .normal, .normal, .normal, .normal],
                NetworkDiagnosticCheckID.allCases
            ),
        ]

        for testCase in cases {
            let recorder = DiagnosticTestRecorder()
            let checks: [any DiagnosticCheck] = NetworkDiagnosticCheckID.allCases.map { id in
                StubDiagnosticCheck(
                    id: id,
                    result: NetworkDiagnosticResult(
                        id: id,
                        status: testCase.overrides[id] ?? .normal,
                        summary: id.rawValue
                    ),
                    recorder: recorder
                )
            }

            let results = (await DiagnosticRunner(checks: checks).run { _ in }).results

            #expect(results.map(\.status) == testCase.statuses)
            #expect(await recorder.values == testCase.invocations)
            if testCase.overrides[.path] == .abnormal {
                #expect(results[1].evidence.contains(.init(code: "blocked.by", value: "path")))
            }
        }
    }

    @Test("runner executes checks and publishes results in order")
    func runnerOrder() async {
        let invocations = DiagnosticTestRecorder()
        let publications = DiagnosticTestRecorder()
        let checks: [any DiagnosticCheck] = NetworkDiagnosticCheckID.allCases.map { id in
            StubDiagnosticCheck(
                id: id,
                result: NetworkDiagnosticResult(id: id, status: .normal, summary: id.rawValue),
                recorder: invocations
            )
        }

        let results = (await DiagnosticRunner(checks: checks).run { result in
            await publications.record(result.id)
        }).results

        #expect(results.map(\.id) == NetworkDiagnosticCheckID.allCases)
        #expect(await invocations.values == NetworkDiagnosticCheckID.allCases)
        #expect(await publications.values == NetworkDiagnosticCheckID.allCases)
    }

    @Test("runner enforces an overall session budget")
    func runnerEnforcesOverallBudget() async {
        let probe = BudgetAwareDiagnosticProbe()
        let clock = ManualDiagnosticClock()
        let task = Task {
            await DiagnosticRunner(
                checks: [BudgetAwareDiagnosticCheck(probe: probe)],
                sessionBudget: .seconds(1),
                clock: clock
            ).run { _ in }
        }

        await probe.waitForInvocation()
        await clock.waitForSleeperCount(1)
        await clock.set(clock.origin.advanced(by: .seconds(1)))

        let outcome = await task.value

        #expect(await probe.wasCancelled)
        #expect(outcome.results.map(\.id) == [.path])
        #expect(outcome.results.first?.status == .indeterminate)
        #expect(outcome.results.first?.evidence == [.init(code: "check.timeout", value: nil)])
        #expect(outcome.pendingIDs.isEmpty)
        #expect(outcome.endReason == .timedOut)
    }

    @Test("runner returns when a cancelled check ignores cancellation")
    func runnerDoesNotWaitForCancellationIgnoringCheck() async {
        let probe = CancellationIgnoringDiagnosticProbe()
        let task = Task {
            await DiagnosticRunner(
                checks: [CancellationIgnoringProbeDiagnosticCheck(probe: probe)],
                sessionBudget: .seconds(30)
            ).run { _ in }
        }

        await probe.waitForInvocationCount(1)
        task.cancel()
        let outcome = await task.value

        #expect(outcome.results.isEmpty)
        #expect(outcome.pendingIDs == [.path])
        #expect(outcome.endReason == .cancelled)
        await probe.release(invocation: 1)
    }

    @Test("runner preserves completed results and identifies pending checks on cancellation")
    func runnerReturnsPartialCancelledOutcome() async {
        let probe = BlockingDiagnosticProbe()
        let checks: [any DiagnosticCheck] = [
            StubDiagnosticCheck(
                id: .path,
                result: .init(id: .path, status: .normal, summary: "path"),
                recorder: DiagnosticTestRecorder()
            ),
            BlockingProbeDiagnosticCheck(id: .gatewayReachability, probe: probe),
        ]
        let runner = DiagnosticRunner(checks: checks)
        let task = Task { await runner.run { _ in } }

        await probe.waitForInvocationCount(1)
        task.cancel()
        let outcome = await task.value

        #expect(outcome.results.map(\.id) == [.path])
        #expect(outcome.pendingIDs == [.gatewayReachability])
        #expect(outcome.endReason == .cancelled)
    }
}

