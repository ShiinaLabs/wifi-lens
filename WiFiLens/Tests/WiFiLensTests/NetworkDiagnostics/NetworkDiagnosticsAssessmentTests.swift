import CFNetwork
import Foundation
import Network
import Testing

@testable import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("conclusion and assessment rules cover the decision table")
    func conclusionDecisionTable() {
        func assessment(for results: [NetworkDiagnosticResult]) -> NetworkDiagnosticAssessment {
            NetworkDiagnosticAssessmentResolver().resolve(
                results: Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) }),
                complete: true
            )
        }

        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .abnormal, dns: .normal, internet: .normal, proxy: .normal)
            ) == .networkUnavailable)
        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .normal, dns: .abnormal, internet: .normal, proxy: .normal)
            ) == .needsAttention)
        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .abnormal)
            ) == .needsAttention)

        let gatewayFailure = makeResults(
            path: .normal,
            gateway: .abnormal,
            gatewayTCP: .abnormal,
            dns: .normal,
            internet: .normal,
            proxy: .normal
        )
        #expect(NetworkDiagnosticConclusion.evaluate(gatewayFailure) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.primaryIssue(in: gatewayFailure)?.id == .gatewayReachability)

        var usableProxy = makeResults(
            path: .normal,
            dns: .normal,
            internet: .abnormal,
            proxy: .normal
        )
        usableProxy[5] = NetworkDiagnosticResult(
            id: .proxy,
            status: .normal,
            summary: "proxy",
            evidence: [.init(code: "proxy.https.egress-status", value: "200")]
        )
        #expect(NetworkDiagnosticConclusion.evaluate(usableProxy) == .needsAttention)

        var directWithoutEgress = makeResults(
            path: .normal,
            dns: .normal,
            internet: .abnormal,
            proxy: .normal
        )
        directWithoutEgress[3] = NetworkDiagnosticResult(
            id: .internet,
            status: .abnormal,
            summary: "internet",
            evidence: [
                .init(
                    code: "https.connectivity-error",
                    value: String(URLError.notConnectedToInternet.rawValue)
                )
            ]
        )
        directWithoutEgress[5] = NetworkDiagnosticResult(
            id: .proxy,
            status: .normal,
            summary: "proxy",
            evidence: [.init(code: "proxy.https.egress-status", value: "base-check")]
        )
        #expect(NetworkDiagnosticConclusion.evaluate(directWithoutEgress) == .needsAttention)
        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .abnormal)
            ) == .needsAttention)

        let captivePortal = [
            NetworkDiagnosticResult(id: .path, status: .normal, summary: "path"),
            NetworkDiagnosticResult(id: .gatewayReachability, status: .normal, summary: "gateway"),
            NetworkDiagnosticResult(id: .gatewayTCPReachability, status: .normal, summary: "gateway TCP"),
            NetworkDiagnosticResult(id: .dns, status: .normal, summary: "dns"),
            NetworkDiagnosticResult(
                id: .internet,
                status: .abnormal,
                summary: "internet",
                evidence: [
                    .init(code: "https.available", value: "200"),
                    .init(code: "captive-portal.suspected", value: nil),
                ]
            ),
            NetworkDiagnosticResult(id: .ipv6, status: .skipped, summary: "ipv6"),
            NetworkDiagnosticResult(id: .proxy, status: .normal, summary: "proxy"),
        ]
        #expect(NetworkDiagnosticConclusion.evaluate(captivePortal) == .needsAttention)
        #expect(assessment(for: captivePortal).primaryIssue?.id == .internet)

        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .normal, dns: .indeterminate, internet: .normal, proxy: .normal)
            ) == .needsAttention)
        #expect(
            NetworkDiagnosticConclusion.evaluate(
                makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .normal)
            ) == .networkNormal)
        #expect(
            NetworkDiagnosticConclusion.evaluate([
                NetworkDiagnosticResult(id: .path, status: .normal, summary: "ok")
            ]) == nil)

        var directRoute = makeResults(
            path: .normal,
            dns: .normal,
            internet: .normal,
            proxy: .indeterminate
        )
        directRoute[5] = NetworkDiagnosticResult(
            id: .proxy,
            status: .indeterminate,
            summary: "direct routing selected",
            evidence: [.init(code: "proxy.https.egress-status", value: "base-check")],
            proxyFacts: .init(http: .unverified, https: .unverified)
        )
        #expect(NetworkDiagnosticConclusion.evaluate(directRoute) == .networkNormal)

        let pacFailure = makeResults(
            path: .normal,
            dns: .normal,
            internet: .normal,
            proxy: .indeterminate
        ).map { result in
            guard result.id == .proxy else { return result }
            return NetworkDiagnosticResult(
                id: .proxy,
                status: .indeterminate,
                summary: "proxy resolution failed",
                evidence: [
                    .init(code: "proxy.http.resolution", value: "pac-timeout"),
                    .init(code: "proxy.https.resolution", value: "pac-timeout"),
                ],
                proxyFacts: .init(http: .unverified, https: .unverified)
            )
        }
        #expect(assessment(for: pacFailure).conclusion == .needsAttention)

        var singleHTTPSFailure = makeResults(
            path: .normal,
            dns: .normal,
            internet: .abnormal,
            proxy: .indeterminate
        )
        singleHTTPSFailure[3] = NetworkDiagnosticResult(
            id: .internet,
            status: .abnormal,
            summary: "one HTTPS target failed",
            evidence: [.init(code: "https.connectivity-error", value: nil)]
        )
        #expect(NetworkDiagnosticConclusion.evaluate(singleHTTPSFailure) == .needsAttention)

        var uncertainDNS = makeResults(
            path: .normal,
            dns: .indeterminate,
            internet: .normal,
            proxy: .indeterminate
        )
        uncertainDNS[5] = NetworkDiagnosticResult(
            id: .proxy,
            status: .indeterminate,
            summary: "direct routing selected",
            proxyFacts: .init(http: .unverified, https: .unverified)
        )
        let uncertainDNSAssessment = assessment(for: uncertainDNS)
        #expect(uncertainDNSAssessment.conclusion == .needsAttention)
        #expect(uncertainDNSAssessment.stages.first { $0.stage == .thisMac }?.status == .indeterminate)

        let facts = DiagnosticProxyFacts(http: .unavailable, https: .available)
        #expect(facts.https == .available)
        let independentHTTPS = makeResults(
            path: .normal,
            dns: .normal,
            internet: .abnormal,
            proxy: .abnormal
        ).map { result in
            if result.id == .internet {
                return NetworkDiagnosticResult(
                    id: result.id,
                    status: result.status,
                    summary: result.summary,
                    evidence: [.init(code: "https.connectivity-error", value: nil)]
                )
            }
            if result.id == .proxy {
                return NetworkDiagnosticResult(
                    id: result.id,
                    status: result.status,
                    summary: result.summary,
                    evidence: [.init(code: "proxy.endpoint-unavailable", value: nil)],
                    proxyFacts: facts
                )
            }
            return result
        }
        let independentHTTPSAssessment = assessment(for: independentHTTPS)
        #expect(independentHTTPSAssessment.conclusion == .needsAttention)
        #expect(independentHTTPSAssessment.primaryIssue?.id == .proxy)

        let recoveredProxy = makeResults(
            path: .normal,
            dns: .normal,
            internet: .normal,
            proxy: .normal
        ).map { result in
            guard result.id == .proxy else { return result }
            return NetworkDiagnosticResult(
                id: .proxy,
                status: .normal,
                summary: "HTTPS proxy recovered",
                evidence: [.init(code: "proxy.https.authentication-required", value: "407")],
                proxyFacts: .init(http: .available, https: .available)
            )
        }
        let recoveredAssessment = assessment(for: recoveredProxy)
        #expect(recoveredAssessment.conclusion == .networkNormal)
        #expect(recoveredAssessment.primaryIssue == nil)
    }
}

extension NetworkDiagnosticsTests {
    @Test("IPv4 boundary keeps consecutive private hops and distinguishes shared addresses")
    func ipv4BoundaryDiscovery() {
        let gateway = "192.168.31.1"
        #expect(IPv4NetworkBoundary(hops: [gateway, "8.8.8.8"], gateway: gateway)?.localHops == [gateway])
        let local = [gateway, "192.168.1.1", "172.31.0.1", "10.0.0.1"]
        let boundary = IPv4NetworkBoundary(hops: local.map(Optional.some) + ["100.66.0.1"], gateway: gateway)
        #expect(boundary?.localHops == local)
        #expect(boundary?.externalHop == "100.66.0.1")
        #expect(IPv4NetworkBoundary(hops: [gateway, nil, "8.8.8.8"], gateway: gateway) == nil)
        #expect(IPv4NetworkBoundary(hops: ["10.0.0.1", "8.8.8.8"], gateway: gateway) == nil)
        #expect(IPv4NetworkBoundary.AddressScope("100.64.0.0") == .carrier)
        #expect(IPv4NetworkBoundary.AddressScope("100.127.255.255") == .carrier)
        #expect(IPv4NetworkBoundary.AddressScope("100.128.0.0") == .external)
        #expect(IPv4NetworkBoundary.AddressScope("100.63.255.255") == .external)
        #expect(IPv4NetworkBoundary.AddressScope("198.18.0.1") == .other)
    }

    @Test("Known dual-router boundary distinguishes local, outlet and carrier failures")
    func ipv4BoundaryReuse() {
        let gateway = "192.168.31.1"
        let upstream = "192.168.1.1"
        let carrier = "100.66.0.1"
        func observation(_ hops: [String?], bssid: String? = "first") -> IPv4BoundaryObservation {
            IPv4BoundaryObservation(
                network: .init(
                    route: .init(interfaceName: "en0", interfaceIndex: 1, address: gateway),
                    addresses: ["192.168.31.2"], masks: ["255.255.255.0"], wirelessIdentity: bssid, isWiFi: true
                ),
                hops: hops
            )
        }
        var cache = IPv4BoundaryCache()
        #expect(cache.assess(observation([gateway, nil]), internetAvailable: false) == nil)
        let now = ContinuousClock.now
        #expect(cache.assess(observation([gateway, upstream, carrier, "8.8.8.8"]), internetAvailable: true, now: now) == nil)
        let localFailure = observation([gateway, nil])
        let upstreamMiss = IPv4GatewayProbe(level: 2, address: upstream, outcome: .noReply)
        let carrierReply = IPv4GatewayProbe(level: 3, address: carrier, outcome: .replied(milliseconds: 3))
        let executionFailure = IPv4GatewayProbe(level: 2, address: upstream, outcome: .executionFailed)
        #expect(cache.boundary(for: localFailure.network)?.localHops == [gateway, upstream])
        #expect(cache.assess(localFailure, internetAvailable: false) == nil)
        #expect(localFailure.firstUnresponsiveGateway(in: [upstreamMiss]) == upstreamMiss)
        #expect(localFailure.firstUnresponsiveGateway(in: [upstreamMiss, carrierReply]) == nil)
        #expect(localFailure.firstUnresponsiveGateway(in: [executionFailure]) == nil)
        #expect(observation([gateway, nil, carrier]).firstUnresponsiveGateway(in: [upstreamMiss]) == nil)
        #expect(cache.assess(observation([gateway, upstream, nil]), internetAvailable: false) == .outlet)
        #expect(cache.assess(observation([gateway, upstream, carrier, nil]), internetAvailable: false) == .carrier)
        #expect(cache.assess(observation([gateway, nil, carrier]), internetAvailable: false) == nil)
        #expect(cache.assess(observation([nil, nil]), internetAvailable: false) == nil)
        #expect(cache.assess(observation([gateway, upstream, nil]), internetAvailable: false, now: now + .seconds(3600)) == nil)
        _ = cache.assess(observation([gateway, upstream, carrier]), internetAvailable: true)
        #expect(cache.assess(observation([gateway, nil], bssid: "second"), internetAvailable: false) == nil)
        let unidentified = observation([gateway, upstream, carrier], bssid: nil)
        #expect(unidentified.boundary?.localHops.last == upstream)
        _ = cache.assess(unidentified, internetAvailable: true)
        #expect(cache.assess(observation([gateway, nil], bssid: nil), internetAvailable: false) == nil)
    }

    @Test("Boundary advice refines an internet failure and leaves working internet and failed runs alone")
    func ipv4BoundaryAssessment() {
        let results = makeResults(path: .normal, dns: .normal, internet: .abnormal, proxy: .normal)
        var byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        byID[.internet] = .init(
            id: .internet, status: .abnormal, summary: "internet",
            evidence: [.init(code: "https.connectivity-error", value: String(URLError.timedOut.rawValue))]
        )
        let resolver = NetworkDiagnosticAssessmentResolver()
        for failure in [IPv4BoundaryFailure.localRoute, .outlet, .carrier] {
            let issue = resolver.resolve(results: byID, complete: true, boundaryFailure: failure).primaryIssue
            #expect(issue?.evidence.contains(.init(code: failure.rawValue)) == true)
        }
        #expect(resolver.resolve(results: byID, complete: false, boundaryFailure: .outlet).conclusion == nil)
        byID[.internet] = .init(id: .internet, status: .normal, summary: "internet", evidence: [.init(code: "https.available")])
        #expect(resolver.resolve(results: byID, complete: true, boundaryFailure: .outlet).conclusion == .networkNormal)
    }
}
