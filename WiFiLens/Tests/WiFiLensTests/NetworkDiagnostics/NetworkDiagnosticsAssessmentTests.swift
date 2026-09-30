import CFNetwork
import Foundation
import Network
import Testing
import WiFiLensCore
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

        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .abnormal, dns: .normal, internet: .normal, proxy: .normal)
        ) == .networkUnavailable)
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .normal, dns: .abnormal, internet: .normal, proxy: .normal)
        ) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .abnormal)
        ) == .needsAttention)

        let gatewayFailure = makeResults(
            path: .normal,
            gateway: .abnormal,
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
            evidence: [.init(
                code: "https.connectivity-error",
                value: String(URLError.notConnectedToInternet.rawValue)
            )]
        )
        directWithoutEgress[5] = NetworkDiagnosticResult(
            id: .proxy,
            status: .normal,
            summary: "proxy",
            evidence: [.init(code: "proxy.https.egress-status", value: "base-check")]
        )
        #expect(NetworkDiagnosticConclusion.evaluate(directWithoutEgress) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .abnormal)
        ) == .needsAttention)

        let captivePortal = [
            NetworkDiagnosticResult(id: .path, status: .normal, summary: "path"),
            NetworkDiagnosticResult(id: .gatewayReachability, status: .normal, summary: "gateway"),
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

        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .normal, dns: .indeterminate, internet: .normal, proxy: .normal)
        ) == .needsAttention)
        #expect(NetworkDiagnosticConclusion.evaluate(
            makeResults(path: .normal, dns: .normal, internet: .normal, proxy: .normal)
        ) == .networkNormal)
        #expect(NetworkDiagnosticConclusion.evaluate([
            NetworkDiagnosticResult(id: .path, status: .normal, summary: "ok"),
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

