import Foundation

struct ControlEndpointMetrics: Equatable, Sendable {
    let dnsDuration: Duration?
    let connectDuration: Duration?
    let tlsDuration: Duration?
    let negotiatedTLSVersion: String?
    let isProxyConnection: Bool?
    let remoteAddress: String?

    init(
        dnsDuration: Duration? = nil,
        connectDuration: Duration? = nil,
        tlsDuration: Duration? = nil,
        negotiatedTLSVersion: String? = nil,
        isProxyConnection: Bool? = nil,
        remoteAddress: String? = nil
    ) {
        self.dnsDuration = dnsDuration
        self.connectDuration = connectDuration
        self.tlsDuration = tlsDuration
        self.negotiatedTLSVersion = negotiatedTLSVersion
        self.isProxyConnection = isProxyConnection
        self.remoteAddress = remoteAddress
    }
}

struct ControlEndpointLoadResult: Equatable, Sendable {
    let status: Int?
    let body: String?
    let errorCode: String?
    let metrics: ControlEndpointMetrics?

    init(
        status: Int?,
        body: String?,
        errorCode: String?,
        metrics: ControlEndpointMetrics? = nil
    ) {
        self.status = status
        self.body = body
        self.errorCode = errorCode
        self.metrics = metrics
    }
}

protocol ControlEndpointLoading: Sendable {
    func load(
        url: URL,
        timeout: Duration
    ) async -> ControlEndpointLoadResult
}

struct SystemControlEndpointLoader: ControlEndpointLoading {
    static func configuration(timeout: Duration) -> URLSessionConfiguration {
        let timeoutInterval = timeout.controlEndpointTimeInterval
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.connectionProxyDictionary = [:]
        configuration.proxyConfigurations = []
        return configuration
    }

    func load(
        url: URL,
        timeout: Duration
    ) async -> ControlEndpointLoadResult {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout.controlEndpointTimeInterval
        )
        request.httpMethod = "GET"

        let metricsCollector = ControlEndpointMetricsCollector()
        let session = URLSession(
            configuration: Self.configuration(timeout: timeout),
            delegate: ControlEndpointDelegate(metricsCollector: metricsCollector),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return .init(status: nil, body: nil, errorCode: "non-http-response")
            }
            return .init(
                status: response.statusCode,
                body: String(data: data, encoding: .utf8),
                errorCode: nil,
                metrics: metricsCollector.metrics
            )
        } catch let error as URLError {
            return .init(status: nil, body: nil, errorCode: String(error.code.rawValue), metrics: metricsCollector.metrics)
        } catch {
            return .init(status: nil, body: nil, errorCode: String(describing: type(of: error)), metrics: metricsCollector.metrics)
        }
    }
}

struct HTTPSControlEndpointCheck: DiagnosticCheck {
    static let stableHTTPSEndpoint = URL(string: "https://www.apple.com/")!

    let id = NetworkDiagnosticCheckID.internet
    let httpsEndpoint = Self.stableHTTPSEndpoint
    // Authoritative captive-portal probe (Apple). HTTPS keeps the control
    // check free of the ATS exception still required by the HTTP-only
    // Microsoft NCSI target used in SystemProxyCheck.
    let captivePortalEndpoint = URL(string: "https://captive.apple.com/hotspot-detect.html")!
    let expectedCaptivePortalBody = "Success"

    private let loader: any ControlEndpointLoading
    private let timeout: Duration

    init(
        loader: any ControlEndpointLoading = SystemControlEndpointLoader(),
        timeout: Duration = .seconds(5)
    ) {
        self.loader = loader
        self.timeout = timeout
    }

    func run() async -> NetworkDiagnosticResult {
        async let httpsLoad = loader.load(url: httpsEndpoint, timeout: timeout)
        async let captivePortalLoad = loader.load(url: captivePortalEndpoint, timeout: timeout)
        let (httpsResponse, captivePortalResponse) = await (httpsLoad, captivePortalLoad)
        let httpsEvaluation = evaluateHTTPS(httpsResponse)
        let captivePortalEvaluation = evaluateCaptivePortal(captivePortalResponse)
        let status: NetworkDiagnosticStatus
        if httpsEvaluation.succeeded && captivePortalEvaluation.succeeded {
            status = .normal
        } else if httpsEvaluation.succeeded && captivePortalEvaluation.isIndeterminate {
            status = .indeterminate
        } else {
            status = .abnormal
        }

        let metricsEvidence = metricEvidence(for: httpsResponse.metrics, prefix: "https")
            + metricEvidence(for: captivePortalResponse.metrics, prefix: "captive-portal")
        return NetworkDiagnosticResult(
            id: id,
            status: status,
            summary: localizedSummary(for: status, httpsEvidence: httpsEvaluation.evidence),
            detail: localizedDetail(for: status),
            evidence: [httpsEvaluation.evidence, captivePortalEvaluation.evidence] + metricsEvidence
        )
    }

    private func metricEvidence(for metrics: ControlEndpointMetrics?, prefix: String) -> [NetworkDiagnosticEvidence] {
        guard let metrics else { return [] }
        var evidence: [NetworkDiagnosticEvidence] = []
        if let duration = metrics.dnsDuration {
            evidence.append(.init(code: "\(prefix).metrics.dns-ms", value: duration.millisecondsString))
        }
        if let duration = metrics.connectDuration {
            evidence.append(.init(code: "\(prefix).metrics.connect-ms", value: duration.millisecondsString))
        }
        if let duration = metrics.tlsDuration {
            evidence.append(.init(code: "\(prefix).metrics.tls-ms", value: duration.millisecondsString))
        }
        if let version = metrics.negotiatedTLSVersion {
            evidence.append(.init(code: "\(prefix).metrics.tls-version", value: version))
        }
        if let isProxyConnection = metrics.isProxyConnection {
            evidence.append(.init(code: "\(prefix).metrics.proxy", value: String(isProxyConnection)))
        }
        return evidence
    }

    private func evaluateHTTPS(
        _ response: ControlEndpointLoadResult
    ) -> EndpointEvaluation {
        if let errorCode = response.errorCode {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: httpsErrorEvidenceCode(errorCode), value: errorCode)
            )
        }
        guard let status = response.status else {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "https.transport-error", value: "unknown")
            )
        }
        guard (200..<300).contains(status) else {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "https.http-status", value: String(status))
            )
        }
        return EndpointEvaluation(
            succeeded: true,
            evidence: .init(code: "https.available", value: String(status))
        )
    }

    private func httpsErrorEvidenceCode(_ errorCode: String) -> String {
        guard let rawValue = Int(errorCode) else { return "https.transport-error" }
        switch URLError.Code(rawValue: rawValue) {
        case .secureConnectionFailed:
            return "https.tls-error"
        case .serverCertificateHasBadDate, .serverCertificateNotYetValid:
            return "https.certificate-time-error"
        case .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return "https.certificate-error"
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return "https.connectivity-error"
        default:
            return "https.transport-error"
        }
    }

    private func evaluateCaptivePortal(
        _ response: ControlEndpointLoadResult
    ) -> EndpointEvaluation {
        if let errorCode = response.errorCode {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "captive-portal.transport-error", value: errorCode),
                isIndeterminate: errorCode == String(URLError.timedOut.rawValue)
            )
        }
        guard let status = response.status else {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "captive-portal.transport-error", value: "unknown")
            )
        }
        if (300..<400).contains(status) {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "captive-portal.redirect", value: String(status))
            )
        }
        guard status == 200 else {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "captive-portal.http-status", value: String(status))
            )
        }
        guard response.body?.localizedCaseInsensitiveContains(expectedCaptivePortalBody) == true else {
            return EndpointEvaluation(
                succeeded: false,
                evidence: .init(code: "captive-portal.suspected", value: nil)
            )
        }
        return EndpointEvaluation(
            succeeded: true,
            evidence: .init(code: "captive-portal.clear", value: nil)
        )
    }

    private func localizedSummary(
        for status: NetworkDiagnosticStatus,
        httpsEvidence: NetworkDiagnosticEvidence
    ) -> String {
        switch status {
        case .normal:
            String(localized: "network_diagnostics.internet.normal.summary", comment: "Network self-check HTTPS control endpoint result summary")
        case .indeterminate:
            String(localized: "network_diagnostics.internet.indeterminate.summary", comment: "Network self-check HTTPS control endpoint result summary")
        case .abnormal, .blocked, .skipped:
            switch httpsEvidence.code {
            case "https.connectivity-error":
                String(localized: "network_diagnostics.internet.connectivity_failure.summary", comment: "Network self-check connectivity failure summary")
            case "https.tls-error", "https.certificate-error":
                String(localized: "network_diagnostics.internet.secure_connection_failure.summary", comment: "Network self-check TLS or certificate failure summary")
            case "https.certificate-time-error":
                String(localized: "network_diagnostics.internet.certificate_time_failure.summary", comment: "Network self-check certificate time failure summary")
            default:
                String(localized: "network_diagnostics.internet.abnormal.summary", comment: "Network self-check HTTPS control endpoint result summary")
            }
        }
    }

    private func localizedDetail(for status: NetworkDiagnosticStatus) -> String {
        switch status {
        case .normal:
            String(localized: "network_diagnostics.internet.normal.detail", comment: "Network self-check HTTPS control endpoint result detail")
        case .indeterminate:
            String(localized: "network_diagnostics.internet.indeterminate.detail", comment: "Network self-check HTTPS control endpoint result detail")
        case .abnormal, .blocked, .skipped:
            String(localized: "network_diagnostics.internet.abnormal.detail", comment: "Network self-check HTTPS control endpoint result detail")
        }
    }
}

private struct EndpointEvaluation {
    let succeeded: Bool
    let evidence: NetworkDiagnosticEvidence
    let isIndeterminate: Bool

    init(
        succeeded: Bool,
        evidence: NetworkDiagnosticEvidence,
        isIndeterminate: Bool = false
    ) {
        self.succeeded = succeeded
        self.evidence = evidence
        self.isIndeterminate = isIndeterminate
    }
}

private final class ControlEndpointMetricsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMetrics: ControlEndpointMetrics?

    var metrics: ControlEndpointMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return storedMetrics
    }

    func store(_ metrics: ControlEndpointMetrics) {
        lock.lock()
        storedMetrics = metrics
        lock.unlock()
    }
}

private final class ControlEndpointDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let metricsCollector: ControlEndpointMetricsCollector

    init(metricsCollector: ControlEndpointMetricsCollector) {
        self.metricsCollector = metricsCollector
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        metricsCollector.store(.init(
            dnsDuration: Self.duration(from: transaction.domainLookupStartDate, to: transaction.domainLookupEndDate),
            connectDuration: Self.duration(from: transaction.connectStartDate, to: transaction.connectEndDate),
            tlsDuration: Self.duration(from: transaction.secureConnectionStartDate, to: transaction.secureConnectionEndDate),
            negotiatedTLSVersion: transaction.negotiatedTLSProtocolVersion.map { String(describing: $0) },
            isProxyConnection: transaction.isProxyConnection
        ))
    }

    private static func duration(from start: Date?, to end: Date?) -> Duration? {
        guard let start, let end else { return nil }
        return .milliseconds(Int64(max(0, end.timeIntervalSince(start) * 1_000)))
    }
}

private extension Duration {
    var controlEndpointTimeInterval: TimeInterval {
        let components = self.components
        return max(
            0.001,
            Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }

    var millisecondsString: String {
        let components = self.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(Int64(max(0, milliseconds.rounded())))
    }
}
