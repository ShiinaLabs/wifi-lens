import Foundation
import dnssd

enum DNSResolutionOutcome: Equatable, Sendable {
    case resolved
    case failed
    case indeterminate
}

protocol DNSResolving: Sendable {
    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome
}

struct SystemDNSResolver: DNSResolving {
    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome {
        let context = DNSResolutionContext()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard context.install(continuation: continuation) else { return }
                var serviceRef: DNSServiceRef?
                let opaqueContext = Unmanaged.passUnretained(context).toOpaque()
                let error = DNSServiceGetAddrInfo(
                    &serviceRef,
                    0,
                    0,
                    0,
                    host,
                    { _, _, _, errorCode, _, address, _, opaqueContext in
                        guard let opaqueContext else { return }
                        let context = Unmanaged<DNSResolutionContext>
                            .fromOpaque(opaqueContext)
                            .takeUnretainedValue()
                        if errorCode == kDNSServiceErr_NoError, address != nil {
                            context.finish(.resolved)
                        } else {
                            context.finish(.failed)
                        }
                    },
                    opaqueContext
                )

                guard error == kDNSServiceErr_NoError, let serviceRef else {
                    context.finish(.failed)
                    return
                }

                DNSServiceSetDispatchQueue(
                    serviceRef,
                    DispatchQueue(label: "io.github.kaoru.wifi-lens.network-diagnostics.dns")
                )
                context.install(serviceRef: serviceRef)

                let timeoutTask = Task { [context] in
                    do {
                        try await Task.sleep(for: timeout)
                        context.finish(.indeterminate)
                    } catch {
                        // The DNS callback completed or the caller cancelled.
                    }
                }
                context.install(timeoutTask: timeoutTask)
            }
        } onCancel: {
            context.cancel()
        }
    }
}

private final class DNSResolutionContext: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DNSResolutionOutcome, Never>?
    private var serviceRef: DNSServiceRef?
    private var cancellationRequested = false
    private var didFinish = false
    private var timeoutTask: Task<Void, Never>?

    func install(continuation: CheckedContinuation<DNSResolutionOutcome, Never>) -> Bool {
        lock.lock()
        guard !cancellationRequested, !didFinish else {
            lock.unlock()
            continuation.resume(returning: .indeterminate)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(serviceRef: DNSServiceRef) {
        lock.lock()
        if didFinish || continuation == nil {
            lock.unlock()
            DNSServiceRefDeallocate(serviceRef)
            return
        }
        self.serviceRef = serviceRef
        lock.unlock()
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

    func finish(_ outcome: DNSResolutionOutcome) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let serviceRef = self.serviceRef
        self.serviceRef = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
        }
        timeoutTask?.cancel()
        continuation?.resume(returning: outcome)
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
        finish(.indeterminate)
    }
}

struct DNSResolutionCheck: DiagnosticCheck {
    // Authoritative third-party DNS probe targets (no self-hosted endpoints).
    private static let defaultProbeTargets = [
        "www.apple.com",
        "www.microsoft.com",
        "www.msftconnecttest.com",
    ]

    let id = NetworkDiagnosticCheckID.dns
    private let resolver: any DNSResolving
    let probeTargets: [String]
    private let timeout: Duration

    init(
        resolver: any DNSResolving = SystemDNSResolver(),
        probeTargets: [String] = Self.defaultProbeTargets,
        timeout: Duration = .seconds(5)
    ) {
        precondition(probeTargets.count == 3, "DNS self-check requires exactly three probe targets")
        self.resolver = resolver
        self.probeTargets = probeTargets
        self.timeout = timeout
    }

    func run() async -> NetworkDiagnosticResult {
        let outcomes = await withTaskGroup(of: (index: Int, outcome: DNSResolutionOutcome).self, returning: [DNSResolutionOutcome].self) { group in
            for (index, host) in probeTargets.enumerated() {
                group.addTask {
                    let firstOutcome = await resolver.resolve(host: host, timeout: timeout)
                    let outcome: DNSResolutionOutcome
                    if firstOutcome == .indeterminate, !Task.isCancelled {
                        outcome = await resolver.resolve(host: host, timeout: timeout)
                    } else {
                        outcome = firstOutcome
                    }
                    return (index, outcome)
                }
            }
            var outcomes = Array(
                repeating: DNSResolutionOutcome.indeterminate,
                count: probeTargets.count
            )
            for await sample in group {
                outcomes[sample.index] = sample.outcome
            }
            return outcomes
        }
        let successCount = outcomes.count { $0 == .resolved }
        let failureCount = outcomes.count { $0 == .failed }
        let indeterminateCount = outcomes.count { $0 == .indeterminate }
        let sampleEvidence = probeTargets.enumerated().map { index, host in
            NetworkDiagnosticEvidence(
                code: "dns.sample.\(Self.sampleID(for: host, index: index))",
                value: Self.evidenceValue(for: outcomes[index])
            )
        }
        let evidence = sampleEvidence + [
            NetworkDiagnosticEvidence(code: "dns.success-count", value: "\(successCount)/\(probeTargets.count)"),
            NetworkDiagnosticEvidence(code: "dns.failure-count", value: "\(failureCount)/\(probeTargets.count)"),
            NetworkDiagnosticEvidence(code: "dns.indeterminate-count", value: "\(indeterminateCount)/\(probeTargets.count)"),
        ]

        if successCount == probeTargets.count {
            return NetworkDiagnosticResult(
                id: id,
                status: .normal,
                summary: String(localized: "network_diagnostics.dns.available.summary", comment: "Network self-check DNS all test names resolved"),
                evidence: evidence
            )
        }
        if failureCount == probeTargets.count {
            return NetworkDiagnosticResult(
                id: id,
                status: .abnormal,
                summary: String(localized: "network_diagnostics.dns.unavailable.summary", comment: "Network self-check DNS all test names failed"),
                evidence: evidence
            )
        }
        if indeterminateCount == probeTargets.count {
            return NetworkDiagnosticResult(
                id: id,
                status: .indeterminate,
                summary: String(localized: "network_diagnostics.dns.unable_to_determine.summary", comment: "Network self-check DNS no test name produced a result"),
                evidence: evidence
            )
        }
        return NetworkDiagnosticResult(
            id: id,
            status: .indeterminate,
            summary: String(localized: "network_diagnostics.dns.inconsistent.summary", comment: "Network self-check DNS test names had mixed outcomes"),
            evidence: evidence
        )
    }

    private static func sampleID(for host: String, index: Int) -> String {
        switch host.lowercased() {
        case "www.apple.com": "apple"
        case "www.microsoft.com": "microsoft"
        case "www.msftconnecttest.com": "msft-connect-test"
        default: "sample-\(index + 1)"
        }
    }

    private static func evidenceValue(for outcome: DNSResolutionOutcome) -> String {
        switch outcome {
        case .resolved: "resolved"
        case .failed: "failed"
        case .indeterminate: "indeterminate"
        }
    }
}
