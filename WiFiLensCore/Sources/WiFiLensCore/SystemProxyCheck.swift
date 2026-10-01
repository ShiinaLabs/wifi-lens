import CFNetwork
import Foundation
import Network

struct ProxyEndpoint: Hashable, Sendable {
    let host: String
    let port: UInt16

    init(host: String, port: UInt16) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.port = port
    }
}

struct SystemProxyConfiguration: Equatable, Sendable {
    var endpoints: [ProxyEndpoint] = []
    var pacEnabled = false
    var pacURL: String?
    var autoDiscoveryEnabled = false
    var hasInvalidExplicitProxy = false

    static let disabled = SystemProxyConfiguration()

    init(
        endpoints: [ProxyEndpoint] = [],
        pacEnabled: Bool = false,
        pacURL: String? = nil,
        autoDiscoveryEnabled: Bool = false,
        hasInvalidExplicitProxy: Bool = false
    ) {
        self.endpoints = endpoints
        self.pacEnabled = pacEnabled
        self.pacURL = pacURL
        self.autoDiscoveryEnabled = autoDiscoveryEnabled
        self.hasInvalidExplicitProxy = hasInvalidExplicitProxy
    }

    init(settings: [String: Any]) {
        var endpoints: [ProxyEndpoint] = []
        var seen: Set<ProxyEndpoint> = []
        var invalid = false

        for keys in [
            ("HTTPEnable", "HTTPProxy", "HTTPPort"),
            ("HTTPSEnable", "HTTPSProxy", "HTTPSPort"),
            ("SOCKSEnable", "SOCKSProxy", "SOCKSPort"),
        ] where Self.isEnabled(settings[keys.0]) {
            guard
                let rawHost = settings[keys.1] as? String,
                !rawHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let rawPort = Self.integer(settings[keys.2]),
                (1...Int(UInt16.max)).contains(rawPort)
            else {
                invalid = true
                continue
            }

            let endpoint = ProxyEndpoint(host: rawHost, port: UInt16(rawPort))
            if seen.insert(endpoint).inserted {
                endpoints.append(endpoint)
            }
        }

        self.init(
            endpoints: endpoints,
            pacEnabled: Self.isEnabled(settings["ProxyAutoConfigEnable"]),
            pacURL: Self.nonemptyString(settings["ProxyAutoConfigURLString"]),
            autoDiscoveryEnabled: Self.isEnabled(settings["ProxyAutoDiscoveryEnable"]),
            hasInvalidExplicitProxy: invalid
        )
    }

    private static func isEnabled(_ value: Any?) -> Bool {
        integer(value).map { $0 != 0 } ?? false
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol SystemProxySettingsReading: Sendable {
    func read() -> SystemProxyConfiguration?
}

struct SystemProxySettingsReader: SystemProxySettingsReading {
    func read() -> SystemProxyConfiguration? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return SystemProxyConfiguration(settings: settings)
    }
}

enum ProxyTunnelDetectionSource: String, Equatable, Sendable {
    case nwpath
    case activeInterface = "active-interface"
}

struct ProxyTunnelState: Equatable, Sendable {
    let interface: String
    let source: ProxyTunnelDetectionSource
}

protocol ProxyTunnelStateReading: Sendable {
    func tunnelState() async -> ProxyTunnelState?
}

struct SystemProxyTunnelStateReader: ProxyTunnelStateReading {
    static let pathWaitTimeout: Duration = .seconds(1)

    func tunnelState() async -> ProxyTunnelState? {
        let path = await Self.firstPath(
            from: Self.makePathStream(),
            timeout: {
                try? await Task.sleep(for: Self.pathWaitTimeout)
            }
        )
        let pathRouted = path.flatMap {
            SystemNetworkTunnelStateReader.state(for: $0).routedTunnelInterface
        }
        return Self.candidateTunnelState(
            pathRouted: pathRouted,
            activeIPv4Tunnels: Self.activeIPv4TunnelInterfaces()
        )
    }

    static func candidateTunnelState(
        pathRouted: String?,
        activeIPv4Tunnels: [String]
    ) -> ProxyTunnelState? {
        if let pathRouted {
            return ProxyTunnelState(interface: pathRouted, source: .nwpath)
        }
        guard let first = activeIPv4Tunnels.first else { return nil }
        return ProxyTunnelState(interface: first, source: .activeInterface)
    }

    static func firstPath(
        from stream: AsyncStream<NWPath>,
        timeout: @escaping @Sendable () async -> Void
    ) async -> NWPath? {
        await withTaskGroup(of: NWPath?.self) { group in
            group.addTask {
                for await path in stream {
                    return path
                }
                return nil
            }
            group.addTask {
                await timeout()
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func makePathStream() -> AsyncStream<NWPath> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path)
                continuation.finish()
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.proxy-tunnel"))
        }
    }

    static func activeIPv4TunnelInterfaces() -> [String] {
        var addrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrPtr) == 0, let first = addrPtr else { return [] }
        defer { freeifaddrs(first) }

        var byName: [String: (up: Bool, hasIPv4: Bool)] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let namePtr = ptr.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            let flags = ptr.pointee.ifa_flags
            var entry = byName[name] ?? (up: false, hasIPv4: false)
            entry.up = entry.up
                || (flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0)
            if let addr = ptr.pointee.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_INET) {
                entry.hasIPv4 = true
            }
            byName[name] = entry
        }

        return byName
            .filter { name, entry in
                NetworkTunnelInterfaceClassifier.prefixes.contains { name.hasPrefix($0) }
                    && entry.up
                    && entry.hasIPv4
            }
            .keys
            .sorted()
    }
}

protocol ProxyEndpointConnecting: Sendable {
    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool
}

struct NetworkProxyEndpointConnector: ProxyEndpointConnecting {
    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        let context = ProxyConnectionContext(connection: connection)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard context.install(continuation: continuation) else { return }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        context.finish(true)
                    case .failed, .cancelled:
                        context.finish(false)
                    default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.proxy"))
                let timeoutTask = Task { [context] in
                    do {
                        try await Task.sleep(for: timeout)
                        context.finish(false)
                    } catch {
                        // The connection completed or the caller cancelled.
                    }
                }
                context.install(timeoutTask: timeoutTask)
            }
        } onCancel: {
            context.cancel()
        }
    }
}

private final class ProxyConnectionContext: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?
    private var cancellationRequested = false
    private var didFinish = false
    private var timeoutTask: Task<Void, Never>?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func install(continuation: CheckedContinuation<Bool, Never>) -> Bool {
        lock.lock()
        guard !cancellationRequested, !didFinish else {
            lock.unlock()
            continuation.resume(returning: false)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(timeoutTask: Task<Void, Never>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func finish(_ reachable: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()
        timeoutTask?.cancel()
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(returning: reachable)
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        connection.cancel()
        finish(false)
    }
}

struct ProxyEgressResponse: Equatable, Sendable {
    let statusCode: Int?
    let errorCode: String?
}

protocol ProxyEgressLoading: Sendable {
    func load(
        url: URL,
        through proxy: EffectiveProxy,
        timeout: Duration
    ) async -> ProxyEgressResponse
}

struct SystemProxyEgressLoader: ProxyEgressLoading {
    func load(
        url: URL,
        through proxy: EffectiveProxy,
        timeout: Duration
    ) async -> ProxyEgressResponse {
        guard let configuration = Self.configuration(for: proxy, timeout: timeout) else {
            return ProxyEgressResponse(statusCode: nil, errorCode: "proxy-type-unavailable")
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout.proxyCheckTimeInterval
        )
        request.httpMethod = "GET"

        let session = URLSession(
            configuration: configuration,
            delegate: ProxyEgressRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return ProxyEgressResponse(statusCode: nil, errorCode: "non-http-response")
            }
            return ProxyEgressResponse(statusCode: response.statusCode, errorCode: nil)
        } catch let error as URLError {
            return Self.response(for: error)
        } catch {
            return ProxyEgressResponse(statusCode: nil, errorCode: "request-failed")
        }
    }

    static func response(for error: URLError) -> ProxyEgressResponse {
        if error.code == .userAuthenticationRequired {
            return ProxyEgressResponse(statusCode: 407, errorCode: nil)
        }
        return ProxyEgressResponse(statusCode: nil, errorCode: String(error.code.rawValue))
    }

    static func configuration(
        for proxy: EffectiveProxy,
        timeout: Duration
    ) -> URLSessionConfiguration? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = timeout.proxyCheckTimeInterval
        configuration.timeoutIntervalForResource = timeout.proxyCheckTimeInterval

        switch proxy {
        case .http(let endpoint):
            configuration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: endpoint.host,
                kCFNetworkProxiesHTTPPort as String: Int(endpoint.port),
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
                kCFNetworkProxiesProxyAutoConfigEnable as String: false,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            ]
            configuration.proxyConfigurations = []
        case .https(let endpoint):
            guard let networkEndpoint = endpoint.networkEndpoint else { return nil }
            var selectedProxy = ProxyConfiguration(httpCONNECTProxy: networkEndpoint)
            selectedProxy.allowFailover = false
            configuration.connectionProxyDictionary = [:]
            configuration.proxyConfigurations = [selectedProxy]
        case .socks(let endpoint):
            guard let networkEndpoint = endpoint.networkEndpoint else { return nil }
            var selectedProxy = ProxyConfiguration(socksv5Proxy: networkEndpoint)
            selectedProxy.allowFailover = false
            configuration.connectionProxyDictionary = [:]
            configuration.proxyConfigurations = [selectedProxy]
        case .direct, .unavailable:
            return nil
        }
        return configuration
    }
}

private extension ProxyEndpoint {
    var networkEndpoint: NWEndpoint? {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else { return nil }
        return .hostPort(
            host: NWEndpoint.Host(host),
            port: networkPort
        )
    }
}

protocol ProxyCheckClock: Sendable {
    func now() -> ContinuousClock.Instant
}

struct ContinuousProxyCheckClock: ProxyCheckClock {
    private let clock = ContinuousClock()

    func now() -> ContinuousClock.Instant {
        clock.now
    }
}

struct SystemProxyCheck: DiagnosticCheck {
    let id = NetworkDiagnosticCheckID.proxy
    // Authoritative Microsoft NCSI endpoint. Kept as plain HTTP on purpose:
    // the proxy check exercises the same unencrypted request a captive
    // portal would intercept. Covered by the scoped ATS exception for
    // www.msftconnecttest.com only; no personal data is transmitted.
    private static let defaultHTTPTarget = URL(
        string: "http://www.msftconnecttest.com/connecttest.txt"
    )!
    private static let defaultHTTPSTarget = URL(string: "https://www.apple.com/")!

    private let resolver: any ProxyResolving
    private let connector: any ProxyEndpointConnecting
    private let egressLoader: any ProxyEgressLoading
    private let tunnelReader: any ProxyTunnelStateReading
    private let httpTarget: URL
    private let httpsTarget: URL
    private let timeout: Duration
    private let clock: any ProxyCheckClock

    init(
        resolver: any ProxyResolving = SystemProxyResolver(),
        connector: any ProxyEndpointConnecting = NetworkProxyEndpointConnector(),
        egressLoader: any ProxyEgressLoading = SystemProxyEgressLoader(),
        tunnelReader: any ProxyTunnelStateReading = SystemProxyTunnelStateReader(),
        httpTarget: URL = Self.defaultHTTPTarget,
        httpsTarget: URL = Self.defaultHTTPSTarget,
        timeout: Duration = .seconds(3),
        clock: any ProxyCheckClock = ContinuousProxyCheckClock()
    ) {
        self.resolver = resolver
        self.connector = connector
        self.egressLoader = egressLoader
        self.tunnelReader = tunnelReader
        self.httpTarget = httpTarget
        self.httpsTarget = httpsTarget
        self.timeout = timeout
        self.clock = clock
    }

    func run() async -> NetworkDiagnosticResult {
        guard !Task.isCancelled else {
            return cancellationResult(stage: "before-http-resolution")
        }
        async let tunnelStateTask = tunnelReader.tunnelState()
        async let httpResolutionTask = resolver.resolve(for: httpTarget)
        async let httpsResolutionTask = resolver.resolve(for: httpsTarget)
        let (httpResolution, httpsResolution, tunnelState) = await (
            httpResolutionTask,
            httpsResolutionTask,
            tunnelStateTask
        )
        guard !Task.isCancelled else {
            return cancellationResult(
                stage: "after-http-resolution",
                target: httpTarget,
                resolution: httpResolution
            )
        }
        async let httpResultTask = evaluate(
            target: httpTarget,
            resolution: httpResolution,
            timeout: timeout,
            tunnelState: tunnelState
        )
        async let httpsResultTask = evaluate(
            target: httpsTarget,
            resolution: httpsResolution,
            timeout: timeout,
            tunnelState: tunnelState
        )
        let (httpResult, httpsResult) = await (httpResultTask, httpsResultTask)
        guard !Task.isCancelled else {
            return cancellationResult(
                stage: "after-target-evaluation",
                evidence: httpResult.evidence + httpsResult.evidence
            )
        }

        return aggregate([httpResult, httpsResult])
    }

    func evaluate(
        target: URL,
        resolution: ProxyCandidateResolution,
        timeout: Duration,
        tunnelState: ProxyTunnelState? = nil
    ) async -> ProxyTargetRouteResult {
        let deadline = clock.now().advanced(by: timeout)
        let evidencePrefix = "proxy.\(target.scheme?.lowercased() ?? "unknown")"
        var evidence = resolution.evidenceCodes.map {
            NetworkDiagnosticEvidence(code: "\(evidencePrefix).resolution", value: $0)
        }
        var authenticationCandidate: (index: Int, proxy: EffectiveProxy)?
        var attemptedEndpoint = false

        guard !Task.isCancelled else {
            return cancelledRoute(
                target: target,
                evidencePrefix: evidencePrefix,
                evidence: evidence,
                stage: "before-candidates"
            )
        }
        guard !resolution.candidates.isEmpty else {
            if resolution.evidenceCodes.isEmpty {
                evidence.append(.init(code: "\(evidencePrefix).resolution", value: "resolution-empty"))
            }
            return ProxyTargetRouteResult(
                target: target,
                status: .indeterminate,
                selectedCandidateIndex: nil,
                selectedProxy: nil,
                evidence: evidence
            )
        }

        for (index, candidate) in resolution.candidates.enumerated() {
            guard !Task.isCancelled else {
                return cancelledRoute(
                    target: target,
                    evidencePrefix: evidencePrefix,
                    evidence: evidence,
                    stage: "candidate"
                )
            }
            let attemptStart = clock.now()
            let remaining = attemptStart.duration(to: deadline)
            guard remaining > .zero else {
                evidence.append(.init(code: "\(evidencePrefix).timeout", value: "expired"))
                break
            }

            let remainingCandidateCount = resolution.candidates.count - index
            let attemptTimeout = remaining / Double(remainingCandidateCount)
            let attemptDeadline = attemptStart.advanced(by: attemptTimeout)
            evidence.append(.init(code: "\(evidencePrefix).candidate-index", value: String(index)))
            let routeType = (candidate == .direct && tunnelState != nil) ? "tunnel" : candidate.routeType
            evidence.append(.init(code: "\(evidencePrefix).route-type", value: routeType))
            evidence.append(.init(code: "\(evidencePrefix).fallback-used", value: String(index > 0)))

            if candidate == .direct {
                if let tunnelState {
                    evidence.append(.init(code: "\(evidencePrefix).tunnel-interface", value: tunnelState.interface))
                    evidence.append(.init(
                        code: "\(evidencePrefix).tunnel-detection-source",
                        value: tunnelState.source.rawValue
                    ))
                }
                evidence.append(.init(code: "\(evidencePrefix).endpoint-status", value: "not-required"))
                evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "not-required"))
                evidence.append(.init(code: "\(evidencePrefix).egress-status", value: "base-check"))
                return ProxyTargetRouteResult(
                    target: target,
                    status: tunnelState == nil ? .direct : .tunnel,
                    selectedCandidateIndex: index,
                    selectedProxy: .direct,
                    evidence: evidence
                )
            }

            guard let endpoint = candidate.endpoint else {
                if case .unavailable(let reason) = candidate {
                    evidence.append(.init(code: "\(evidencePrefix).resolution", value: reason))
                }
                continue
            }

            attemptedEndpoint = true
            let endpointAvailable = await connector.canConnect(to: endpoint, timeout: attemptTimeout)
            guard !Task.isCancelled else {
                return cancelledRoute(
                    target: target,
                    evidencePrefix: evidencePrefix,
                    evidence: evidence,
                    stage: "endpoint"
                )
            }
            guard endpointAvailable else {
                evidence.append(.init(code: "\(evidencePrefix).endpoint-status", value: "unavailable"))
                evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "not-tested"))
                evidence.append(.init(code: "\(evidencePrefix).egress-status", value: "not-tested"))
                evidence.append(.init(code: "proxy.endpoint-unavailable", value: nil))
                continue
            }
            evidence.append(.init(code: "\(evidencePrefix).endpoint-status", value: "available"))

            let egressTimeout = clock.now().duration(to: attemptDeadline)
            guard egressTimeout > .zero else {
                evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "not-tested"))
                evidence.append(.init(code: "\(evidencePrefix).egress-status", value: "timed-out"))
                evidence.append(.init(code: "proxy.egress-unavailable", value: "timed-out"))
                continue
            }

            let response = await egressLoader.load(
                url: target,
                through: candidate,
                timeout: egressTimeout
            )
            guard !Task.isCancelled else {
                return cancelledRoute(
                    target: target,
                    evidencePrefix: evidencePrefix,
                    evidence: evidence,
                    stage: "egress"
                )
            }
            if response.statusCode == 407 {
                evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "required"))
                evidence.append(.init(code: "\(evidencePrefix).egress-status", value: "407"))
                evidence.append(.init(code: "proxy.authentication-required", value: "407"))
                if authenticationCandidate == nil {
                    authenticationCandidate = (index, candidate)
                }
                continue
            }

            guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else {
                let failure = response.errorCode ?? response.statusCode.map(String.init) ?? "unknown"
                evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "not-required"))
                evidence.append(.init(code: "\(evidencePrefix).egress-status", value: failure))
                evidence.append(.init(code: "proxy.egress-unavailable", value: failure))
                continue
            }

            evidence.append(.init(code: "\(evidencePrefix).authentication-status", value: "not-required"))
            evidence.append(.init(code: "\(evidencePrefix).egress-status", value: String(statusCode)))
            evidence.append(.init(code: "proxy.egress-available", value: String(statusCode)))
            return ProxyTargetRouteResult(
                target: target,
                status: .proxied,
                selectedCandidateIndex: index,
                selectedProxy: candidate,
                evidence: evidence
            )
        }

        if let authenticationCandidate {
            return ProxyTargetRouteResult(
                target: target,
                status: .authenticationRequired,
                selectedCandidateIndex: authenticationCandidate.index,
                selectedProxy: authenticationCandidate.proxy,
                evidence: evidence
            )
        }

        return ProxyTargetRouteResult(
            target: target,
            status: attemptedEndpoint ? .unavailable : .indeterminate,
            selectedCandidateIndex: nil,
            selectedProxy: nil,
            evidence: evidence
        )
    }

    private func cancelledRoute(
        target: URL,
        evidencePrefix: String,
        evidence: [NetworkDiagnosticEvidence],
        stage: String
    ) -> ProxyTargetRouteResult {
        ProxyTargetRouteResult(
            target: target,
            status: .indeterminate,
            selectedCandidateIndex: nil,
            selectedProxy: nil,
            evidence: evidence + [.init(code: "\(evidencePrefix).cancelled", value: stage)]
        )
    }

    private func cancellationResult(
        stage: String,
        target: URL? = nil,
        resolution: ProxyCandidateResolution? = nil,
        evidence: [NetworkDiagnosticEvidence] = []
    ) -> NetworkDiagnosticResult {
        let resolutionEvidence: [NetworkDiagnosticEvidence]
        if let target, let resolution {
            let prefix = "proxy.\(target.scheme?.lowercased() ?? "unknown").resolution"
            resolutionEvidence = resolution.evidenceCodes.map {
                .init(code: prefix, value: $0)
            }
        } else {
            resolutionEvidence = []
        }
        return result(
            .indeterminate,
            key: "network_diagnostics.proxy.unable_to_determine.summary",
            evidence: evidence
                + resolutionEvidence
                + [.init(code: "proxy.cancelled", value: stage)]
        )
    }

    private func aggregate(_ routes: [ProxyTargetRouteResult]) -> NetworkDiagnosticResult {
        let statuses = routes.map(\.status)
        let evidence = routes.flatMap(\.evidence)
        let proxyFacts = DiagnosticProxyFacts(
            http: routes.first(where: { $0.target.scheme?.lowercased() == "http" })?.diagnosticAvailability ?? .unverified,
            https: routes.first(where: { $0.target.scheme?.lowercased() == "https" })?.diagnosticAvailability ?? .unverified
        )

        if statuses.contains(.authenticationRequired) {
            return result(
                .abnormal,
                key: "network_diagnostics.proxy.authentication_required.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        if statuses.contains(.unavailable) {
            return result(
                .abnormal,
                key: "network_diagnostics.proxy.route_unavailable.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        if statuses.contains(.indeterminate) {
            return result(
                .indeterminate,
                key: "network_diagnostics.proxy.unable_to_determine.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        if statuses.allSatisfy({ $0 == .tunnel || $0 == .direct }),
           statuses.contains(.tunnel) {
            let nwPathConfirmed = evidence.contains { evidence in
                evidence.code.hasSuffix(".tunnel-detection-source")
                    && evidence.value == ProxyTunnelDetectionSource.nwpath.rawValue
            }
            return result(
                .normal,
                key: nwPathConfirmed
                    ? "network_diagnostics.proxy.tunnel_routes.summary"
                    : "network_diagnostics.proxy.tunnel_routes_active.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        if statuses.allSatisfy({ $0 == .direct }) {
            return result(
                .indeterminate,
                key: "network_diagnostics.proxy.direct_routes.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        if statuses.allSatisfy({ $0 == .proxied }) {
            return result(
                .normal,
                key: "network_diagnostics.proxy.routes_available.summary",
                evidence: evidence,
                proxyFacts: proxyFacts
            )
        }
        return result(
            .indeterminate,
            key: "network_diagnostics.proxy.mixed_routing.summary",
            evidence: evidence,
            proxyFacts: proxyFacts
        )
    }

    private func result(
        _ status: NetworkDiagnosticStatus,
        key: String.LocalizationValue,
        evidence: [NetworkDiagnosticEvidence] = [],
        proxyFacts: DiagnosticProxyFacts? = nil
    ) -> NetworkDiagnosticResult {
        NetworkDiagnosticResult(
            id: id,
            status: status,
            summary: String(localized: key, comment: "Network self-check system proxy result summary"),
            evidence: evidence,
            proxyFacts: proxyFacts
        )
    }
}

private extension EffectiveProxy {
    var routeType: String {
        switch self {
        case .direct:
            "direct"
        case .http:
            "http"
        case .https:
            "https"
        case .socks:
            "socks"
        case .unavailable:
            "unavailable"
        }
    }

    var endpoint: ProxyEndpoint? {
        switch self {
        case .http(let endpoint), .https(let endpoint), .socks(let endpoint):
            endpoint
        case .direct, .unavailable:
            nil
        }
    }
}

private final class ProxyEgressRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private extension Duration {
    var proxyCheckTimeInterval: TimeInterval {
        let components = self.components
        return max(
            0.001,
            Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}
