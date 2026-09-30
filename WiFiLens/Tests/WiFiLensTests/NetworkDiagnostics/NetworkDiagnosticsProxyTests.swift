import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("proxy configuration and candidate parsing preserve routing semantics")
    func proxyConfigurationAndCandidateMatrices() {
        let configuration = SystemProxyConfiguration(settings: [
            "HTTPEnable": 1,
            "HTTPProxy": " Proxy.Example ",
            "HTTPPort": 8080,
            "HTTPSEnable": 1,
            "HTTPSProxy": "proxy.example",
            "HTTPSPort": 8080,
            "SOCKSEnable": 1,
            "SOCKSProxy": "socks.example",
            "SOCKSPort": 1080,
        ])

        #expect(configuration.endpoints == [
            ProxyEndpoint(host: "proxy.example", port: 8080),
            ProxyEndpoint(host: "socks.example", port: 1080),
        ])
        #expect(!configuration.hasInvalidExplicitProxy)

        let pacConfiguration = SystemProxyConfiguration(settings: [
            "ProxyAutoConfigEnable": 1,
            "ProxyAutoConfigURLString": "https://proxy.example/config.pac",
            "ProxyAutoDiscoveryEnable": 1,
        ])

        #expect(pacConfiguration.pacEnabled)
        #expect(pacConfiguration.pacURL == "https://proxy.example/config.pac")
        #expect(pacConfiguration.autoDiscoveryEnabled)

        let staticCandidates = SystemProxyResolver.candidates(from: [
            proxyDictionary(type: kCFProxyTypeHTTP, host: "127.0.0.1", port: 7890),
            proxyDictionary(type: kCFProxyTypeNone),
        ])
        #expect(staticCandidates == [
            .http(.init(host: "127.0.0.1", port: 7890)),
            .direct,
        ])

        let pacCandidates = SystemPACResolver.resolution(from: [
            proxyDictionary(type: kCFProxyTypeHTTP, host: "proxy.example", port: 8080),
            proxyDictionary(type: kCFProxyTypeNone),
        ])
        #expect(pacCandidates == ProxyCandidateResolution(
            candidates: [
                .http(.init(host: "proxy.example", port: 8080)),
                .direct,
            ],
            evidenceCodes: []
        ))

        let script = "function FindProxyForURL(url, host) { return 'DIRECT'; }"
        let dictionary: NSDictionary = [
            kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationJavaScript,
            kCFProxyAutoConfigurationJavaScriptKey as String: script,
        ]
        #expect(SystemProxyResolver.directive(from: dictionary) == .pacScript(script))
        #expect(SystemProxyResolver.directive(from: proxyDictionary(
            type: kCFProxyTypeHTTP,
            host: " \n\t ",
            port: 8080
        )) == .unavailable("proxy-endpoint-invalid"))
        let directDictionary: NSDictionary = [
            kCFProxyTypeKey as String: kCFProxyTypeNone,
        ]
        #expect(SystemProxyResolver.directive(from: directDictionary) == .direct)
    }

    @Test("PAC result chooses DIRECT without probing a stale explicit endpoint")
    func pacCanChooseDirect() async {
        let controlURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let recorder = PACResolutionTestRecorder()
        let resolver = SystemProxyResolver(
            pacTimeout: .milliseconds(25),
            configurationResolver: StubProxyConfigurationResolver(.pac(pacURL)),
            pacResolver: StubPACResolver(.direct, recorder: recorder)
        )
        let resolution = await resolver.resolve(for: controlURL)

        #expect(resolution == ProxyCandidateResolution(candidates: [.direct], evidenceCodes: []))
        #expect(await recorder.requests == [
            .init(pacURL: pacURL, targetURL: controlURL, timeout: .milliseconds(25)),
        ])
    }

    @Test("inline PAC scripts execute at their ordered directive position")
    func inlinePACScriptPreservesDirectiveOrder() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let script = "function FindProxyForURL(url, host) { return 'SOCKS proxy.example:1080'; }"
        let first = EffectiveProxy.http(.init(host: "first.example", port: 8080))
        let inline = EffectiveProxy.socks(.init(host: "proxy.example", port: 1080))
        let executor = ControlledPACCallbackExecutor()
        let resolver = SystemProxyResolver(
            configurationResolver: StubProxyConfigurationResolver([
                .http(.init(host: "first.example", port: 8080)),
                .pacScript(script),
                .direct,
            ]),
            pacResolver: SystemPACResolver(callbackExecutor: executor)
        )
        let task = Task { await resolver.resolve(for: target) }

        let request = await executor.nextRequest()
        #expect(request == .init(source: .script(script), targetURL: target))
        executor.complete(.success(.init(candidates: [inline], evidenceCodes: [])))
        let resolution = await task.value

        #expect(resolution == .init(candidates: [first, inline, .direct], evidenceCodes: []))
    }

    @Test("PAC callback errors resume with execution-failed evidence")
    func pacCallbackErrorResumesContinuation() async {
        let target = URL(string: "https://www.apple.com/")!
        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let executor = ControlledPACCallbackExecutor()
        let resolver = SystemPACResolver(callbackExecutor: executor)
        let task = Task {
            await resolver.resolve(pacURL: pacURL, targetURL: target, timeout: .seconds(30))
        }

        let request = await executor.nextRequest()
        #expect(request == .init(source: .url(pacURL), targetURL: target))
        executor.complete(.failure)
        let resolution = await task.value

        #expect(resolution == .init(candidates: [], evidenceCodes: ["pac-execution-failed"]))
        #expect(executor.executionWasCancelled)
    }

    @Test("PAC callback cancellation resumes once with cancellation evidence")
    func pacCallbackCancellationResumesContinuation() async {
        let target = URL(string: "https://www.apple.com/")!
        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let executor = ControlledPACCallbackExecutor()
        let resolver = SystemPACResolver(callbackExecutor: executor)
        let task = Task {
            await resolver.resolve(pacURL: pacURL, targetURL: target, timeout: .seconds(30))
        }

        _ = await executor.nextRequest()
        task.cancel()
        let resolution = await task.value

        #expect(resolution == .init(candidates: [], evidenceCodes: ["pac-cancelled"]))
        #expect(executor.executionWasCancelled)
    }

    @Test("PAC callback timeout resumes once and cancels execution")
    func pacCallbackTimeoutResumesContinuation() async {
        let target = URL(string: "https://www.apple.com/")!
        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let executor = ControlledPACCallbackExecutor()
        let resolver = SystemPACResolver(callbackExecutor: executor)
        let task = Task {
            await resolver.resolve(pacURL: pacURL, targetURL: target, timeout: .milliseconds(10))
        }

        _ = await executor.nextRequest()
        let resolution = await task.value

        #expect(resolution == .init(candidates: [], evidenceCodes: ["pac-timeout"]))
        #expect(executor.executionWasCancelled)
    }

    @Test("invalid proxy candidate preserves later valid candidate and evidence")
    func invalidProxyCandidatePreservesLaterCandidate() async {
        let validProxy = EffectiveProxy.http(.init(host: "proxy.example", port: 8080))
        let resolver = SystemProxyResolver(
            configurationResolver: StubProxyConfigurationResolver(
                SystemProxyResolver.directives(from: [
                    proxyDictionary(type: kCFProxyTypeHTTP),
                    proxyDictionary(
                        type: kCFProxyTypeHTTP,
                        host: "proxy.example",
                        port: 8080
                    ),
                ])
            ),
            pacResolver: StubPACResolver(.direct)
        )

        let resolution = await resolver.resolve(
            for: URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        )

        #expect(resolution.candidates == [validProxy])
        #expect(resolution.evidenceCodes == ["proxy-endpoint-invalid"])
    }

    @Test("DIRECT does not probe a stale explicit endpoint or proxy egress")
    func directSkipsStaleProxy() async {
        let connectorRecorder = ProxyConnectorTestRecorder()
        let egressRecorder = ProxyEgressTestRecorder()
        let check = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: RecordingProxyConnector(reachable: false, recorder: connectorRecorder),
            egressLoader: StubProxyEgressLoader(statusCode: nil, errorCode: "unexpected", recorder: egressRecorder),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let result = await check.run()

        #expect(result.status == .indeterminate)
        #expect(await connectorRecorder.endpoints.isEmpty)
        #expect(await egressRecorder.requests.isEmpty)
    }

    @Test("tunnel route detection preserves source and candidate priority")
    func tunnelRouteMatrix() async {
        let check = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: StubProxyConnector(reachable: false),
            egressLoader: StubProxyEgressLoader(statusCode: nil, errorCode: "unexpected"),
            tunnelReader: StubProxyTunnelStateReader(interface: "utun98")
        )

        let result = await check.run()

        #expect(result.status == .normal)
        #expect(result.summary == String(
            localized: "network_diagnostics.proxy.tunnel_routes.summary",
            comment: "Network self-check tunneled proxy route result summary"
        ))
        #expect(result.evidence.contains(.init(code: "proxy.http.route-type", value: "tunnel")))
        #expect(result.evidence.contains(.init(code: "proxy.https.route-type", value: "tunnel")))
        #expect(result.evidence.contains(.init(code: "proxy.http.tunnel-interface", value: "utun98")))
        #expect(result.evidence.contains(.init(code: "proxy.https.tunnel-interface", value: "utun98")))
        #expect(result.evidence.contains(.init(code: "proxy.http.tunnel-detection-source", value: "nwpath")))
        #expect(result.evidence.contains(.init(code: "proxy.https.tunnel-detection-source", value: "nwpath")))
        #expect(result.evidence.contains(.init(code: "proxy.http.egress-status", value: "base-check")))

        let activeResult = await SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: StubProxyConnector(reachable: false),
            egressLoader: StubProxyEgressLoader(statusCode: nil, errorCode: "unexpected"),
            tunnelReader: StubProxyTunnelStateReader(
                interface: "utun98",
                source: .activeInterface
            )
        ).run()

        #expect(activeResult.status == .normal)
        #expect(activeResult.summary == String(
            localized: "network_diagnostics.proxy.tunnel_routes_active.summary",
            comment: "Network self-check active tunnel interface proxy route result summary"
        ))
        #expect(activeResult.evidence.contains(.init(code: "proxy.http.route-type", value: "tunnel")))
        #expect(activeResult.evidence.contains(.init(code: "proxy.http.tunnel-detection-source", value: "active-interface")))
        #expect(activeResult.evidence.contains(.init(code: "proxy.https.tunnel-detection-source", value: "active-interface")))

        #expect(SystemProxyTunnelStateReader.candidateTunnelState(
            pathRouted: "utun3",
            activeIPv4Tunnels: ["utun98"]
        ) == ProxyTunnelState(interface: "utun3", source: .nwpath))
        #expect(SystemProxyTunnelStateReader.candidateTunnelState(
            pathRouted: nil,
            activeIPv4Tunnels: ["utun98"]
        ) == ProxyTunnelState(interface: "utun98", source: .activeInterface))
        #expect(SystemProxyTunnelStateReader.candidateTunnelState(
            pathRouted: nil,
            activeIPv4Tunnels: []
        ) == nil)
    }

    @Test("tunnel path wait returns nil when the timeout fires before any path")
    func tunnelPathWaitTimeoutWins() async {
        let streamTerminated = LockedFlag()
        let neverEnding = AsyncStream<NWPath> { continuation in
            continuation.onTermination = { _ in streamTerminated.set() }
        }

        let path = await SystemProxyTunnelStateReader.firstPath(
            from: neverEnding,
            timeout: {}
        )

        #expect(path == nil)
        #expect(streamTerminated.isSet)
    }

    @Test("tunnel path wait cancels the pending timeout when the path side completes first")
    func tunnelPathWaitCancelsPendingTimeout() async {
        let probe = TunnelTimeoutCancellationProbe()
        let finished = AsyncStream<NWPath> { continuation in
            continuation.finish()
        }

        let path = await SystemProxyTunnelStateReader.firstPath(
            from: finished,
            timeout: { await probe.park() }
        )

        #expect(path == nil)
        #expect(probe.didCancel)
    }

    @Test("failed proxy candidate falls back to DIRECT for the same target")
    func failedProxyCandidateFallsBackToDirect() async {
        let httpURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let staleEndpoint = ProxyEndpoint(host: "stale.example", port: 8080)
        let connectorRecorder = ProxyConnectorTestRecorder()
        let egressRecorder = ProxyEgressTestRecorder()
        let check = SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [
                httpURL: .init(candidates: [.http(staleEndpoint), .direct], evidenceCodes: []),
                httpsURL: .init(candidates: [.direct], evidenceCodes: []),
            ]),
            connector: RecordingProxyConnector(reachable: false, recorder: connectorRecorder),
            egressLoader: StubProxyEgressLoader(
                statusCode: 200,
                recorder: egressRecorder
            ),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let result = await check.run()

        #expect(result.status == .indeterminate)
        #expect(result.evidence.contains(.init(code: "proxy.http.endpoint-status", value: "unavailable")))
        #expect(result.evidence.contains(.init(code: "proxy.http.candidate-index", value: "1")))
        #expect(result.evidence.contains(.init(code: "proxy.http.route-type", value: "direct")))
        #expect(result.evidence.contains(.init(code: "proxy.http.fallback-used", value: "true")))
        #expect(await connectorRecorder.endpoints == [staleEndpoint])
        #expect(await egressRecorder.requests.isEmpty)
    }

    @Test("failed first proxy tries the next proxy candidate")
    func failedFirstProxyTriesNextProxy() async {
        let httpURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let staleEndpoint = ProxyEndpoint(host: "stale.example", port: 8080)
        let workingEndpoint = ProxyEndpoint(host: "working.example", port: 8081)
        let selectedProxy = EffectiveProxy.http(workingEndpoint)
        let connector = SequencedProxyConnector(outcomes: [false, true])
        let egressRecorder = ProxyEgressTestRecorder()
        let check = SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [
                httpURL: .init(
                    candidates: [.http(staleEndpoint), selectedProxy],
                    evidenceCodes: []
                ),
                httpsURL: .init(candidates: [.direct], evidenceCodes: []),
            ]),
            connector: connector,
            egressLoader: StubProxyEgressLoader(statusCode: 204, recorder: egressRecorder),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let result = await check.run()

        #expect(result.status == .indeterminate)
        #expect(await connector.endpoints == [staleEndpoint, workingEndpoint])
        #expect(await egressRecorder.requests.map(\.proxy) == [selectedProxy])
        #expect(result.evidence.contains(.init(code: "proxy.http.candidate-index", value: "1")))
        #expect(result.evidence.contains(.init(code: "proxy.http.fallback-used", value: "true")))
    }

    @Test("candidate attempts share one controlled overall timeout")
    func proxyCandidateAttemptsShareTimeout() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let firstProxy = EffectiveProxy.http(.init(host: "first.example", port: 8080))
        let secondProxy = EffectiveProxy.http(.init(host: "second.example", port: 8081))
        let connector = SequencedProxyConnector(outcomes: [true, true])
        let egressLoader = SequencedProxyEgressLoader(
            responses: [
                .init(statusCode: nil, errorCode: "timed-out"),
                .init(statusCode: 200, errorCode: nil),
            ],
            delays: [.zero, .zero]
        )
        let clock = SequencedProxyCheckClock(offsets: [
            .zero,
            .zero,
            .milliseconds(250),
            .milliseconds(1_200),
            .milliseconds(1_300),
        ])
        let check = SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [:]),
            connector: connector,
            egressLoader: egressLoader,
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
            timeout: .seconds(2),
            clock: clock
        )

        let result = await check.evaluate(
            target: target,
            resolution: .init(candidates: [firstProxy, secondProxy], evidenceCodes: []),
            timeout: .seconds(2)
        )

        #expect(result.status == .proxied)
        #expect(result.selectedCandidateIndex == 1)
        #expect(result.selectedProxy == secondProxy)
        #expect(await connector.endpoints == [
            .init(host: "first.example", port: 8080),
            .init(host: "second.example", port: 8081),
        ])
        #expect(await connector.timeouts == [.seconds(1), .milliseconds(800)])
        #expect(await egressLoader.timeouts == [.milliseconds(750), .milliseconds(700)])
    }

    @Test("an expired overall proxy timeout does not start another candidate")
    func expiredProxyTimeoutStopsCandidateFallback() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let firstProxy = EffectiveProxy.http(.init(host: "first.example", port: 8080))
        let secondProxy = EffectiveProxy.http(.init(host: "second.example", port: 8081))
        let connector = SequencedProxyConnector(outcomes: [true, true])
        let egressLoader = SequencedProxyEgressLoader(
            responses: [.init(statusCode: nil, errorCode: "timed-out")],
            delays: [.zero]
        )
        let clock = SequencedProxyCheckClock(offsets: [
            .zero,
            .zero,
            .milliseconds(250),
            .milliseconds(2_100),
        ])
        let check = SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [:]),
            connector: connector,
            egressLoader: egressLoader,
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
            timeout: .seconds(2),
            clock: clock
        )

        let result = await check.evaluate(
            target: target,
            resolution: .init(candidates: [firstProxy, secondProxy], evidenceCodes: []),
            timeout: .seconds(2)
        )

        #expect(result.status == .unavailable)
        #expect(await connector.endpoints == [.init(host: "first.example", port: 8080)])
        #expect(await connector.timeouts == [.seconds(1)])
        #expect(await egressLoader.timeouts == [.milliseconds(750)])
        #expect(result.evidence.contains(.init(code: "proxy.http.timeout", value: "expired")))
    }

    @Test("proxy check resolves the HTTP and HTTPS targets independently")
    func proxyTargetsAreResolvedIndependently() async {
        let recorder = ProxyResolutionTestRecorder()
        let httpURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let httpsProxy = EffectiveProxy.https(.init(host: "secure-proxy.example", port: 8443))
        let resolver = RecordingProxyResolver(
            resolutions: [
                httpURL: .init(candidates: [.direct], evidenceCodes: []),
                httpsURL: .init(candidates: [httpsProxy], evidenceCodes: []),
            ],
            recorder: recorder
        )
        let check = SystemProxyCheck(
            resolver: resolver,
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let result = await check.run()
        let resolvedURLs = await recorder.urls

        #expect(resolvedURLs.count == 2)
        #expect(Set(resolvedURLs) == Set([httpURL.absoluteString, httpsURL.absoluteString]))
        #expect(result.status == .indeterminate)
        #expect(result.summary == String(
            localized: "network_diagnostics.proxy.mixed_routing.summary",
            comment: "Network self-check mixed target proxy routing result summary"
        ))
    }

    @Test("proxy target routes preserve direct, proxied, and unresolved outcome states")
    func proxyTargetOutcomeMatrix() async {
        let recorder = ProxyResolutionTestRecorder()
        let resolver = RecordingProxyResolver(
            defaultResolution: .init(candidates: [.direct], evidenceCodes: []),
            recorder: recorder
        )

        let result = await SystemProxyCheck(
            resolver: resolver,
            connector: StubProxyConnector(reachable: false),
            egressLoader: StubProxyEgressLoader(statusCode: nil, errorCode: "unexpected"),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(result.status == .indeterminate)
        #expect(result.summary == String(
            localized: "network_diagnostics.proxy.direct_routes.summary",
            comment: "Network self-check direct target routes result summary"
        ))
        #expect(result.summary != String(
            localized: "network_diagnostics.proxy.disabled.summary",
            comment: "Network self-check system proxy disabled result summary"
        ))
        #expect(Set(await recorder.urls) == Set([
            "http://www.msftconnecttest.com/connecttest.txt",
            "https://www.apple.com/",
        ]))


        let httpURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let proxiedResolver = RecordingProxyResolver(resolutions: [
            httpURL: .init(
                candidates: [.http(.init(host: "proxy.example", port: 8080))],
                evidenceCodes: []
            ),
            httpsURL: .init(
                candidates: [.https(.init(host: "proxy.example", port: 8443))],
                evidenceCodes: []
            ),
        ])

        let proxiedResult = await SystemProxyCheck(
            resolver: proxiedResolver,
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(proxiedResult.status == .normal)
        #expect(proxiedResult.proxyFacts == .init(http: .available, https: .available))
        #expect(proxiedResult.summary == String(
            localized: "network_diagnostics.proxy.routes_available.summary",
            comment: "Network self-check proxy target routes available result summary"
        ))

        let authenticatedResolver = RecordingProxyResolver(resolutions: [
            httpURL: .init(
                candidates: [.http(.init(host: "proxy.example", port: 8080))],
                evidenceCodes: []
            ),
            httpsURL: .init(candidates: [.direct], evidenceCodes: []),
        ])

        let authenticatedResult = await SystemProxyCheck(
            resolver: authenticatedResolver,
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 407),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(authenticatedResult.status == .abnormal)
        #expect(authenticatedResult.summary == String(
            localized: "network_diagnostics.proxy.authentication_required.summary",
            comment: "Network self-check proxy authentication required result summary"
        ))
        #expect(authenticatedResult.evidence.contains(.init(
            code: "proxy.http.authentication-status",
            value: "required"
        )))
        #expect(authenticatedResult.evidence.contains(.init(code: "proxy.http.egress-status", value: "407")))

        let unavailableResolver = RecordingProxyResolver(defaultResolution: .init(
            candidates: [.http(.init(host: "stale.example", port: 8080))],
            evidenceCodes: []
        ))

        let unavailableResult = await SystemProxyCheck(
            resolver: unavailableResolver,
            connector: StubProxyConnector(reachable: false),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(unavailableResult.status == .abnormal)
        #expect(unavailableResult.summary == String(
            localized: "network_diagnostics.proxy.route_unavailable.summary",
            comment: "Network self-check proxy target route unavailable result summary"
        ))
        #expect(unavailableResult.evidence.contains(.init(
            code: "proxy.http.endpoint-status",
            value: "unavailable"
        )))
        #expect(unavailableResult.evidence.contains(.init(
            code: "proxy.https.endpoint-status",
            value: "unavailable"
        )))

        let emptyResolutionResult = await SystemProxyCheck(
            resolver: RecordingProxyResolver(defaultResolution: .init(
                candidates: [],
                evidenceCodes: ["resolution-empty"]
            )),
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(emptyResolutionResult.status == .indeterminate)
        #expect(emptyResolutionResult.summary == String(
            localized: "network_diagnostics.proxy.unable_to_determine.summary",
            comment: "Network self-check target proxy routing indeterminate result summary"
        ))
        #expect(emptyResolutionResult.evidence.contains(.init(
            code: "proxy.http.resolution",
            value: "resolution-empty"
        )))
        #expect(emptyResolutionResult.evidence.contains(.init(
            code: "proxy.https.resolution",
            value: "resolution-empty"
        )))

        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let pacTimeoutResult = await SystemProxyCheck(
            resolver: SystemProxyResolver(
                configurationResolver: StubProxyConfigurationResolver(.pac(pacURL)),
                pacResolver: StubPACResolver(.unavailable("pac-timeout"))
            ),
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(pacTimeoutResult.status == .indeterminate)
        #expect(pacTimeoutResult.summary == String(
            localized: "network_diagnostics.proxy.unable_to_determine.summary",
            comment: "Network self-check target proxy routing indeterminate result summary"
        ))
        #expect(pacTimeoutResult.evidence.contains(.init(code: "proxy.http.resolution", value: "pac-timeout")))
        #expect(pacTimeoutResult.evidence.contains(.init(code: "proxy.https.resolution", value: "pac-timeout")))
    }

    @Test("proxy failure outcomes preserve endpoint, authentication, timeout, and egress causes")
    func proxyFailureOutcomeMatrix() async {
        let egressRecorder = ProxyEgressTestRecorder()
        let proxy = EffectiveProxy.http(ProxyEndpoint(host: "proxy.example", port: 8080))
        let endpointCheck = SystemProxyCheck(
            resolver: StubProxyResolver(proxy),
            connector: StubProxyConnector(reachable: false),
            egressLoader: StubProxyEgressLoader(statusCode: 200, recorder: egressRecorder),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let endpointResult = await endpointCheck.run()

        #expect(endpointResult.status == .abnormal)
        #expect(endpointResult.summary == String(
            localized: "network_diagnostics.proxy.route_unavailable.summary",
            comment: "Network self-check proxy target route unavailable result summary"
        ))
        #expect(endpointResult.evidence.contains(.init(code: "proxy.endpoint-unavailable", value: nil)))
        #expect(await egressRecorder.requests.isEmpty)

        let authenticationCheck = SystemProxyCheck(
            resolver: StubProxyResolver(proxy),
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 407),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let authenticationResult = await authenticationCheck.run()

        #expect(authenticationResult.status == .abnormal)
        #expect(authenticationResult.summary == String(
            localized: "network_diagnostics.proxy.authentication_required.summary",
            comment: "Network self-check proxy authentication required result summary"
        ))
        #expect(authenticationResult.evidence.contains(.init(code: "proxy.authentication-required", value: "407")))
        #expect(!authenticationResult.evidence.contains(where: { $0.code == "proxy.endpoint-unavailable" }))

        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let endpoint = ProxyEndpoint(host: "proxy.example", port: 8080)
        let connectorRecorder = ProxyConnectorTestRecorder()
        let timeoutCheck = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: RecordingProxyConnector(reachable: true, recorder: connectorRecorder),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )
        let expiredRoute = await timeoutCheck.evaluate(
            target: target,
            resolution: .init(candidates: [.http(endpoint)], evidenceCodes: []),
            timeout: .zero
        )
        #expect(expiredRoute.status == .indeterminate)
        #expect(expiredRoute.selectedCandidateIndex == nil)
        #expect(expiredRoute.selectedProxy == nil)
        #expect(expiredRoute.evidence.contains(.init(code: "proxy.http.timeout", value: "expired")))
        #expect(await connectorRecorder.endpoints.isEmpty)
    }

    @Test("URL loading authentication challenge remains a proxy 407 result")
    func proxyAuthenticationChallenge() {
        let response = SystemProxyEgressLoader.response(
            for: URLError(.userAuthenticationRequired)
        )

        #expect(response == ProxyEgressResponse(statusCode: 407, errorCode: nil))
    }

    @Test("production tunneled egress configuration disables selected proxy failover")
    func selectedProxyDoesNotFailOver() throws {
        let proxy = EffectiveProxy.https(ProxyEndpoint(host: "proxy.example", port: 8080))
        let configuration = try #require(
            SystemProxyEgressLoader.configuration(for: proxy, timeout: .seconds(3))
        )

        #expect(configuration.proxyConfigurations.count == 1)
        #expect(configuration.proxyConfigurations[0].allowFailover == false)
        #expect(configuration.connectionProxyDictionary?.isEmpty != false)
        #expect(configuration.urlCredentialStorage == nil)
    }

    @Test("HTTP forward HTTPS tunnel and SOCKS candidates use distinct transport configurations")
    func selectedProxyTransportConfigurationsPreserveSemantics() throws {
        let endpoint = ProxyEndpoint(host: "proxy.example", port: 8080)
        let httpConfiguration = try #require(SystemProxyEgressLoader.configuration(
            for: .http(endpoint),
            timeout: .seconds(3)
        ))
        let httpsConfiguration = try #require(SystemProxyEgressLoader.configuration(
            for: .https(endpoint),
            timeout: .seconds(3)
        ))
        let socksConfiguration = try #require(SystemProxyEgressLoader.configuration(
            for: .socks(endpoint),
            timeout: .seconds(3)
        ))

        let httpDictionary = try #require(httpConfiguration.connectionProxyDictionary)
        #expect((httpDictionary[kCFNetworkProxiesHTTPEnable as String] as? NSNumber)?.boolValue == true)
        #expect(httpDictionary[kCFNetworkProxiesHTTPProxy as String] as? String == endpoint.host)
        #expect((httpDictionary[kCFNetworkProxiesHTTPPort as String] as? NSNumber)?.intValue == Int(endpoint.port))
        #expect((httpDictionary[kCFNetworkProxiesHTTPSEnable as String] as? NSNumber)?.boolValue == false)
        #expect((httpDictionary[kCFNetworkProxiesSOCKSEnable as String] as? NSNumber)?.boolValue == false)
        #expect((httpDictionary[kCFNetworkProxiesProxyAutoConfigEnable as String] as? NSNumber)?.boolValue == false)
        #expect((httpDictionary[kCFNetworkProxiesProxyAutoDiscoveryEnable as String] as? NSNumber)?.boolValue == false)
        #expect(httpConfiguration.proxyConfigurations.isEmpty)

        #expect(httpsConfiguration.connectionProxyDictionary?.isEmpty == true)
        #expect(httpsConfiguration.proxyConfigurations.count == 1)
        #expect(httpsConfiguration.proxyConfigurations[0].debugDescription.contains("http_connect"))
        #expect(httpsConfiguration.proxyConfigurations[0].allowFailover == false)

        #expect(socksConfiguration.connectionProxyDictionary?.isEmpty == true)
        #expect(socksConfiguration.proxyConfigurations.count == 1)
        #expect(socksConfiguration.proxyConfigurations[0].debugDescription.contains("socksv5"))
        #expect(socksConfiguration.proxyConfigurations[0].allowFailover == false)
    }

    @Test("later success after 407 selects that candidate and skips the trailing route")
    func proxySuccessAfterAuthenticationShortCircuitsTrailingCandidate() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let firstEndpoint = ProxyEndpoint(host: "auth.example", port: 8080)
        let selectedEndpoint = ProxyEndpoint(host: "working.example", port: 8081)
        let trailingEndpoint = ProxyEndpoint(host: "unused.example", port: 8082)
        let first = EffectiveProxy.http(firstEndpoint)
        let selected = EffectiveProxy.http(selectedEndpoint)
        let trailing = EffectiveProxy.http(trailingEndpoint)
        let connector = SequencedProxyConnector(outcomes: [true, true, true])
        let egress = SequencedProxyEgressLoader(
            responses: [
                .init(statusCode: 407, errorCode: nil),
                .init(statusCode: 204, errorCode: nil),
                .init(statusCode: 200, errorCode: nil),
            ],
            delays: [.zero, .zero, .zero]
        )
        let check = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: connector,
            egressLoader: egress,
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let route = await check.evaluate(
            target: target,
            resolution: .init(candidates: [first, selected, trailing], evidenceCodes: []),
            timeout: .seconds(3)
        )

        #expect(route.status == .proxied)
        #expect(route.selectedCandidateIndex == 1)
        #expect(route.selectedProxy == selected)
        #expect(await connector.endpoints == [firstEndpoint, selectedEndpoint])
        #expect(await egress.timeouts.count == 2)
    }

    @Test("proxy aggregation preserves authentication and egress failure severity")
    func proxyFailureAggregationMatrix() async {
        let httpURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let httpProxy = EffectiveProxy.http(.init(host: "auth.example", port: 8080))
        let httpsProxy = EffectiveProxy.https(.init(host: "stale.example", port: 8443))
        let connector = EndpointSelectiveProxyConnector(reachableHosts: ["auth.example"])
        let result = await SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [
                httpURL: .init(candidates: [httpProxy], evidenceCodes: []),
                httpsURL: .init(candidates: [httpsProxy], evidenceCodes: []),
            ]),
            connector: connector,
            egressLoader: StubProxyEgressLoader(statusCode: 407),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(result.status == .abnormal)
        #expect(result.summary == String(
            localized: "network_diagnostics.proxy.authentication_required.summary",
            comment: "Network self-check proxy authentication required result summary"
        ))
        #expect(result.evidence.contains(.init(code: "proxy.http.authentication-status", value: "required")))
        #expect(result.evidence.contains(.init(code: "proxy.https.endpoint-status", value: "unavailable")))

        let proxy = EffectiveProxy.http(ProxyEndpoint(host: "proxy.example", port: 8080))
        let egressResult = await SystemProxyCheck(
            resolver: StubProxyResolver(proxy),
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: nil, errorCode: "-1005"),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        ).run()

        #expect(egressResult.status == .abnormal)
        #expect(egressResult.summary == String(
            localized: "network_diagnostics.proxy.route_unavailable.summary",
            comment: "Network self-check proxy target route unavailable result summary"
        ))
        #expect(egressResult.evidence.contains(.init(code: "proxy.egress-unavailable", value: "-1005")))
    }

    @Test("selected HTTP proxy probes the same control URL once")
    func selectedProxyEgressSuccess() async {
        let controlURL = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let httpsURL = URL(string: "https://www.apple.com/")!
        let proxy = EffectiveProxy.http(ProxyEndpoint(host: "proxy.example", port: 8080))
        let recorder = ProxyEgressTestRecorder()
        let check = SystemProxyCheck(
            resolver: RecordingProxyResolver(resolutions: [
                controlURL: .init(candidates: [proxy], evidenceCodes: []),
                httpsURL: .init(candidates: [.direct], evidenceCodes: []),
            ]),
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200, recorder: recorder),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )

        let result = await check.run()

        #expect(result.status == .indeterminate)
        #expect(await recorder.requests == [.init(url: controlURL, proxy: proxy)])
    }

    @Test("cancelled concurrent proxy resolution remains bounded")
    func proxyCancellationStopsSecondTargetResolution() async {
        let resolver = CancellationIgnoringProxyResolver()
        let check = SystemProxyCheck(
            resolver: resolver,
            connector: StubProxyConnector(reachable: true),
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )
        let task = Task { await check.run() }

        await resolver.waitForInvocation()
        task.cancel()
        let result = await task.value

        #expect(await resolver.urls.count <= 2)
        #expect(result.status == .indeterminate)
        #expect(result.evidence.contains(.init(
            code: "proxy.cancelled",
            value: "after-http-resolution"
        )))
    }

    @Test("cancelled PAC resolution does not append later static candidates")
    func proxyResolverCancellationStopsRemainingDirectives() async {
        let pacURL = URL(string: "https://proxy.example/config.pac")!
        let pacResolver = CancellationIgnoringPACResolver()
        let resolver = SystemProxyResolver(
            configurationResolver: StubProxyConfigurationResolver([
                .pac(pacURL),
                .http(.init(host: "unused.example", port: 8080)),
            ]),
            pacResolver: pacResolver
        )
        let task = Task {
            await resolver.resolve(
                for: URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
            )
        }

        await pacResolver.waitForInvocation()
        task.cancel()
        let resolution = await task.value

        #expect(resolution.candidates.isEmpty)
        #expect(resolution.evidenceCodes.contains("pac-cancelled"))
        #expect(resolution.evidenceCodes.contains("resolution-cancelled"))
    }

    @Test("cancelling an endpoint attempt stops candidate fallback")
    func proxyCancellationStopsAfterConnector() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let first = ProxyEndpoint(host: "first.example", port: 8080)
        let second = ProxyEndpoint(host: "second.example", port: 8081)
        let connector = CancellationIgnoringProxyConnector()
        let check = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: connector,
            egressLoader: StubProxyEgressLoader(statusCode: 200),
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )
        let task = Task {
            await check.evaluate(
                target: target,
                resolution: .init(candidates: [.http(first), .http(second)], evidenceCodes: []),
                timeout: .seconds(30)
            )
        }

        await connector.waitForInvocation()
        task.cancel()
        let route = await task.value

        #expect(await connector.endpoints == [first])
        #expect(route.status == .indeterminate)
        #expect(route.evidence.contains(.init(
            code: "proxy.http.cancelled",
            value: "endpoint"
        )))
    }

    @Test("cancelling proxy egress stops connector and candidate fallback")
    func proxyCancellationStopsAfterEgress() async {
        let target = URL(string: "http://www.msftconnecttest.com/connecttest.txt")!
        let first = ProxyEndpoint(host: "first.example", port: 8080)
        let second = ProxyEndpoint(host: "second.example", port: 8081)
        let connector = SequencedProxyConnector(outcomes: [true, true])
        let egress = CancellationIgnoringProxyEgressLoader()
        let check = SystemProxyCheck(
            resolver: StubProxyResolver(.direct),
            connector: connector,
            egressLoader: egress,
            tunnelReader: StubProxyTunnelStateReader(interface: nil),
        )
        let task = Task {
            await check.evaluate(
                target: target,
                resolution: .init(candidates: [.http(first), .http(second)], evidenceCodes: []),
                timeout: .seconds(30)
            )
        }

        await egress.waitForInvocation()
        task.cancel()
        let route = await task.value

        #expect(await connector.endpoints == [first])
        #expect(await egress.invocationCount == 1)
        #expect(route.status == .indeterminate)
        #expect(route.evidence.contains(.init(
            code: "proxy.http.cancelled",
            value: "egress"
        )))
    }
}

