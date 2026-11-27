import Foundation
import WiFiLensCoreRust

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
        let stageResolution = resolveStages(results: results)
        guard complete,
            Set(results.keys) == requiredIDs
        else {
            return NetworkDiagnosticAssessment(
                conclusion: nil,
                stages: stageResolution.stages,
                primaryIssue: primaryIssue(
                    in: results,
                    neutralGateway: stageResolution.neutralGateway
                )
            )
        }

        let conclusion = conclusion(
            results: results,
            externalSuccess: stageResolution.externalSuccess,
            neutralDirectProxy: stageResolution.neutralDirectProxy
        )
        var issue = primaryIssue(
            in: results,
            neutralGateway: stageResolution.neutralGateway
        )
        if let boundaryFailure,
            issue?.id == .internet
                || (issue?.id == .dns && boundaryFailure != .carrier),
            results[.path]?.status == .normal,
            results[.gatewayReachability]?.status == .normal
                || results[.gatewayTCPReachability]?.status == .normal,
            let internet = results[.internet], internet.status == .abnormal,
            !stageResolution.externalSuccess,
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
                evidence: internet.evidence + [
                    .init(code: boundaryFailure.rawValue, value: unresponsiveGateway?.address)
                ]
            )
        }
        return NetworkDiagnosticAssessment(
            conclusion: conclusion,
            stages: stageResolution.stages,
            primaryIssue: issue
        )
    }

    private func resolveStages(
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult]
    ) -> (
        stages: [DiagnosticStageAssessment], externalSuccess: Bool, neutralDirectProxy: Bool, neutralGateway: Bool
    ) {
        func statusCode(_ status: NetworkDiagnosticStatus?) -> Int32 {
            switch status {
            case nil: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING
            case .normal: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL
            case .abnormal: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL
            case .indeterminate: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE
            case .blocked: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED
            case .skipped: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED
            }
        }

        func proxyAvailabilityCode(_ availability: DiagnosticRouteAvailability?) -> Int32 {
            switch availability {
            case .none: WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_FACTS_MISSING
            case .some(.available): WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AVAILABLE
            case .some(.unavailable): WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNAVAILABLE
            case .some(.authenticationRequired): WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AUTHENTICATION_REQUIRED
            case .some(.unverified): WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNVERIFIED
            }
        }

        let proxyEvidence = results[.proxy]?.evidence ?? []
        var flags: UInt32 = 0
        if results[.internet]?.evidence.contains(where: { $0.code == "https.available" }) == true {
            flags |= WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE
        }
        if results[.gatewayReachability]?.evidence.contains(where: { $0.code == "gateway.no-response" }) == true {
            flags |= WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE
        }
        if proxyEvidence.contains(where: { evidence in
            if evidence.code == "proxy.http.route-type" || evidence.code == "proxy.https.route-type" {
                return evidence.value == "direct" || evidence.value == "tunnel"
            }
            if evidence.code == "proxy.http.egress-status" || evidence.code == "proxy.https.egress-status" {
                return evidence.value == "base-check"
            }
            return false
        }) {
            flags |= WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE
        }
        if proxyEvidence.contains(where: {
            $0.code == "proxy.http.resolution" || $0.code == "proxy.https.resolution"
        }) {
            flags |= WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE
        }

        let input = WiFiLensDiagnosticStageInput(
            path_status: statusCode(results[.path]?.status),
            gateway_reachability_status: statusCode(results[.gatewayReachability]?.status),
            gateway_tcp_reachability_status: statusCode(results[.gatewayTCPReachability]?.status),
            dns_status: statusCode(results[.dns]?.status),
            internet_status: statusCode(results[.internet]?.status),
            proxy_status: statusCode(results[.proxy]?.status),
            proxy_http_availability: proxyAvailabilityCode(results[.proxy]?.proxyFacts?.http),
            proxy_https_availability: proxyAvailabilityCode(results[.proxy]?.proxyFacts?.https),
            flags: flags
        )
        var output = WiFiLensDiagnosticStageResult()
        let status = withUnsafePointer(to: input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                wifi_lens_diagnostic_stage_assess(inputPointer, outputPointer)
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            assertionFailure("Rust diagnostic stage assessment returned status \(status)")
            return (
                NetworkDiagnosticStage.allCases.map { .init(stage: $0, status: nil, qualificationCode: nil) },
                false,
                false,
                false
            )
        }

        func mappedStatus(_ code: Int32) -> NetworkDiagnosticStatus? {
            switch code {
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING: return nil
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL: return .normal
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL: return .abnormal
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE: return .indeterminate
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED: return .blocked
            case WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED: return .skipped
            default:
                assertionFailure("Rust diagnostic stage assessment returned status code \(code)")
                return nil
            }
        }

        func qualificationCode(_ code: Int32) -> String? {
            switch code {
            case WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_NONE: return nil
            case WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_PROXY_DIRECT_UNVERIFIED: return "proxy.direct-unverified"
            case WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_GATEWAY_UNVERIFIED: return "gateway.unverified"
            default:
                assertionFailure("Rust diagnostic stage assessment returned qualification code \(code)")
                return nil
            }
        }

        return (
            [
                .init(
                    stage: .thisMac,
                    status: mappedStatus(output.this_mac_status),
                    qualificationCode: qualificationCode(output.this_mac_qualification)
                ),
                .init(
                    stage: .lan,
                    status: mappedStatus(output.lan_status),
                    qualificationCode: qualificationCode(output.lan_qualification)
                ),
                .init(
                    stage: .internet,
                    status: mappedStatus(output.internet_status),
                    qualificationCode: qualificationCode(output.internet_qualification)
                ),
            ],
            output.external_success != 0,
            output.neutral_direct_proxy != 0,
            output.neutral_gateway != 0
        )
    }

    private func conclusion(
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        externalSuccess: Bool,
        neutralDirectProxy: Bool
    ) -> NetworkDiagnosticConclusion {
        let path = results[.path]
        let internet = results[.internet]
        let gateway = results[.gatewayReachability]
        let dns = results[.dns]
        let proxy = results[.proxy]
        let gatewayIsNeutral =
            externalSuccess && gateway?.status == .indeterminate
            && gateway?.evidence.contains { $0.code == "gateway.no-response" } == true
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
                        && !gatewayIsNeutral
                        && result.status != .normal
                        && result.status != .skipped
                case .gatewayTCPReachability:
                    false
                case .dns, .internet:
                    result.status != .normal
                case .proxy:
                    !neutralDirectProxy
                        && result.status != .normal
                case .ipv6:
                    false
                }
            }
        return hasActionableIssue ? .needsAttention : .networkNormal
    }

    private func primaryIssue(
        in results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        neutralGateway: Bool
    ) -> NetworkDiagnosticResult? {
        let candidates = results.values.filter { result in
            switch result.id {
            case .path:
                result.status == .abnormal || result.status == .indeterminate
            case .gatewayReachability:
                (result.status == .abnormal || result.status == .indeterminate)
                    && results[.gatewayTCPReachability]?.status != .normal
                    && !neutralGateway
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

    private func hasDirectHTTPS(_ result: NetworkDiagnosticResult?) -> Bool {
        result?.evidence.contains { $0.code == "https.available" } == true
    }

    private func hasAvailableHTTPSProxy(_ result: NetworkDiagnosticResult?) -> Bool {
        result?.proxyFacts?.https == .available
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
}
