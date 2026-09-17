import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("route selection follows the kernel-selected interface")
    func routeSelectionUsesKernelInterface() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 192.0.2.1
          interface: en7
              flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
        """

        let result = DiagnosticRouteParser.parse(
            output: output,
            interfaceIndices: ["en0": 4, "en7": 12]
        )

        #expect(result == .selected(.init(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        )))

        let firstOrder = DiagnosticRouteParser.parse(
            output: output,
            interfaceIndices: ["en0": 4, "en7": 12]
        )
        let reversedOrder = DiagnosticRouteParser.parse(
            output: output,
            interfaceIndices: ["en7": 12, "en0": 4]
        )

        #expect(firstOrder == reversedOrder)
        #expect(firstOrder == .selected(.init(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        )))
        #expect(DiagnosticRouteParser.parse(
            output: output,
            interfaceIndices: ["en0": 4, "en7": 12]
        ) == .selected(.init(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        )))
    }

    @Test("route parser recognizes an active tunnel default without a gateway")
    func routeParserRecognizesTunnelDefaultWithoutGateway() {
        let output = """
        destination: default
        interface: utun6
        flags: <UP,DONE,CLONING,STATIC,GLOBAL>
        """

        let result = DiagnosticRouteParser.parse(
            output: output,
            interfaceIndices: ["utun6": 22]
        )

        #expect(result == .tunneled(.init(interfaceName: "utun6", interfaceIndex: 22)))
    }

    @Test("route parser rejects invalid, ambiguous, and unsupported default routes")
    func routeParserRejectsInvalidDefaultRoutes() {
        let ambiguousOutput = """
        destination: default
        gateway: 192.0.2.1
        gateway: 192.0.2.254
        interface: en7
        flags: <UP,GATEWAY>
        """

        #expect(DiagnosticRouteParser.parse(
            output: ambiguousOutput,
            interfaceIndices: ["en7": 12]
        ) == .ambiguous)

        let addresses = ["0.0.0.0", "224.0.0.1", "255.255.255.255", "not-an-ip"]

        for address in addresses {
            let output = "destination: default\ngateway: \(address)\ninterface: en7\nflags: <UP,GATEWAY>"
            let result = DiagnosticRouteParser.parse(
                output: output,
                interfaceIndices: ["en7": 12]
            )
            #expect(result == .unavailable)
        }

        let linkLayer = "destination: default\ngateway: link#4\ninterface: en7\nflags: <UP,GATEWAY>"
        let tunnel = "destination: default\ngateway: 192.0.2.1\ninterface: utun3\nflags: <UP,GATEWAY>"

        #expect(DiagnosticRouteParser.parse(
            output: linkLayer,
            interfaceIndices: ["en7": 12]
        ) == .unsupported)
        #expect(DiagnosticRouteParser.parse(
            output: tunnel,
            interfaceIndices: ["utun3": 20]
        ) == .tunneled(.init(interfaceName: "utun3", interfaceIndex: 20)))

        let missingRouteOutput = "gateway: 192.0.2.1\ninterface: en7\nflags: <UP,GATEWAY>"

        #expect(DiagnosticRouteParser.parse(
            output: missingRouteOutput,
            interfaceIndices: ["en7": 12]
        ) == .unavailable)

        let records = [
            "destination: default\ngateway: 192.0.2.1\ninterface: en7\nflags: <GATEWAY>",
            "destination: default\ngateway: 192.0.2.1\ninterface: en7\nflags: <UP>",
            "destination: default\ngateway: 192.0.2.1\ninterface: en7\nflags: <>"
        ]

        for output in records {
            #expect(DiagnosticRouteParser.parse(
                output: output,
                interfaceIndices: ["en7": 12]
            ) == .unavailable)
        }

        #expect(DiagnosticRouteParser.parse(
            output: "destination: default\ngateway: 192.0.2.1\ninterface: en7\nflags: <UP,GATEWAY>",
            interfaceIndices: ["en0": 4]
        ) == .unavailable)
    }

    @Test("route command timeout terminates the child without waiting for EOF")
    func routeCommandTimeoutDoesNotWaitForChild() async {
        let execution = DiagnosticRouteProcessExecution(
            executablePath: "/bin/sleep",
            arguments: ["5"],
            environment: [:],
            outputLimit: 1024
        )
        let startedAt = ContinuousClock.now
        let result = await execution.run(timeout: .milliseconds(50))
        let elapsed = startedAt.duration(to: ContinuousClock.now)

        #expect(result.timedOut)
        #expect(elapsed < .seconds(2))
    }

    @Test("diagnostic gateway ping binds the selected interface")
    func diagnosticGatewayPingBindsSelectedInterface() async {
        let runner = RecordingGatewayPingProcessRunner(latency: 2.5)
        let pinger = GatewayPinger(processRunner: runner)
        let target = DiagnosticGatewayTarget(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        )

        _ = await pinger.ping(target: target)

        #expect(await runner.executablePath == "/sbin/ping")
        #expect(await runner.arguments == [
            "-b", "en7", "-c", "1", "-W", "1000", "192.0.2.1"
        ])
    }

    @Test("overlapping gateway pings preserve the latest cancellation owner")
    func overlappingGatewayPingsPreserveCancellationOwnership() async {
        let runner = ControlledGatewayPingProcessRunner()
        let pinger = GatewayPinger(processRunner: runner)

        let first = Task {
            await pinger.ping(host: "first.example")
        }
        await runner.waitUntilInvocationCount(1)

        let second = Task {
            await pinger.ping(host: "second.example")
        }
        await runner.waitUntilInvocationCount(2)

        await runner.cancel()

        #expect(await first.value == nil)
        #expect(await second.value == nil)
        #expect(await runner.invocationCount == 2)
        #expect(await runner.cancelledInvocationIDs == [1, 2])
    }

    @Test("contextual path and gateway checks use one selected interface")
    func contextualChecksShareSelectedRouteTarget() async {
        let context = makeDiagnosticContext(
            pathState: .satisfied,
            route: .selected(.init(
                interfaceName: "en7",
                interfaceIndex: 12,
                address: "192.0.2.1"
            )),
            interfaces: [
                makeNetworkInterface(name: "en0", router: "192.0.2.1"),
                makeNetworkInterface(name: "en7", router: "192.0.2.1"),
            ]
        )
        let gateway = RecordingDiagnosticGatewayMeasurer()

        let pathResult = await NetworkConnectivityCheck(context: context).run()
        let gatewayResult = await GatewayReachabilityCheck(
            context: context,
            gatewayMeasuring: gateway,
            routeSource: nil
        ).run()

        #expect(pathResult.evidence.contains(.init(code: "path.interface", value: "en7")))
        #expect(pathResult.evidence.contains(.init(code: "path.gateway", value: "192.0.2.1")))
        #expect(gatewayResult.evidence.contains(.init(code: "gateway.interface", value: "en7")))
        #expect(await gateway.targets == [
            .init(interfaceName: "en7", interfaceIndex: 12, address: "192.0.2.1")
        ])
    }

    @Test("VPN route probes the uniquely identified physical underlay gateway")
    func vpnRouteProbesPhysicalUnderlayGateway() async {
        let context = makeDiagnosticContext(
            pathState: .satisfied,
            route: .tunneled(.init(interfaceName: "utun6", interfaceIndex: 22)),
            interfaces: [makeNetworkInterface(name: "en0", router: "192.0.2.1")]
        )
        let gateway = RecordingDiagnosticGatewayMeasurer()

        let result = await GatewayReachabilityCheck(
            context: context,
            gatewayMeasuring: gateway,
            routeSource: nil,
            interfaceIndexProvider: { name in name == "en0" ? 4 : 0 }
        ).run()

        #expect(result.status == .normal)
        #expect(result.evidence.contains(.init(code: "gateway.route-selection", value: "tunneled")))
        #expect(result.evidence.contains(.init(code: "gateway.probe-scope", value: "underlying-lan")))
        #expect(result.evidence.contains(.init(code: "gateway.interface", value: "en0")))
        #expect(result.evidence.contains(.init(code: "gateway.address", value: "192.0.2.1")))
        #expect(await gateway.targets == [
            .init(interfaceName: "en0", interfaceIndex: 4, address: "192.0.2.1")
        ])
    }

    @Test("VPN route skips gateway probing when no physical underlay gateway is identifiable")
    func vpnRouteSkipsGatewayProbeWithoutPhysicalUnderlay() async {
        let context = makeDiagnosticContext(
            pathState: .satisfied,
            route: .tunneled(.init(interfaceName: "utun6", interfaceIndex: 22))
        )
        let gateway = RecordingDiagnosticGatewayMeasurer()

        let result = await GatewayReachabilityCheck(
            context: context,
            gatewayMeasuring: gateway,
            routeSource: nil,
            interfaceIndexProvider: { _ in 0 }
        ).run()

        #expect(result.status == .skipped)
        #expect(result.evidence.contains(.init(code: "gateway.route-selection", value: "tunneled")))
        #expect(await gateway.targets.isEmpty)
    }

    @Test("context capture accepts a stable route")
    func diagnosticContextCaptureAcceptsStableRoute() async {
        let route = DiagnosticRouteSelection.selected(.init(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        ))
        let routeSource = SequencedDiagnosticRouteSource(values: [route, route])
        let source = SystemDiagnosticNetworkContextSource(
            routeSource: routeSource,
            pathSource: StubPathSource(.satisfied),
            interfaceSource: StubNetworkInterfaceSnapshotSource(interfaces: [])
        )

        let context = await source.capture(runID: UUID(), timeout: .seconds(1))

        #expect(context?.route == route)
        #expect(context?.pathState == .satisfied)
        #expect(await routeSource.invocationCount == 2)
    }

    @Test("context capture does not publish a conflicting route")
    func diagnosticContextCaptureRejectsChangingRoute() async {
        let first = DiagnosticRouteSelection.selected(.init(
            interfaceName: "en0",
            interfaceIndex: 4,
            address: "192.0.2.1"
        ))
        let second = DiagnosticRouteSelection.selected(.init(
            interfaceName: "en7",
            interfaceIndex: 12,
            address: "192.0.2.1"
        ))
        let routeSource = SequencedDiagnosticRouteSource(values: [first, second, first, second])
        let source = SystemDiagnosticNetworkContextSource(
            routeSource: routeSource,
            pathSource: StubPathSource(.satisfied),
            interfaceSource: StubNetworkInterfaceSnapshotSource(interfaces: [])
        )

        let context = await source.capture(runID: UUID(), timeout: .seconds(1))

        #expect(context?.route == .ambiguous)
        #expect(await routeSource.invocationCount == 4)
    }

    @Test("route change during gateway ping suppresses the old result")
    func gatewayRouteChangeSuppressesStaleResult() async {
        let target = DiagnosticGatewayTarget(
            interfaceName: "en0",
            interfaceIndex: 4,
            address: "192.0.2.1"
        )
        let context = makeDiagnosticContext(
            pathState: .satisfied,
            route: .selected(target)
        )
        let gateway = RecordingDiagnosticGatewayMeasurer()
        let routeSource = SequencedDiagnosticRouteSource(values: [.unavailable])

        let result = await GatewayReachabilityCheck(
            context: context,
            gatewayMeasuring: gateway,
            routeSource: routeSource
        ).run()

        #expect(result.status == .indeterminate)
        #expect(result.evidence.contains(.init(code: "gateway.route-changed", value: nil)))
    }

    @Test("missing diagnostic route never starts a gateway ping")
    func missingDiagnosticRouteDoesNotPing() async {
        let context = makeDiagnosticContext(pathState: .satisfied, route: .unavailable)
        let gateway = RecordingDiagnosticGatewayMeasurer()

        let result = await GatewayReachabilityCheck(
            context: context,
            gatewayMeasuring: gateway
        ).run()

        #expect(result.status == .indeterminate)
        #expect(await gateway.targets.isEmpty)
    }

    @Test("system path check maps path states")
    func pathMapping() async {
        let satisfied = await NetworkConnectivityCheck(pathSource: StubPathSource(.satisfied)).run()
        #expect(satisfied.id == .path)
        #expect(satisfied.status == .normal)
        #expect(await NetworkConnectivityCheck(pathSource: StubPathSource(.unsatisfied)).run().status == .abnormal)
        #expect(await NetworkConnectivityCheck(pathSource: StubPathSource(.requiresConnection)).run().status == .indeterminate)
        #expect(await NetworkConnectivityCheck(pathSource: StubPathSource(nil)).run().status == .indeterminate)
    }

    @Test("gateway reachability outcomes preserve latency, nonresponse, and missing-router semantics")
    func gatewayReachabilityOutcomeMatrix() async {
        let result = await GatewayReachabilityCheck(
            interfaceSource: StubNetworkInterfaceSource(interface: makeNetworkInterface(router: "192.0.2.1")),
            gatewayLatency: StubGatewayLatencyProvider(result: GatewayLatencyResult(
                timestamp: Date(),
                routerIP: "192.0.2.1",
                latencyMs: 2.5
            ))
        ).run()

        #expect(result.id == .gatewayReachability)
        #expect(result.status == .normal)
        #expect(result.evidence.contains(.init(code: "gateway.latency-ms", value: "2.5")))

        let nonresponse = await GatewayReachabilityCheck(
            interfaceSource: StubNetworkInterfaceSource(interface: makeNetworkInterface(router: "192.0.2.1")),
            gatewayLatency: StubGatewayLatencyProvider(result: GatewayLatencyResult(
                timestamp: Date(),
                routerIP: "192.0.2.1",
                error: .gatewayPingFailed("192.0.2.1")
            ))
        ).run()

        #expect(nonresponse.status == .indeterminate)
        #expect(nonresponse.evidence.contains(.init(code: "gateway.no-response", value: "192.0.2.1")))

        let missingRouter = await GatewayReachabilityCheck(
            interfaceSource: StubNetworkInterfaceSource(interface: makeNetworkInterface(router: nil)),
            gatewayLatency: StubGatewayLatencyProvider(result: GatewayLatencyResult(
                timestamp: Date(),
                error: .missingRouterIP
            ))
        ).run()

        #expect(missingRouter.status == .indeterminate)
        #expect(missingRouter.evidence.contains(.init(code: "gateway.unavailable", value: nil)))
    }

    @Test("successful HTTPS access neutralizes gateway ICMP nonresponse")
    func gatewayNonresponseDoesNotDowngradeSuccessfulHTTPS() {
        var results = makeResults(
            path: .normal,
            gateway: .indeterminate,
            dns: .normal,
            internet: .normal,
            proxy: .normal
        )
        results[1] = NetworkDiagnosticResult(
            id: .gatewayReachability,
            status: .indeterminate,
            summary: "gateway did not answer ICMP",
            evidence: [.init(code: "gateway.no-response", value: "192.0.2.1")]
        )
        results[3] = NetworkDiagnosticResult(
            id: .internet,
            status: .normal,
            summary: "HTTPS available",
            evidence: [.init(code: "https.available", value: "200")]
        )

        let assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) }),
            complete: true
        )

        #expect(assessment.conclusion == .networkNormal)
        #expect(assessment.primaryIssue == nil)
        #expect(assessment.stages.first { $0.stage == .lan }?.status == .indeterminate)
    }

    @Test("skipped VPN gateway does not make a healthy assessment actionable")
    func skippedVPNGatewayDoesNotMakeHealthyAssessmentActionable() {
        var results = makeResults(
            path: .normal,
            gateway: .skipped,
            dns: .normal,
            internet: .normal,
            ipv6: .indeterminate,
            proxy: .normal
        )
        results[1] = NetworkDiagnosticResult(
            id: .gatewayReachability,
            status: .skipped,
            summary: "Gateway check not applicable",
            evidence: [.init(code: "gateway.route-selection", value: "tunneled")]
        )

        let assessment = NetworkDiagnosticAssessmentResolver().resolve(
            results: Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) }),
            complete: true
        )

        #expect(assessment.conclusion == .networkNormal)
        #expect(assessment.primaryIssue == nil)
        #expect(assessment.stages.first { $0.stage == .lan }?.status == .skipped)
    }

    @Test("path check keeps interface evidence without gateway latency")
    func pathCheckKeepsInterfaceEvidence() async {
        let result = await NetworkConnectivityCheck(
            pathSource: StubPathSource(.satisfied),
            interfaceSource: StubNetworkInterfaceSource(interface: makeNetworkInterface(router: "192.0.2.1"))
        ).run()

        #expect(result.status == .normal)
        #expect(result.evidence.contains(.init(code: "path.interface", value: "en0")))
        #expect(result.evidence.contains(.init(code: "path.local-ip", value: "192.0.2.10")))
        #expect(result.evidence.contains(.init(code: "path.router", value: "192.0.2.1")))
        #expect(!result.evidence.contains { $0.code.hasPrefix("gateway.") })
    }
}
