import CFNetwork
import Foundation

enum EffectiveProxy: Equatable, Sendable {
    case direct
    case http(ProxyEndpoint)
    case https(ProxyEndpoint)
    case socks(ProxyEndpoint)
    case unavailable(String)
}

struct ProxyCandidateResolution: Equatable, Sendable {
    let candidates: [EffectiveProxy]
    let evidenceCodes: [String]
}

enum ProxyTargetRouteStatus: Equatable, Sendable {
    case direct
    case tunnel
    case proxied
    case authenticationRequired
    case unavailable
    case indeterminate
}

struct ProxyTargetRouteResult: Equatable, Sendable {
    let target: URL
    let status: ProxyTargetRouteStatus
    let selectedCandidateIndex: Int?
    let selectedProxy: EffectiveProxy?
    let evidence: [NetworkDiagnosticEvidence]

    var diagnosticAvailability: DiagnosticRouteAvailability {
        switch status {
        case .proxied:
            .available
        case .authenticationRequired:
            .authenticationRequired
        case .unavailable:
            .unavailable
        case .direct, .tunnel, .indeterminate:
            .unverified
        }
    }
}

protocol ProxyResolving: Sendable {
    func resolve(for url: URL) async -> ProxyCandidateResolution
}

enum ProxyResolutionDirective: Equatable, Sendable {
    case direct
    case http(ProxyEndpoint)
    case https(ProxyEndpoint)
    case socks(ProxyEndpoint)
    case pac(URL)
    case pacScript(String)
    case unavailable(String)

    var effectiveProxy: EffectiveProxy {
        switch self {
        case .direct:
            .direct
        case .http(let endpoint):
            .http(endpoint)
        case .https(let endpoint):
            .https(endpoint)
        case .socks(let endpoint):
            .socks(endpoint)
        case .pac, .pacScript:
            .unavailable("pac-execution-invalid")
        case .unavailable(let reason):
            .unavailable(reason)
        }
    }
}

protocol ProxyConfigurationResolving: Sendable {
    func resolutions(for url: URL) -> [ProxyResolutionDirective]
}

protocol PACResolving: Sendable {
    func resolve(
        pacURL: URL,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution

    func resolve(
        pacScript: String,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution
}

extension PACResolving {
    func resolve(
        pacScript: String,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        ProxyCandidateResolution(candidates: [], evidenceCodes: ["pac-script-unsupported"])
    }
}

enum PACSource: Equatable, Sendable {
    case url(URL)
    case script(String)
}

enum PACCallbackOutcome: Equatable, Sendable {
    case success(ProxyCandidateResolution)
    case failure
}

protocol PACCallbackExecution: Sendable {
    func cancel()
}

protocol PACCallbackExecuting: Sendable {
    func execute(
        source: PACSource,
        targetURL: URL,
        callback: @escaping @Sendable (PACCallbackOutcome) -> Void
    ) -> any PACCallbackExecution
}

struct SystemProxyResolver: ProxyResolving {
    private let pacTimeout: Duration
    private let configurationResolver: any ProxyConfigurationResolving
    private let pacResolver: any PACResolving

    init(
        pacTimeout: Duration = .seconds(5),
        configurationResolver: any ProxyConfigurationResolving = CFNetworkProxyConfigurationResolver(),
        pacResolver: any PACResolving = SystemPACResolver()
    ) {
        self.pacTimeout = pacTimeout
        self.configurationResolver = configurationResolver
        self.pacResolver = pacResolver
    }

    func resolve(for url: URL) async -> ProxyCandidateResolution {
        guard !Task.isCancelled else { return Self.cancelledResolution() }
        var candidates: [EffectiveProxy] = []
        var evidenceCodes: [String] = []
        let directives = configurationResolver.resolutions(for: url)
        guard !Task.isCancelled else { return Self.cancelledResolution() }

        for directive in directives {
            guard !Task.isCancelled else {
                return Self.cancelledResolution(preserving: evidenceCodes)
            }
            switch directive {
            case .direct, .http, .https, .socks:
                candidates.append(directive.effectiveProxy)
            case .pac(let pacURL):
                let pacResolution = await pacResolver.resolve(
                    pacURL: pacURL,
                    targetURL: url,
                    timeout: pacTimeout
                )
                evidenceCodes.append(contentsOf: pacResolution.evidenceCodes)
                guard !Task.isCancelled else {
                    return Self.cancelledResolution(preserving: evidenceCodes)
                }
                candidates.append(contentsOf: pacResolution.candidates)
            case .pacScript(let script):
                let pacResolution = await pacResolver.resolve(
                    pacScript: script,
                    targetURL: url,
                    timeout: pacTimeout
                )
                evidenceCodes.append(contentsOf: pacResolution.evidenceCodes)
                guard !Task.isCancelled else {
                    return Self.cancelledResolution(preserving: evidenceCodes)
                }
                candidates.append(contentsOf: pacResolution.candidates)
            case .unavailable(let reason):
                evidenceCodes.append(reason)
            }
        }

        guard !Task.isCancelled else {
            return Self.cancelledResolution(preserving: evidenceCodes)
        }
        if candidates.isEmpty, evidenceCodes.isEmpty {
            evidenceCodes.append("resolution-empty")
        }
        return ProxyCandidateResolution(candidates: candidates, evidenceCodes: evidenceCodes)
    }

    private static func cancelledResolution(
        preserving evidenceCodes: [String] = []
    ) -> ProxyCandidateResolution {
        var evidenceCodes = evidenceCodes
        if !evidenceCodes.contains("resolution-cancelled") {
            evidenceCodes.append("resolution-cancelled")
        }
        return ProxyCandidateResolution(candidates: [], evidenceCodes: evidenceCodes)
    }

    static func directives(from values: [Any]) -> [ProxyResolutionDirective] {
        values.map(directive(from:))
    }

    static func candidates(from values: [Any]) -> [EffectiveProxy] {
        directives(from: values).compactMap { directive in
            switch directive {
            case .direct, .http, .https, .socks:
                directive.effectiveProxy
            case .pac, .pacScript, .unavailable:
                nil
            }
        }
    }

    static func directive(from value: Any) -> ProxyResolutionDirective {
        guard
            let dictionary = value as? NSDictionary,
            let type = dictionary[kCFProxyTypeKey] as? NSString
        else {
            return .unavailable("resolution-invalid")
        }

        if type == kCFProxyTypeNone as NSString {
            return .direct
        }
        if type == kCFProxyTypeAutoConfigurationURL as NSString {
            guard let pacURL = dictionary[kCFProxyAutoConfigurationURLKey] as? URL else {
                return .unavailable("pac-url-unavailable")
            }
            return .pac(pacURL)
        }
        if type == kCFProxyTypeAutoConfigurationJavaScript as NSString {
            guard
                let script = dictionary[kCFProxyAutoConfigurationJavaScriptKey] as? String,
                !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return .unavailable("pac-script-unavailable")
            }
            return .pacScript(script)
        }
        if type == kCFProxyTypeHTTP as NSString {
            return endpoint(in: dictionary).map(ProxyResolutionDirective.http)
                ?? .unavailable("proxy-endpoint-invalid")
        }
        if type == kCFProxyTypeHTTPS as NSString {
            return endpoint(in: dictionary).map(ProxyResolutionDirective.https)
                ?? .unavailable("proxy-endpoint-invalid")
        }
        if type == kCFProxyTypeSOCKS as NSString {
            return endpoint(in: dictionary).map(ProxyResolutionDirective.socks)
                ?? .unavailable("proxy-endpoint-invalid")
        }
        return .unavailable("proxy-type-unsupported")
    }

    private static func endpoint(in dictionary: NSDictionary) -> ProxyEndpoint? {
        guard
            let host = dictionary[kCFProxyHostNameKey] as? String,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let portNumber = dictionary[kCFProxyPortNumberKey] as? NSNumber,
            (1...Int(UInt16.max)).contains(portNumber.intValue)
        else {
            return nil
        }
        return ProxyEndpoint(host: host, port: UInt16(portNumber.intValue))
    }
}

struct CFNetworkProxyConfigurationResolver: ProxyConfigurationResolving {
    func resolutions(for url: URL) -> [ProxyResolutionDirective] {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
            return [.unavailable("settings-unavailable")]
        }

        let proxyList = CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue()
        let values = (proxyList as NSArray).map { $0 }
        guard !values.isEmpty else {
            return [.unavailable("resolution-empty")]
        }

        return SystemProxyResolver.directives(from: values)
    }
}

struct SystemPACResolver: PACResolving {
    private let callbackExecutor: any PACCallbackExecuting

    init(callbackExecutor: any PACCallbackExecuting = SystemPACCallbackExecutor()) {
        self.callbackExecutor = callbackExecutor
    }

    func resolve(
        pacURL: URL,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        await resolve(source: .url(pacURL), targetURL: targetURL, timeout: timeout)
    }

    func resolve(
        pacScript: String,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        await resolve(source: .script(pacScript), targetURL: targetURL, timeout: timeout)
    }

    private func resolve(
        source: PACSource,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        let context = PACResolutionContext()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                context.start(
                    source: source,
                    targetURL: targetURL,
                    timeout: timeout,
                    callbackExecutor: callbackExecutor,
                    continuation: continuation
                )
            }
        } onCancel: {
            context.cancel()
        }
    }

    static func resolution(from values: [Any]) -> ProxyCandidateResolution {
        guard !values.isEmpty else {
            return ProxyCandidateResolution(
                candidates: [],
                evidenceCodes: ["pac-execution-failed"]
            )
        }

        var candidates: [EffectiveProxy] = []
        var evidenceCodes: [String] = []
        for directive in SystemProxyResolver.directives(from: values) {
            switch directive {
            case .direct, .http, .https, .socks:
                candidates.append(directive.effectiveProxy)
            case .pac, .pacScript:
                evidenceCodes.append("pac-execution-invalid")
            case .unavailable(let reason):
                evidenceCodes.append(reason)
            }
        }
        return ProxyCandidateResolution(candidates: candidates, evidenceCodes: evidenceCodes)
    }
}

private struct SystemPACCallbackExecutor: PACCallbackExecuting {
    func execute(
        source: PACSource,
        targetURL: URL,
        callback: @escaping @Sendable (PACCallbackOutcome) -> Void
    ) -> any PACCallbackExecution {
        let execution = SystemPACCallbackExecution(callback: callback)
        execution.start(source: source, targetURL: targetURL)
        return execution
    }
}

private final class SystemPACCallbackExecution: PACCallbackExecution, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (PACCallbackOutcome) -> Void)?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var cancellationRequested = false

    init(callback: @escaping @Sendable (PACCallbackOutcome) -> Void) {
        self.callback = callback
    }

    func start(source pacSource: PACSource, targetURL: URL) {
        var clientContext = CFStreamClientContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let source: CFRunLoopSource = switch pacSource {
        case .url(let pacURL):
            CFNetworkExecuteProxyAutoConfigurationURL(
                pacURL as CFURL,
                targetURL as CFURL,
                proxyAutoConfigurationCallback,
                &clientContext
            )
        case .script(let script):
            CFNetworkExecuteProxyAutoConfigurationScript(
                script as CFString,
                targetURL as CFURL,
                proxyAutoConfigurationCallback,
                &clientContext
            )
        }

        lock.lock()
        guard !cancellationRequested, callback != nil else {
            lock.unlock()
            CFRunLoopSourceInvalidate(source)
            return
        }
        self.source = source
        lock.unlock()

        DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.pac").async { [self] in
            run()
        }
    }

    func receive(proxyList: CFArray, error: CFError?) {
        let outcome: PACCallbackOutcome
        if error != nil {
            outcome = .failure
        } else {
            let values = (proxyList as NSArray).map { $0 }
            outcome = .success(SystemPACResolver.resolution(from: values))
        }

        lock.lock()
        guard !cancellationRequested, let callback else {
            lock.unlock()
            return
        }
        self.callback = nil
        lock.unlock()
        callback(outcome)
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        callback = nil
        let source = self.source
        self.source = nil
        let runLoop = self.runLoop
        self.runLoop = nil
        lock.unlock()

        if let source {
            CFRunLoopSourceInvalidate(source)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func run() {
        let runLoop = CFRunLoopGetCurrent()
        lock.lock()
        guard !cancellationRequested, let source else {
            lock.unlock()
            return
        }
        self.runLoop = runLoop
        lock.unlock()

        CFRunLoopAddSource(runLoop, source, .defaultMode)
        CFRunLoopRun()
    }
}

private final class PACResolutionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProxyCandidateResolution, Never>?
    private var execution: (any PACCallbackExecution)?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false

    func start(
        source: PACSource,
        targetURL: URL,
        timeout: Duration,
        callbackExecutor: any PACCallbackExecuting,
        continuation: CheckedContinuation<ProxyCandidateResolution, Never>
    ) {
        lock.lock()
        guard !cancellationRequested else {
            lock.unlock()
            continuation.resume(returning: ProxyCandidateResolution(
                candidates: [],
                evidenceCodes: ["pac-cancelled"]
            ))
            return
        }
        self.continuation = continuation
        lock.unlock()

        let execution = callbackExecutor.execute(
            source: source,
            targetURL: targetURL
        ) { [weak self] outcome in
            self?.receive(outcome)
        }
        install(execution)

        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            self?.finish(ProxyCandidateResolution(
                candidates: [],
                evidenceCodes: ["pac-timeout"]
            ))
        }
        install(timeoutTask)
    }

    func receive(_ outcome: PACCallbackOutcome) {
        switch outcome {
        case .success(let resolution):
            finish(resolution)
        case .failure:
            finish(ProxyCandidateResolution(
                candidates: [],
                evidenceCodes: ["pac-execution-failed"]
            ))
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let hasContinuation = continuation != nil
        lock.unlock()
        if hasContinuation {
            finish(ProxyCandidateResolution(
                candidates: [],
                evidenceCodes: ["pac-cancelled"]
            ))
        }
    }

    private func install(_ execution: any PACCallbackExecution) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            execution.cancel()
            return
        }
        self.execution = execution
        lock.unlock()
    }

    private func install(_ timeoutTask: Task<Void, Never>) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    private func finish(_ resolution: ProxyCandidateResolution) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let execution = self.execution
        self.execution = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        execution?.cancel()
        timeoutTask?.cancel()
        continuation.resume(returning: resolution)
    }
}

private func proxyAutoConfigurationCallback(
    client: UnsafeMutableRawPointer,
    proxyList: CFArray,
    error: CFError?
) {
    Unmanaged<SystemPACCallbackExecution>
        .fromOpaque(client)
        .takeUnretainedValue()
        .receive(proxyList: proxyList, error: error)
}
