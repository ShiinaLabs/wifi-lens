import Foundation
import WiFiLensCore

enum NetworkDiagnosticStatus: String, CaseIterable, Equatable, Sendable {
    case normal, abnormal, indeterminate, blocked, skipped

    var logTitle: String {
        switch self {
        case .normal:
            "Normal"
        case .abnormal:
            "Abnormal"
        case .indeterminate:
            "Indeterminate"
        case .blocked:
            "Blocked"
        case .skipped:
            "Skipped"
        }
    }
}

enum NetworkDiagnosticCheckID: String, CaseIterable, Equatable, Hashable, Sendable {
    case path, gatewayReachability, dns, internet, ipv6, proxy

    var logTitle: String {
        switch self {
        case .path:
            "Network Path"
        case .gatewayReachability:
            "Gateway Reachability"
        case .dns:
            "DNS Resolution"
        case .internet:
            "Internet Access"
        case .ipv6:
            "IPv6 Connectivity"
        case .proxy:
            "System Proxy"
        }
    }

    var localizedTitle: String {
        switch self {
        case .path:
            String(localized: "network_diagnostics.check.path.title", comment: "Network system path check title")
        case .gatewayReachability:
            String(localized: "network_diagnostics.check.gateway_reachability.title", comment: "Gateway reachability check title")
        case .dns:
            String(localized: "network_diagnostics.check.dns.title", comment: "DNS resolution check title")
        case .internet:
            String(localized: "network_diagnostics.check.internet.title", comment: "Internet access check title")
        case .ipv6:
            String(localized: "network_diagnostics.check.ipv6.title", comment: "Optional forced IPv6 access check title")
        case .proxy:
            String(localized: "network_diagnostics.check.proxy.title", comment: "System proxy check title")
        }
    }
}

struct NetworkDiagnosticsLogStore: Equatable, Sendable {
    static let capacity = 500
    static let truncationMarker = "… earlier diagnostic events omitted …"

    private(set) var lines: [String] = []
    private(set) var events: [NetworkDiagnosticEvent] = []
    private var hasTruncationMarker = false

    var text: String {
        lines.joined(separator: "\n")
    }

    mutating func append(_ line: String) {
        appendLine(line)
    }

    mutating func append(_ event: NetworkDiagnosticEvent) {
        // Start events remain available for diagnostics, but only results and
        // meaningful session transitions occupy the user-facing console.
        if event.kind != .sessionStarted && event.kind != .checkStarted {
            event.formattedLines.forEach { appendLine($0) }
        }
        events.append(event)
        if events.count > Self.capacity - 1 {
            events.removeFirst(events.count - (Self.capacity - 1))
        }
    }

    private mutating func appendLine(_ line: String) {
        if lines.count >= Self.capacity {
            if hasTruncationMarker {
                if lines.count > 1 {
                    lines.remove(at: 1)
                } else {
                    lines.removeFirst()
                }
            } else {
                lines.removeFirst()
                lines.insert(Self.truncationMarker, at: 0)
                hasTruncationMarker = true
            }
            if lines.count >= Self.capacity {
                lines.removeLast()
            }
        }
        lines.append(line)
    }

    mutating func reset() {
        lines.removeAll(keepingCapacity: true)
        events.removeAll(keepingCapacity: true)
        hasTruncationMarker = false
    }
}

enum NetworkDiagnosticStatusTone: Equatable, Sendable {
    case success
    case error
    case caution
    case informational
    case muted
}

struct NetworkDiagnosticStatusPresentation: Equatable, Sendable {
    let labelKey: String
    let icon: String
    let tone: NetworkDiagnosticStatusTone
}

extension NetworkDiagnosticStatus {
    var presentation: NetworkDiagnosticStatusPresentation {
        switch self {
        case .normal:
            .init(labelKey: "network_diagnostics.status.normal", icon: "checkmark.circle.fill", tone: .success)
        case .abnormal:
            .init(labelKey: "network_diagnostics.status.abnormal", icon: "xmark.circle.fill", tone: .error)
        case .indeterminate:
            .init(labelKey: "network_diagnostics.status.indeterminate", icon: "questionmark.circle.fill", tone: .caution)
        case .blocked:
            .init(labelKey: "network_diagnostics.status.blocked", icon: "lock.fill", tone: .informational)
        case .skipped:
            .init(labelKey: "network_diagnostics.status.skipped", icon: "forward.fill", tone: .muted)
        }
    }

    var localizedTitle: String {
        String(
            localized: .init(stringLiteral: presentation.labelKey),
            comment: "Network self-check status title"
        )
    }
}

struct NetworkDiagnosticEvidence: Equatable, Sendable {
    let code: String
    let value: String?
}

struct NetworkDiagnosticRemediation: Equatable, Sendable {
    let detectionKey: String
    let causeKey: String
    let actionKey: String
    let rerunKey: String

    static func forResult(_ result: NetworkDiagnosticResult) -> Self {
        var codes = Set(result.evidence.map(\.code))
        if result.id == .proxy, let facts = result.proxyFacts {
            if facts.http != .authenticationRequired && facts.https != .authenticationRequired {
                codes.remove("proxy.authentication-required")
                codes.remove("proxy.http.authentication-required")
                codes.remove("proxy.https.authentication-required")
            }
            if facts.http != .unavailable && facts.https != .unavailable {
                codes.remove("proxy.endpoint-unavailable")
                codes.remove("proxy.egress-unavailable")
                codes.remove("proxy.http.endpoint-unavailable")
                codes.remove("proxy.https.endpoint-unavailable")
                codes.remove("proxy.http.egress-unavailable")
                codes.remove("proxy.https.egress-unavailable")
            }
        }
        let base: (String, String, String) = if codes.contains("proxy.authentication-required") {
            (
                "network_diagnostics.remediation.proxy_authentication.detection",
                "network_diagnostics.remediation.proxy_authentication.cause",
                "network_diagnostics.remediation.proxy_authentication.action"
            )
        } else if codes.contains("captive-portal.suspected") || codes.contains("captive-portal.redirect") {
            (
                "network_diagnostics.remediation.captive_portal.detection",
                "network_diagnostics.remediation.captive_portal.cause",
                "network_diagnostics.remediation.captive_portal.action"
            )
        } else if codes.contains("https.certificate-time-error") {
            (
                "network_diagnostics.remediation.certificate_time.detection",
                "network_diagnostics.remediation.certificate_time.cause",
                "network_diagnostics.remediation.certificate_time.action"
            )
        } else if codes.contains("proxy.endpoint-unavailable") || codes.contains("proxy.egress-unavailable") {
            (
                "network_diagnostics.remediation.proxy_unavailable.detection",
                "network_diagnostics.remediation.proxy_unavailable.cause",
                "network_diagnostics.remediation.proxy_unavailable.action"
            )
        } else if result.id == .dns && result.status == .abnormal {
            (
                "network_diagnostics.remediation.dns_unavailable.detection",
                "network_diagnostics.remediation.dns_unavailable.cause",
                "network_diagnostics.remediation.dns_unavailable.action"
            )
        } else if result.id == .path && result.status == .abnormal {
            (
                "network_diagnostics.remediation.path_unavailable.detection",
                "network_diagnostics.remediation.path_unavailable.cause",
                "network_diagnostics.remediation.path_unavailable.action"
            )
        } else if result.status == .indeterminate {
            (
                "network_diagnostics.remediation.indeterminate.detection",
                "network_diagnostics.remediation.indeterminate.cause",
                "network_diagnostics.remediation.indeterminate.action"
            )
        } else {
            (
                "network_diagnostics.remediation.generic.detection",
                "network_diagnostics.remediation.generic.cause",
                "network_diagnostics.remediation.generic.action"
            )
        }

        return .init(
            detectionKey: base.0,
            causeKey: base.1,
            actionKey: base.2,
            rerunKey: "network_diagnostics.remediation.rerun"
        )
    }
}

extension NetworkDiagnosticConclusion {
    static func primaryIssue(in results: [NetworkDiagnosticResult]) -> NetworkDiagnosticResult? {
        let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        return NetworkDiagnosticAssessmentResolver()
            .resolve(
                results: resultsByID,
                complete: Set(resultsByID.keys) == Set(NetworkDiagnosticCheckID.allCases)
            )
            .primaryIssue
    }
}

enum NetworkDiagnosticStage: CaseIterable, Equatable, Sendable {
    case thisMac
    case lan
    case internet

    var contributingCheckIDs: [NetworkDiagnosticCheckID] {
        switch self {
        case .thisMac: [.path, .dns, .proxy]
        case .lan: [.gatewayReachability]
        case .internet: [.internet]
        }
    }
}

struct NetworkDiagnosticStageResolver: Sendable {
    func status(
        for stage: NetworkDiagnosticStage,
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult]
    ) -> NetworkDiagnosticStatus? {
        NetworkDiagnosticAssessmentResolver()
            .resolve(results: results, complete: false)
            .stages
            .first { $0.stage == stage }?
            .status
    }
}

struct NetworkDiagnosticResult: Equatable, Identifiable, Sendable {
    let id: NetworkDiagnosticCheckID
    let status: NetworkDiagnosticStatus
    let summary: String
    let detail: String?
    let evidence: [NetworkDiagnosticEvidence]
    let proxyFacts: DiagnosticProxyFacts?

    init(
        id: NetworkDiagnosticCheckID,
        status: NetworkDiagnosticStatus,
        summary: String,
        detail: String? = nil,
        evidence: [NetworkDiagnosticEvidence] = [],
        proxyFacts: DiagnosticProxyFacts? = nil
    ) {
        self.id = id
        self.status = status
        self.summary = summary
        self.detail = detail
        self.evidence = evidence
        self.proxyFacts = proxyFacts
    }

    static func blocked(id: NetworkDiagnosticCheckID, summary: String) -> Self {
        .init(id: id, status: .blocked, summary: summary, detail: summary)
    }
}

enum NetworkDiagnosticConclusion: String, Equatable, Sendable {
    case networkNormal
    case needsAttention
    case networkUnavailable

    static func evaluate(
        _ results: [NetworkDiagnosticResult],
        requiredIDs: Set<NetworkDiagnosticCheckID> = Set(NetworkDiagnosticCheckID.allCases)
    ) -> Self? {
        let resultsByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        guard Set(resultsByID.keys) == requiredIDs else { return nil }
        return NetworkDiagnosticAssessmentResolver()
            .resolve(
                results: resultsByID,
                complete: true,
                requiredIDs: requiredIDs
            )
            .conclusion
    }
}
