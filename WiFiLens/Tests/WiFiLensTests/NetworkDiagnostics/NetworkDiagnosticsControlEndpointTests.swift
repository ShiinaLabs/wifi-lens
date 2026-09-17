import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("IPv6 outcomes preserve optional-check conclusion semantics")
    func ipv6OutcomeMatrix() async {
        let route = DiagnosticIPv6RouteTarget(interfaceName: "utun6", interfaceIndex: 22)
        let ipv6 = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.noGlobalAddress)
        ).run()

        #expect(ipv6.id == .ipv6)
        #expect(ipv6.status == .skipped)
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(
                path: .normal,
                dns: .normal,
                internet: .normal,
                ipv6: ipv6.status,
                proxy: .normal
            )
        ) == .networkNormal)

        let failed = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.connectionFailed(route: route))
        ).run()

        #expect(failed.status == .indeterminate)
        #expect(failed.evidence.contains(.init(code: "ipv6.connection-failure", value: nil)))
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(
                path: .normal,
                dns: .normal,
                internet: .normal,
                ipv6: failed.status,
                proxy: .normal
            )
        ) == .networkNormal)

        let succeeded = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.succeeded(route: route))
        ).run()

        #expect(succeeded.status == .normal)
        #expect(succeeded.evidence.contains(.init(code: "ipv6.available", value: nil)))
        #expect(succeeded.evidence.contains(.init(code: "ipv6.route-interface", value: "utun6")))
    }

    @Test("IPv6 outcomes preserve the distinction between DNS and connection failures")
    func ipv6OutcomeReasonsRemainDistinct() async {
        let route = DiagnosticIPv6RouteTarget(interfaceName: "utun6", interfaceIndex: 22)

        let noRoute = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.noDefaultRoute)
        ).run()
        #expect(noRoute.status == .indeterminate)
        #expect(noRoute.evidence.contains(.init(code: "ipv6.no-default-route", value: nil)))

        let noAAAA = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.noAAAA(route: route))
        ).run()
        #expect(noAAAA.status == .indeterminate)
        #expect(noAAAA.evidence.contains(.init(code: "ipv6.no-aaaa", value: nil)))

        let dnsFailure = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.dnsFailure(route: route))
        ).run()
        #expect(dnsFailure.status == .indeterminate)
        #expect(dnsFailure.evidence.contains(.init(code: "ipv6.dns-failure", value: nil)))

        let timeout = await IPv6ControlEndpointCheck(
            loader: StubIPv6Loader(.timedOut(route: route))
        ).run()
        #expect(timeout.status == .indeterminate)
        #expect(timeout.evidence.contains(.init(code: "ipv6.timeout", value: nil)))
    }

    @Test("IPv6 loader preserves literal, fallback, and precondition behavior")
    func ipv6LoaderMatrix() async {
        let recorder = IPv6LoaderTestRecorder()
        let loader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: true),
            resolver: StubIPv6AddressResolver(addresses: ["2001:db8::42"]),
            connector: RecordingIPv6HTTPSConnector(succeeds: true, recorder: recorder),
            routeSource: StubIPv6RouteSource(.init(interfaceName: "utun6", interfaceIndex: 22))
        )
        let endpoint = URL(string: "https://control.example/health")!

        let outcome = await loader.load(url: endpoint, timeout: .seconds(4))

        #expect(outcome == .succeeded(route: .init(interfaceName: "utun6", interfaceIndex: 22)))
        let requests = await recorder.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url == endpoint)
        #expect(requests.first?.ipv6Address == "2001:db8::42")
        #expect(requests.first?.serverName == "control.example")
        #expect(requests.first.map { $0.timeout > .zero && $0.timeout <= .seconds(4) } == true)

        let connector = SequencedIPv6HTTPSConnector(successfulAddress: "2001:db8::2")
        let fallbackLoader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: true),
            resolver: StubIPv6AddressResolver(addresses: ["2001:db8::1", "2001:db8::2"]),
            connector: connector,
            routeSource: StubIPv6RouteSource(.init(interfaceName: "en0", interfaceIndex: 11))
        )

        let fallbackOutcome = await fallbackLoader.load(
            url: URL(string: "https://control.example/health")!,
            timeout: .seconds(4)
        )

        #expect(fallbackOutcome == .succeeded(route: .init(interfaceName: "en0", interfaceIndex: 11)))
        #expect(await connector.addresses == ["2001:db8::1", "2001:db8::2"])
        let timeouts = await connector.timeouts
        #expect(timeouts.count == 2)
        #expect(timeouts.first.map { $0 > .zero && $0 <= .seconds(2) } == true)
        #expect(timeouts.last.map { $0 > .zero && $0 <= .seconds(4) } == true)

        let noAAAALoader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: true),
            resolver: StubIPv6AddressResolver(addresses: []),
            connector: StubIPv6HTTPSConnector(succeeds: true),
            routeSource: StubIPv6RouteSource(.init(interfaceName: "utun6", interfaceIndex: 22))
        )
        #expect(
            await noAAAALoader.load(
                url: URL(string: "https://control.example/health")!,
                timeout: .seconds(4)
            ) == .noAAAA(route: .init(interfaceName: "utun6", interfaceIndex: 22))
        )

        let dnsFailureLoader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: true),
            resolver: StubIPv6AddressResolver(outcome: .failed),
            connector: StubIPv6HTTPSConnector(succeeds: true),
            routeSource: StubIPv6RouteSource(.init(interfaceName: "utun6", interfaceIndex: 22))
        )
        #expect(
            await dnsFailureLoader.load(
                url: URL(string: "https://control.example/health")!,
                timeout: .seconds(4)
            ) == .dnsFailure(route: .init(interfaceName: "utun6", interfaceIndex: 22))
        )

        let connectionFailureLoader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: true),
            resolver: StubIPv6AddressResolver(addresses: ["2001:db8::42"]),
            connector: StubIPv6HTTPSConnector(succeeds: false),
            routeSource: StubIPv6RouteSource(.init(interfaceName: "utun6", interfaceIndex: 22))
        )
        #expect(
            await connectionFailureLoader.load(
                url: URL(string: "https://control.example/health")!,
                timeout: .seconds(4)
            ) == .connectionFailed(route: .init(interfaceName: "utun6", interfaceIndex: 22))
        )

        let resolver = RecordingIPv6AddressResolver(addresses: ["2001:db8::42"])
        let noAddressLoader = SystemIPv6ControlEndpointLoader(
            addressSource: StubGlobalIPv6AddressSource(hasAddress: false),
            resolver: resolver,
            connector: StubIPv6HTTPSConnector(succeeds: true),
            routeSource: StubIPv6RouteSource(.init(interfaceName: "utun6", interfaceIndex: 22))
        )

        let noAddressOutcome = await noAddressLoader.load(
            url: URL(string: "https://control.example/")!,
            timeout: .seconds(4)
        )

        #expect(noAddressOutcome == .noGlobalAddress)
        #expect(await resolver.hosts.isEmpty)
    }

    @Test("control endpoint outcomes preserve HTTPS and captive-portal evidence")
    func controlEndpointOutcomeMatrix() async {
        let check = HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 204,
                httpStatus: 200,
                httpBody: "login"
            )
        )

        let result = await check.run()

        #expect(result.id == .internet)
        #expect(result.evidence.contains(.init(code: "captive-portal.suspected", value: nil)))

        let success = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 200,
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()

        #expect(success.status == .normal)
        #expect(success.evidence.contains(.init(code: "https.available", value: "200")))
        #expect(success.evidence.contains(.init(code: "captive-portal.clear", value: nil)))

        let timeout = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 200,
                httpStatus: nil,
                httpBody: nil,
                httpErrorCode: String(URLError.timedOut.rawValue)
            )
        ).run()

        #expect(timeout.status == .indeterminate)
        #expect(timeout.evidence.contains(.init(code: "https.available", value: "200")))
        #expect(timeout.evidence.contains(.init(
            code: "captive-portal.transport-error",
            value: String(URLError.timedOut.rawValue)
        )))
    }

    @Test("independent control endpoints load concurrently and preserve evidence order")
    func controlEndpointsRunConcurrently() async {
        let loader = ConcurrentControlLoader()
        let result = await HTTPSControlEndpointCheck(loader: loader).run()

        #expect(await loader.maximumInFlight == 2)
        #expect(result.evidence.map(\.code).prefix(2) == ["https.available", "captive-portal.clear"])
    }

    @Test("control endpoint metrics are redacted to bounded transaction fields")
    func controlEndpointMetricsAreRedacted() async {
        let result = await HTTPSControlEndpointCheck(
            loader: MetricsControlLoader(
                metrics: .init(
                    dnsDuration: .milliseconds(12),
                    connectDuration: .milliseconds(34),
                    tlsDuration: .milliseconds(56),
                    negotiatedTLSVersion: "TLSv1.3",
                    isProxyConnection: true,
                    remoteAddress: "192.0.2.10:443"
                )
            )
        ).run()

        #expect(result.evidence.contains(.init(code: "https.metrics.dns-ms", value: "12")))
        #expect(result.evidence.contains(.init(code: "https.metrics.connect-ms", value: "34")))
        #expect(result.evidence.contains(.init(code: "https.metrics.tls-ms", value: "56")))
        #expect(result.evidence.contains(.init(code: "https.metrics.tls-version", value: "TLSv1.3")))
        #expect(result.evidence.contains(.init(code: "https.metrics.proxy", value: "true")))
        #expect(!result.evidence.contains { $0.value == "192.0.2.10:443" })
    }

    @Test("control endpoint failures retain distinct evidence")
    func controlEndpointFailureEvidence() async {
        let tlsFailure = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: nil,
                httpsErrorCode: String(URLError.secureConnectionFailed.rawValue),
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()
        let certificateTimeFailure = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: nil,
                httpsErrorCode: String(URLError.serverCertificateNotYetValid.rawValue),
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()
        let certificateValidationFailure = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: nil,
                httpsErrorCode: String(URLError.serverCertificateUntrusted.rawValue),
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()
        let connectivityFailure = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: nil,
                httpsErrorCode: String(URLError.timedOut.rawValue),
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()
        let httpsStatusFailure = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 503,
                httpStatus: 200,
                httpBody: "Success"
            )
        ).run()
        let captivePortalRedirect = await HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 200,
                httpStatus: 302,
                httpBody: nil
            )
        ).run()

        #expect(tlsFailure.evidence.contains(.init(
            code: "https.tls-error",
            value: String(URLError.secureConnectionFailed.rawValue)
        )))
        #expect(certificateTimeFailure.evidence.contains(.init(
            code: "https.certificate-time-error",
            value: String(URLError.serverCertificateNotYetValid.rawValue)
        )))
        #expect(certificateValidationFailure.evidence.contains(.init(
            code: "https.certificate-error",
            value: String(URLError.serverCertificateUntrusted.rawValue)
        )))
        #expect(connectivityFailure.evidence.contains(.init(
            code: "https.connectivity-error",
            value: String(URLError.timedOut.rawValue)
        )))
        #expect(httpsStatusFailure.evidence.contains(.init(code: "https.http-status", value: "503")))
        #expect(captivePortalRedirect.evidence.contains(.init(code: "captive-portal.redirect", value: "302")))
        #expect(tlsFailure.summary == String(
            localized: "network_diagnostics.internet.secure_connection_failure.summary",
            comment: "Network self-check TLS or certificate failure summary"
        ))
        #expect(certificateValidationFailure.summary == tlsFailure.summary)
        #expect(certificateTimeFailure.summary == String(
            localized: "network_diagnostics.internet.certificate_time_failure.summary",
            comment: "Network self-check certificate time failure summary"
        ))
        #expect(connectivityFailure.summary == String(
            localized: "network_diagnostics.internet.connectivity_failure.summary",
            comment: "Network self-check connectivity failure summary"
        ))

        let baseResults = [
            NetworkDiagnosticResult(id: .path, status: .normal, summary: "path"),
            NetworkDiagnosticResult(id: .gatewayReachability, status: .normal, summary: "gateway"),
            NetworkDiagnosticResult(id: .dns, status: .normal, summary: "dns"),
        ]
        let trailingResults = [
            NetworkDiagnosticResult(id: .ipv6, status: .skipped, summary: "ipv6"),
            NetworkDiagnosticResult(id: .proxy, status: .abnormal, summary: "proxy"),
        ]
        #expect(NetworkDiagnosticConclusion.evaluate(
            baseResults + [tlsFailure] + trailingResults
        ) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            baseResults + [certificateTimeFailure] + trailingResults
        ) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            baseResults + [certificateValidationFailure] + trailingResults
        ) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            baseResults + [connectivityFailure] + trailingResults
        ) == .needsAttention)
    }

    @Test("control check loads the approved endpoints with an explicit timeout")
    func controlEndpointRequests() async {
        let recorder = ControlEndpointTestRecorder()
        let check = HTTPSControlEndpointCheck(
            loader: StubControlLoader(
                httpsStatus: 200,
                httpStatus: 200,
                httpBody: "Success",
                recorder: recorder
            )
        )

        _ = await check.run()

        #expect(Set(await recorder.urls) == Set([
            "https://www.apple.com/",
            "https://captive.apple.com/hotspot-detect.html",
        ]))
        #expect(await recorder.timeouts == [.seconds(5), .seconds(5)])
    }

    @Test("system control loader disables caching and connectivity waits")
    func controlEndpointSessionConfiguration() {
        let configuration = SystemControlEndpointLoader.configuration(timeout: .seconds(5))

        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.urlCache == nil)
        #expect(!configuration.waitsForConnectivity)
        #expect(configuration.timeoutIntervalForRequest == 5)
        #expect(configuration.timeoutIntervalForResource == 5)
    }

    @Test("base endpoint configuration does not inherit explicit system proxies")
    func baseEndpointDisablesExplicitSystemProxy() {
        let configuration = SystemControlEndpointLoader.configuration(timeout: .seconds(2))

        #expect(configuration.connectionProxyDictionary?.isEmpty == true)
        #expect(configuration.proxyConfigurations.isEmpty)
    }

    @Test("app scopes the ATS HTTP exception to the Microsoft captive-portal/proxy endpoint")
    func temporaryCaptivePortalATSException() {
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        let domains = ats?["NSExceptionDomains"] as? [String: Any]
        let exception = domains?["www.msftconnecttest.com"] as? [String: Any]

        #expect(ats?.count == 1)
        #expect(ats?["NSAllowsArbitraryLoads"] == nil)
        #expect(domains?.count == 1)
        #expect(exception?.count == 1)
        #expect(exception?["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true)
        #expect(exception?["NSIncludesSubdomains"] == nil)
    }
}
