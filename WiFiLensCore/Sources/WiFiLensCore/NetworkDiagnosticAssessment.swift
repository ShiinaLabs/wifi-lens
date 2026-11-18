import Foundation

enum DiagnosticRouteAvailability: Equatable, Sendable {
    case available
    case unavailable
    case authenticationRequired
    case unverified
}

struct DiagnosticProxyFacts: Equatable, Sendable {
    let http: DiagnosticRouteAvailability
    let https: DiagnosticRouteAvailability

    public init(http: DiagnosticRouteAvailability, https: DiagnosticRouteAvailability) {
        self.http = http
        self.https = https
    }
}

enum DiagnosticActionPriority: Int, Comparable, Sendable {
    case captivePortal = 0
    case pathUnavailable = 1
    case proxyAuthentication = 2
    case certificateTime = 3
    case proxyRoute = 4
    case dns = 5
    case targetTransport = 6
    case indeterminate = 7

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct DiagnosticStageAssessment: Equatable, Sendable {
    public let stage: NetworkDiagnosticStage
    public let status: NetworkDiagnosticStatus?
    let qualificationCode: String?

    public init(stage: NetworkDiagnosticStage, status: NetworkDiagnosticStatus?, qualificationCode: String?) {
        self.stage = stage
        self.status = status
        self.qualificationCode = qualificationCode
    }
}

struct NetworkDiagnosticAssessment: Equatable, Sendable {
    public let conclusion: NetworkDiagnosticConclusion?
    let stages: [DiagnosticStageAssessment]
    let primaryIssue: NetworkDiagnosticResult?
}

struct NetworkDiagnosticAssessmentResolver: Sendable {
    func resolve(
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        complete: Bool,
        requiredIDs: Set<NetworkDiagnosticCheckID> = Set(NetworkDiagnosticCheckID.allCases),
        boundaryFailure: IPv4BoundaryFailure? = nil,
        unresponsiveGateway: IPv4GatewayProbe? = nil
    ) -> NetworkDiagnosticAssessment {
        let stages = NetworkDiagnosticStage.allCases.map { stage in
            stageAssessment(stage, results: results)
        }
        guard complete,
            Set(results.keys) == requiredIDs
        else {
            return NetworkDiagnosticAssessment(
                conclusion: nil,
                stages: stages,
                primaryIssue: primaryIssue(in: results)
            )
        }

        let conclusion = conclusion(results: results)
        var issue = primaryIssue(in: results)
        if let boundaryFailure,
            issue?.id == .internet
                || (issue?.id == .dns && boundaryFailure != .carrier),
            results[.path]?.status == .normal,
            results[.gatewayReachability]?.status == .normal
                || results[.gatewayTCPReachability]?.status == .normal,
            let internet = results[.internet], internet.status == .abnormal,
            !hasExternalSuccess(internet: internet, proxy: results[.proxy]),
            !internet.evidence.contains(where: { $0.code == "captive-portal.clear" }),
            internet.evidence.contains(where: {
                $0.code == "https.connectivity-error"
                    && (boundaryFailure != .carrier || $0.value != String(URLError.dnsLookupFailed.rawValue))
            })
        {
            issue = NetworkDiagnosticResult(
                id: internet.id,
                status: internet.status,
                summary: internet.summary,
                detail: internet.detail,
                evidence: internet.evidence + [.init(code: boundaryFailure.rawValue, value: unresponsiveGateway?.address)]
            )
        }
        return NetworkDiagnosticAssessment(
            conclusion: conclusion,
            stages: stages,
            primaryIssue: issue
        )
    }

    private func stageAssessment(
        _ stage: NetworkDiagnosticStage,
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult]
    ) -> DiagnosticStageAssessment {
        let contributors = stage.contributingCheckIDs.compactMap { results[$0] }
        guard contributors.count == stage.contributingCheckIDs.count else {
            return .init(stage: stage, status: nil, qualificationCode: nil)
        }
        if contributors.allSatisfy({ $0.status == .skipped }) {
            return .init(stage: stage, status: .skipped, qualificationCode: nil)
        }
        if contributors.contains(where: { $0.status == .abnormal }) {
            return .init(stage: stage, status: .abnormal, qualificationCode: nil)
        }
        if contributors.contains(where: { $0.status == .blocked }) {
            return .init(stage: stage, status: .blocked, qualificationCode: nil)
        }
        if stage == .lan, contributors.contains(where: { $0.status == .normal }) {
            return .init(stage: stage, status: .normal, qualificationCode: nil)
        }
        if contributors.contains(where: { $0.status == .indeterminate }) {
            let nonProxyContributors = contributors.filter { $0.id != .proxy }
            if stage == .thisMac,
                let proxy = results[.proxy],
                isUnverifiedDirectRoute(proxy: proxy, internet: results[.internet]),
                nonProxyContributors.allSatisfy({ $0.status == .normal })
            {
                return .init(
                    stage: stage,
                    status: .normal,
                    qualificationCode: "proxy.direct-unverified"
                )
            }
            if stage == .lan,
                let gateway = results[.gatewayReachability],
                gateway.status == .indeterminate,
                gateway.evidence.contains(where: { $0.code == "gateway.no-response" }),
                hasExternalSuccess(
                    internet: results[.internet],
                    proxy: results[.proxy]
                )
            {
                return .init(
                    stage: stage,
                    status: .indeterminate,
                    qualificationCode: "gateway.unverified"
                )
            }
            return .init(stage: stage, status: .indeterminate, qualificationCode: nil)
        }
        return .init(stage: stage, status: .normal, qualificationCode: nil)
    }

    private func conclusion(
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult]
    ) -> NetworkDiagnosticConclusion {
        let path = results[.path]
        let internet = results[.internet]
        let gateway = results[.gatewayReachability]
        let dns = results[.dns]
        let proxy = results[.proxy]
        let externalSuccess = hasExternalSuccess(internet: internet, proxy: proxy)
        if internet?.evidence.contains(where: {
            $0.code == "captive-portal.redirect" || $0.code == "captive-portal.suspected"
        }) == true {
            return .needsAttention
        }

        if path?.status == .abnormal, !externalSuccess {
            return .networkUnavailable
        }
        if internet?.status == .abnormal,
            !hasDirectHTTPS(internet),
            !hasAvailableHTTPSProxy(proxy),
            internet?.evidence.contains(where: { $0.code == "https.connectivity-error" }) == true
        {
            return .needsAttention
        }

        let hasActionableIssue = [path, gateway, dns, internet, proxy]
            .compactMap { $0 }
            .contains { result in
                switch result.id {
                case .path:
                    result.status != .normal
                case .gatewayReachability:
                    results[.gatewayTCPReachability]?.status != .normal
                        && !isNeutralGateway(result, externalSuccess: externalSuccess)
                        && result.status != .normal
                        && result.status != .skipped
                case .gatewayTCPReachability:
                    false
                case .dns, .internet:
                    result.status != .normal
                case .proxy:
                    !isNeutralDirectProxy(result, internet: internet)
                        && result.status != .normal
                case .ipv6:
                    false
                }
            }
        return hasActionableIssue ? .needsAttention : .networkNormal
    }

    private func primaryIssue(
        in results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult]
    ) -> NetworkDiagnosticResult? {
        let externalSuccess = hasExternalSuccess(
            internet: results[.internet],
            proxy: results[.proxy]
        )
        let candidates = results.values.filter { result in
            switch result.id {
            case .path:
                result.status == .abnormal || result.status == .indeterminate
            case .gatewayReachability:
                (result.status == .abnormal || result.status == .indeterminate)
                    && results[.gatewayTCPReachability]?.status != .normal
                    && !isNeutralGateway(result, externalSuccess: externalSuccess)
            case .gatewayTCPReachability:
                false
            case .dns:
                result.status == .indeterminate
                    || (result.status == .abnormal && hasCorroboratedDNSFailure(result, internet: results[.internet]))
            case .internet, .proxy:
                result.status == .abnormal || result.status == .indeterminate
            case .ipv6:
                false
            }
        }
        return candidates.min { lhs, rhs in
            actionPriority(for: lhs).rawValue < actionPriority(for: rhs).rawValue
        }
    }

    private func actionPriority(for result: NetworkDiagnosticResult) -> DiagnosticActionPriority {
        let codes = Set(result.evidence.map(\.code))
        if result.id == .path, result.status == .abnormal {
            return .pathUnavailable
        }
        if codes.contains("captive-portal.redirect") || codes.contains("captive-portal.suspected") {
            return .captivePortal
        }
        if result.id == .proxy,
            let facts = result.proxyFacts,
            facts.http == .authenticationRequired || facts.https == .authenticationRequired
        {
            return .proxyAuthentication
        }
        if codes.contains("https.certificate-time-error") {
            return .certificateTime
        }
        if result.id == .proxy,
            codes.contains(where: { $0 == "proxy.endpoint-unavailable" || $0 == "proxy.egress-unavailable" })
        {
            return .proxyRoute
        }
        if result.id == .dns {
            return .dns
        }
        if result.id == .internet {
            return .targetTransport
        }
        return .indeterminate
    }

    private func hasExternalSuccess(
        internet: NetworkDiagnosticResult?,
        proxy: NetworkDiagnosticResult?
    ) -> Bool {
        hasDirectHTTPS(internet) || hasAvailableHTTPSProxy(proxy)
    }

    private func hasDirectHTTPS(_ result: NetworkDiagnosticResult?) -> Bool {
        result?.evidence.contains { $0.code == "https.available" } == true
    }

    private func hasCorroboratedDNSFailure(
        _ dns: NetworkDiagnosticResult,
        internet: NetworkDiagnosticResult?
    ) -> Bool {
        let samples = dns.evidence.filter { $0.code.hasPrefix("dns.sample.") }
        return samples.count == 3
            && samples.allSatisfy { $0.value == "failed" }
            && internet?.evidence.contains {
                $0.code == "https.connectivity-error"
                    && $0.value == String(URLError.dnsLookupFailed.rawValue)
            } == true
    }

    private func hasAvailableHTTPSProxy(_ result: NetworkDiagnosticResult?) -> Bool {
        result?.proxyFacts?.https == .available
    }

    private func isNeutralGateway(
        _ result: NetworkDiagnosticResult,
        externalSuccess: Bool
    ) -> Bool {
        guard externalSuccess, result.status == .indeterminate else { return false }
        return result.evidence.contains { $0.code == "gateway.no-response" }
    }

    private func isNeutralDirectProxy(
        _ result: NetworkDiagnosticResult,
        internet: NetworkDiagnosticResult?
    ) -> Bool {
        result.status == .indeterminate
            && internet?.status == .normal
            && result.proxyFacts?.http == .unverified
            && result.proxyFacts?.https == .unverified
            && hasExplicitDirectRouteEvidence(result)
            && !result.evidence.contains {
                $0.code == "proxy.http.resolution" || $0.code == "proxy.https.resolution"
            }
    }

    private func hasExplicitDirectRouteEvidence(_ result: NetworkDiagnosticResult) -> Bool {
        result.evidence.contains { evidence in
            if evidence.code == "proxy.http.route-type" || evidence.code == "proxy.https.route-type" {
                return evidence.value == "direct" || evidence.value == "tunnel"
            }
            if evidence.code == "proxy.http.egress-status" || evidence.code == "proxy.https.egress-status" {
                return evidence.value == "base-check"
            }
            return false
        }
    }

    private func isUnverifiedDirectRoute(
        proxy: NetworkDiagnosticResult,
        internet: NetworkDiagnosticResult?
    ) -> Bool {
        isNeutralDirectProxy(proxy, internet: internet)
    }
}
