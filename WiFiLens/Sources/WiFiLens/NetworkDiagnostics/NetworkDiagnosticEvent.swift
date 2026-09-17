import Foundation

enum DiagnosticEventKind: Equatable, Sendable {
    case sessionStarted
    case runStarted
    case checkStarted
    case checkFinished
    case restarted
    case timedOut
    case cancelled
    case completed
}

struct NetworkDiagnosticEvent: Equatable, Sendable {
    let runID: UUID
    let elapsedMilliseconds: Int64
    let kind: DiagnosticEventKind
    let checkID: NetworkDiagnosticCheckID?
    let reasonCode: String?

    var timestamp = Date()
    var runNumber = 0
    var result: DiagnosticLogResult?
    var durationMilliseconds: Int64?
    var conclusion: NetworkDiagnosticConclusion?
    var pendingIDs: [NetworkDiagnosticCheckID] = []
    var retainedIDs: [NetworkDiagnosticCheckID] = []

    var message: String {
        let run = runNumber > 0 ? "Run \(runNumber) · " : ""
        switch kind {
        case .sessionStarted:
            return "Session started"
        case .runStarted:
            let retained = retainedIDs.isEmpty ? "" : "; retained: " + retainedIDs.map(\.logTitle).joined(separator: ", ")
            return run + "Network self-check started" + retained
        case .checkStarted:
            return run + "Checking " + (checkID?.logTitle ?? "diagnostic")
        case .checkFinished:
            let title = checkID?.logTitle ?? "Diagnostic"
            let duration = durationMilliseconds.map { " (\(max(0, $0)) ms)" } ?? ""
            guard let result else { return run + title + ": result unavailable" + duration }
            return run + title + ": " + result.status.logTitle + " → "
                + (result.details.first ?? "No probe evidence") + duration
        case .restarted:
            return run + "Network changed; restarting (" + Self.reasonTitle(reasonCode) + ")"
        case .timedOut, .cancelled, .completed:
            let outcome: String
            switch kind {
            case .timedOut:
                outcome = reasonCode == "network-change"
                    ? "Timed out; network did not stabilize within the session budget"
                    : "Timed out; session budget exhausted"
            case .cancelled: outcome = "Cancelled by user"
            default:
                outcome = switch conclusion {
                case .networkNormal: "Network normal"
                case .needsAttention: "Needs attention"
                case .networkUnavailable: "Network unavailable"
                case nil: "Completed; conclusion unavailable"
                }
            }
            let pending = pendingIDs.isEmpty ? "" : "; unfinished: " + pendingIDs.map(\.logTitle).joined(separator: ", ")
            return run + "Summary: " + outcome + pending + " (\(max(0, elapsedMilliseconds)) ms total)"
        }
    }

    func formatted() -> String {
        formattedLines.joined(separator: "\n")
    }

    var formattedLines: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        let prefix = formatter.string(from: timestamp) + "  "
        var lines = [prefix + message]
        if kind == .checkFinished, let result {
            let context = "Run \(runNumber) · " + (checkID?.logTitle ?? "Diagnostic") + ": "
            lines += result.details.dropFirst().map { prefix + context + $0 }
        }
        return lines
    }

    private static func reasonTitle(_ reasonCode: String?) -> String {
        switch reasonCode {
        case .some("route"):
            "route"
        case .some("address"):
            "address"
        case .some("dns"):
            "DNS"
        case .some("proxy"):
            "proxy"
        case .some("path"):
            "path"
        case .some("network-change"):
            "network change"
        default:
            "network state"
        }
    }
}

/// A safe, English-only projection: localized summaries and arbitrary payloads
/// never enter the log store. Keep evidence values constrained by their meaning.
struct DiagnosticLogResult: Equatable, Sendable {
    let status: NetworkDiagnosticStatus
    let details: [String]

    init(_ result: NetworkDiagnosticResult) {
        status = result.status
        var details = result.evidence.compactMap(Self.describe)
        if result.id == .path {
            let state: String? = switch result.status {
            case .normal: "System network path is available"
            case .abnormal: "System network path is unsatisfied"
            default: nil
            }
            if let state { details.insert(state, at: 0) }
        }
        if let facts = result.proxyFacts {
            details.append("Final HTTP egress: " + Self.availability(facts.http))
            details.append("Final HTTPS egress: " + Self.availability(facts.https))
        }
        if details.isEmpty {
            let fallback = switch result.status {
            case .normal: "Check passed; no additional probe evidence"
            case .abnormal: "Check failed; no additional probe evidence"
            case .indeterminate: "Insufficient evidence to determine availability"
            case .blocked: "Not tested because a prerequisite failed"
            case .skipped: "Not tested; check not applicable"
            }
            details = [fallback]
        }
        self.details = details
    }

    private static func availability(_ value: DiagnosticRouteAvailability) -> String {
        switch value {
        case .available: "available"
        case .unavailable: "unavailable"
        case .authenticationRequired: "proxy authentication required"
        case .unverified: "not independently verified"
        }
    }

    private static func describe(_ evidence: NetworkDiagnosticEvidence) -> String? {
        let code = evidence.code
        let value = evidence.value ?? ""
        let fixed: [String: String] = [
            "gateway.no-response": "No ICMP reply; this alone does not prove the gateway is unavailable",
            "gateway.unreachable": "Gateway probe failed",
            "gateway.unavailable": "Gateway could not be determined",
            "gateway.route-changed": "Route changed before the gateway probe; result not established",
            "ipv6.available": "Forced IPv6 endpoint responded",
            "ipv6.unavailable": "Forced IPv6 endpoint did not respond",
            "ipv6.no-global-address": "No global IPv6 address; probe skipped",
            "captive-portal.clear": "HTTP captive-portal control response matched",
            "captive-portal.suspected": "HTTP control response differed; captive portal suspected",
            "check.failed": "Probe could not complete",
            "check.timeout": "Probe timed out at the session deadline",
            "proxy.endpoint-unavailable": "Proxy endpoint could not be reached",
            "proxy.authentication-required": "Proxy authentication required (HTTP 407)",
        ]
        if let description = fixed[code] { return description }
        if code == "blocked.by", let check = NetworkDiagnosticCheckID(rawValue: value) {
            return "Not tested because " + check.logTitle + " failed"
        }
        if code == "gateway.route-selection" {
            let reasons = ["unavailable": "No usable default IPv4 route", "ambiguous": "Default route is ambiguous",
                           "unsupported": "Default route does not support this gateway probe", "selected": "Default route selected",
                           "tunneled": "Default route selected through a VPN tunnel"]
            return reasons[value]
        }
        if code == "gateway.probe-scope" {
            return "Gateway probe scope: " + value
        }
        let interfaces = ["path.interface", "path.interface-name", "path.routed-tunnel", "gateway.interface", "gateway.route-interface",
                          "proxy.http.tunnel-interface", "proxy.https.tunnel-interface"]
        if interfaces.contains(code), value.range(of: #"^(en|utun|ipsec|ppp|bridge|lo|awdl|llw|gif|stf)[0-9]{1,5}$"#, options: .regularExpression) != nil {
            return ((code.contains("tunnel") || code == "gateway.route-interface") ? "Tunnel interface: " : "Interface: ") + value
        }
        if code == "path.interface-type" {
            let types = ["wifi": "Wi-Fi", "wiredEthernet": "Ethernet", "cellular": "Cellular", "loopback": "Loopback", "other": "Other"]
            return types[value].map { "Path type: " + $0 }
        }
        if code.hasPrefix("dns.sample.") {
            let sample = String(code.dropFirst("dns.sample.".count))
            guard ["apple", "microsoft", "msft-connect-test"].contains(sample)
                    || sample.range(of: #"^sample-[0-9]{1,3}$"#, options: .regularExpression) != nil,
                  ["resolved", "failed", "indeterminate"].contains(value) else { return nil }
            return "DNS sample " + sample + ": " + value
        }
        if ["dns.success-count", "dns.failure-count", "dns.indeterminate-count"].contains(code),
           value.range(of: #"^[0-9]{1,3}/[0-9]{1,3}$"#, options: .regularExpression) != nil {
            let label = code == "dns.success-count" ? "resolved" : code == "dns.failure-count" ? "failed" : "indeterminate"
            return "DNS samples " + label + ": " + value
        }
        let numbers = ["gateway.latency-ms": "Gateway ICMP RTT", "https.metrics.dns-ms": "HTTPS DNS",
                       "https.metrics.connect-ms": "HTTPS connect", "https.metrics.tls-ms": "HTTPS TLS",
                       "http.metrics.dns-ms": "HTTP DNS", "http.metrics.connect-ms": "HTTP connect",
                       "captive-portal.metrics.dns-ms": "HTTP DNS", "captive-portal.metrics.connect-ms": "HTTP connect"]
        if let label = numbers[code], let number = Double(value), number.isFinite, number >= 0, value.count <= 24 {
            return label + ": " + String(number) + " ms"
        }
        let responses = ["https.available": "HTTPS responded", "https.http-status": "HTTPS unexpected response",
                         "captive-portal.redirect": "HTTP control redirected; captive portal suspected",
                         "captive-portal.http-status": "HTTP control unexpected response"]
        if let label = responses[code], let status = Int(value), (100...599).contains(status) {
            return label + ": HTTP " + String(status)
        }
        let errors = ["https.connectivity-error": "HTTPS connection failed", "https.tls-error": "HTTPS TLS failed",
                      "https.certificate-error": "HTTPS certificate validation failed",
                      "https.certificate-time-error": "HTTPS certificate validity dates failed",
                      "https.transport-error": "HTTPS transport failed", "captive-portal.transport-error": "HTTP control transport failed"]
        if let label = errors[code] { return label + ": " + errorDescription(value) }
        for scheme in ["http", "https"] {
            let prefix = "proxy." + scheme + "."
            guard code.hasPrefix(prefix) else { continue }
            let field = String(code.dropFirst(prefix.count))
            let label = "Proxy " + scheme.uppercased()
            switch field {
            case "candidate-index":
                guard let index = Int(value), (0..<1000).contains(index) else { return nil }
                return label + " candidate " + String(index + 1)
            case "route-type":
                guard ["direct", "tunnel", "http", "https", "socks", "unavailable"].contains(value) else { return nil }
                return label + " route: " + value
            case "endpoint-status", "authentication-status", "egress-status":
                if let status = Int(value), (100...599).contains(status) { return label + " " + field.replacingOccurrences(of: "-status", with: "") + ": HTTP " + String(status) }
                if let error = Int(value), error < 0 { return label + " " + field.replacingOccurrences(of: "-status", with: "") + ": " + errorDescription(value) }
                guard ["available", "unavailable", "required", "not-required", "not-tested", "timed-out", "base-check", "unknown"].contains(value) else { return nil }
                return label + " " + field.replacingOccurrences(of: "-status", with: "") + ": " + (value == "base-check" ? "see base Internet check" : value)
            case "resolution":
                let reasons = [
                    "pac-execution-failed": "PAC execution failed", "pac-execution-invalid": "PAC result invalid",
                    "pac-timeout": "PAC evaluation timed out", "pac-cancelled": "PAC evaluation cancelled",
                    "pac-script-unsupported": "PAC scripts unsupported", "pac-url-unavailable": "PAC URL unavailable",
                    "pac-script-unavailable": "PAC script unavailable", "proxy-endpoint-invalid": "Proxy endpoint invalid",
                    "proxy-type-unsupported": "Proxy type unsupported", "settings-unavailable": "System settings unavailable",
                    "resolution-empty": "No route candidates returned", "resolution-cancelled": "Resolution cancelled",
                    "resolution-invalid": "Resolution result invalid",
                ]
                return label + " resolution: " + (reasons[value] ?? "Could not complete")
            case "timeout": return label + " candidate budget exhausted"
            case "cancelled": return label + " probe cancelled"
            case "tunnel-detection-source":
                return value == "nwpath" ? "Tunnel confirmed on active path" : "Tunnel interface detected; target routing not confirmed"
            default: return nil
            }
        }
        return nil
    }

    private static func errorDescription(_ value: String) -> String {
        guard let code = Int(value), (-100_000...(-1)).contains(code) else { return "unknown error" }
        let reason: String = switch code {
        case -1001: "timed out"
        case -1003: "host not found"
        case -1004: "could not connect to host"
        case -1005: "connection lost"
        case -1006: "DNS lookup failed"
        case -1009: "no Internet connection"
        case -1200: "TLS negotiation failed"
        case -1201: "certificate date invalid"
        case -1202: "certificate untrusted"
        case -1203: "certificate root unknown"
        case -1204: "certificate not yet valid"
        default: "transport error"
        }
        return reason + " (" + String(code) + ")"
    }
}
