import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFi_Lens

@Suite("Network diagnostics")
struct NetworkDiagnosticsTests {

    func makeResults(
        path: NetworkDiagnosticStatus,
        gateway: NetworkDiagnosticStatus = .normal,
        dns: NetworkDiagnosticStatus,
        internet: NetworkDiagnosticStatus,
        ipv6: NetworkDiagnosticStatus = .skipped,
        proxy: NetworkDiagnosticStatus
    ) -> [NetworkDiagnosticResult] {
        [
            NetworkDiagnosticResult(id: .path, status: path, summary: "path"),
            NetworkDiagnosticResult(id: .gatewayReachability, status: gateway, summary: "gateway"),
            NetworkDiagnosticResult(id: .dns, status: dns, summary: "dns"),
            NetworkDiagnosticResult(id: .internet, status: internet, summary: "internet"),
            NetworkDiagnosticResult(id: .ipv6, status: ipv6, summary: "ipv6"),
            NetworkDiagnosticResult(id: .proxy, status: proxy, summary: "proxy"),
        ]
    }

    func makeFingerprint(
        interfaceName: String,
        dnsHash: UInt64
    ) -> NetworkFingerprint {
        NetworkFingerprint(
            interfaceType: "wifi",
            interfaceName: interfaceName,
            pathStatus: .satisfied,
            dnsSettingsHash: dnsHash,
            staticProxySettingsHash: 7
        )
    }

    func makeStubChecks(recorder: DiagnosticTestRecorder) -> [any DiagnosticCheck] {
        [.path, .dns, .proxy].map { id in
            StubDiagnosticCheck(
                id: id,
                result: NetworkDiagnosticResult(id: id, status: .normal, summary: id.rawValue),
                recorder: recorder
            )
        }
    }
}

struct AppLocalNetworkUsageDescription {
    let target: String
    let configuration: String
    let baseConfiguration: String
    let value: String
}

func appLocalNetworkUsageDescriptions() throws -> [AppLocalNetworkUsageDescription] {
    let projectURL = try privacyCopyProjectURL()
    let project = try String(contentsOf: projectURL, encoding: .utf8)
    return try appLocalNetworkUsageDescriptions(from: project)
}

func appLocalNetworkUsageDescriptions(
    from project: String
) throws -> [AppLocalNetworkUsageDescription] {
    let settingPrefix = "INFOPLIST_KEY_NSLocalNetworkUsageDescription = \""
    let selectedTargets = ["WiFiLens", "WiFiLensPro"]

    return try selectedTargets.flatMap { targetName in
        let target = try nativeTarget(named: targetName, in: project)
        guard target.contains("productType = \"com.apple.product-type.application\";") else {
            throw projectConfigurationError("\(targetName) is not an application target.")
        }
        let configurationListID = try pbxIdentifier(
            after: "buildConfigurationList = ",
            in: target,
            context: "\(targetName) target"
        )
        let configurationList = try pbxObject(
            id: configurationListID,
            in: project,
            context: "\(targetName) configuration list"
        )
        guard configurationList.contains("isa = XCConfigurationList;") else {
            throw projectConfigurationError("\(configurationListID) is not an XCConfigurationList.")
        }

        let configurationIDs = try buildConfigurationIDs(in: configurationList)
        let configurations = try configurationIDs.map { configurationID in
            let configuration = try pbxObject(
                id: configurationID,
                in: project,
                context: "\(targetName) build configuration"
            )
            guard configuration.contains("isa = XCBuildConfiguration;") else {
                throw projectConfigurationError("\(configurationID) is not an XCBuildConfiguration.")
            }
            let name = try pbxValue(
                after: "name = ",
                in: configuration,
                context: "\(configurationID) name"
            )
            let baseConfiguration = try requiredMatch(
                ["OSS.xcconfig", "PRO.xcconfig"],
                in: configuration,
                context: "\(configurationID) base configuration"
            )
            let settingRange = try requiredRange(
                of: settingPrefix,
                in: configuration,
                context: "\(configurationID) local-network privacy copy"
            )
            let valueStart = settingRange.upperBound
            let valueEnd = try requiredIndex(
                of: "\"",
                in: configuration[valueStart...],
                context: "\(configurationID) local-network privacy copy closing quote"
            )
            return AppLocalNetworkUsageDescription(
                target: targetName,
                configuration: name,
                baseConfiguration: baseConfiguration,
                value: String(configuration[valueStart..<valueEnd])
            )
        }

        guard configurations.count == 2,
              Set(configurations.map(\.configuration)) == ["Debug", "Release"] else {
            throw projectConfigurationError("\(targetName) must provide exactly Debug and Release configurations.")
        }
        return configurations
    }
}

func nativeTarget(named name: String, in project: String) throws -> String {
    let marker = " /* \(name) */ = {\n\t\t\tisa = PBXNativeTarget;"
    let markerRange = try requiredRange(of: marker, in: project, context: "\(name) PBXNativeTarget")
    let lineStart = project[..<markerRange.lowerBound].lastIndex(of: "\n")
        .map { project.index(after: $0) }
        ?? project.startIndex
    let identifier = String(project[lineStart..<markerRange.lowerBound])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return try pbxObject(id: identifier, in: project, context: "\(name) PBXNativeTarget")
}

func pbxObject(id: String, in project: String, context: String) throws -> String {
    let header = "\t\t\(id) "
    let start: String.Index
    if project.hasPrefix(header) {
        start = project.startIndex
    } else {
        let headerRange = try requiredRange(of: "\n\(header)", in: project, context: context)
        start = project.index(after: headerRange.lowerBound)
    }
    let suffix = String(project[start...])
    let end = try requiredRange(
        of: "\n\t\t};",
        in: suffix,
        context: "\(context) closing brace"
    ).upperBound
    return String(suffix[..<end])
}

func buildConfigurationIDs(in configurationList: String) throws -> [String] {
    let start = try requiredRange(
        of: "buildConfigurations = (",
        in: configurationList,
        context: "XCConfigurationList build configurations"
    ).upperBound
    let suffix = String(configurationList[start...])
    let end = try requiredRange(
        of: "\n\t\t\t);",
        in: suffix,
        context: "XCConfigurationList build configurations closing parenthesis"
    ).lowerBound
    return suffix[..<end]
        .split(separator: "\n")
        .compactMap { line in
            line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
        }
}

func pbxIdentifier(after prefix: String, in object: String, context: String) throws -> String {
    let value = try pbxValue(after: prefix, in: object, context: context)
    guard !value.isEmpty else {
        throw projectConfigurationError("\(context) must name a PBX object identifier.")
    }
    return value
}

func pbxValue(after prefix: String, in object: String, context: String) throws -> String {
    let valueStart = try requiredRange(of: prefix, in: object, context: context).upperBound
    let valueEnd = try requiredIndex(of: ";", in: object[valueStart...], context: "\(context) terminator")
    let value = object[valueStart..<valueEnd].trimmingCharacters(in: .whitespaces)
    return value.split(separator: " ").first.map(String.init) ?? ""
}

func requiredMatch(_ candidates: [String], in value: String, context: String) throws -> String {
    guard let match = candidates.first(where: value.contains) else {
        throw projectConfigurationError("\(context) must reference OSS.xcconfig or PRO.xcconfig.")
    }
    return match
}

func requiredRange(of needle: String, in value: String, context: String) throws -> Range<String.Index> {
    guard let range = value.range(of: needle) else {
        throw projectConfigurationError("Missing \(context).")
    }
    return range
}

func requiredIndex(
    of character: Character,
    in value: Substring,
    context: String
) throws -> String.Index {
    guard let index = value.firstIndex(of: character) else {
        throw projectConfigurationError("Missing \(context).")
    }
    return index
}

func projectConfigurationError(_ description: String) -> NSError {
    NSError(
        domain: "NetworkDiagnosticsTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: description]
    )
}

func privacyCopyProjectURL() throws -> URL {
    var directory = URL(filePath: #filePath).deletingLastPathComponent()
    let marker = "WiFiLens/WiFiLens.xcodeproj/project.pbxproj"

    while directory.path != directory.deletingLastPathComponent().path {
        let candidate = directory.appending(path: marker)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }

    throw NSError(
        domain: "NetworkDiagnosticsTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not locate \(marker) while searching ancestors of \(#filePath)."]
    )
}

struct StubPathSource: NetworkPathChecking {
    let state: NetworkPathState?

    init(_ state: NetworkPathState?) {
        self.state = state
    }

    func currentState(timeout: Duration) async -> NetworkPathState? {
        state
    }
}

actor ConcurrentDNSResolver: DNSResolving {
    private(set) var maximumInFlight = 0
    var inFlight = 0

    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome {
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        return .resolved
    }
}

actor ConcurrentControlLoader: ControlEndpointLoading {
    private(set) var maximumInFlight = 0
    var inFlight = 0

    func load(url: URL, timeout: Duration) async -> ControlEndpointLoadResult {
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        if url.host == "captive.apple.com" {
            return .init(status: 200, body: "Success", errorCode: nil)
        }
        return .init(status: 200, body: nil, errorCode: nil)
    }
}

struct MetricsControlLoader: ControlEndpointLoading {
    let metrics: ControlEndpointMetrics

    func load(url: URL, timeout: Duration) async -> ControlEndpointLoadResult {
        if url.host == "captive.apple.com" {
            return .init(status: 200, body: "Success", errorCode: nil)
        }
        return .init(status: 200, body: nil, errorCode: nil, metrics: metrics)
    }
}

actor BudgetAwareDiagnosticProbe {
    var didStart = false
    var invocationContinuation: CheckedContinuation<Void, Never>?
    private(set) var wasCancelled = false

    func run() async {
        didStart = true
        invocationContinuation?.resume()
        invocationContinuation = nil
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            wasCancelled = true
        }
    }

    func waitForInvocation() async {
        if didStart {
            return
        }
        await withCheckedContinuation { continuation in
            if didStart {
                continuation.resume()
            } else {
                invocationContinuation = continuation
            }
        }
    }
}

actor ManualDiagnosticClock: DiagnosticClock {
    let origin: ContinuousClock.Instant
    var current: ContinuousClock.Instant
    var sleepers: [UUID: (deadline: ContinuousClock.Instant, continuation: CheckedContinuation<Void, Never>)] = [:]

    init(origin: ContinuousClock.Instant = ContinuousClock.now) {
        self.origin = origin
        current = origin
    }

    func now() async -> ContinuousClock.Instant {
        current
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        try Task.checkCancellation()
        guard current < deadline else { return }
        let sleeperID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if current >= deadline || Task.isCancelled {
                    continuation.resume()
                } else {
                    sleepers[sleeperID] = (deadline, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelSleep(id: sleeperID) }
        }
        try Task.checkCancellation()
    }

    func set(_ value: ContinuousClock.Instant) {
        current = value
        let readyIDs = sleepers.compactMap { id, sleeper in
            sleeper.deadline <= value ? id : nil
        }
        let readySleepers = readyIDs.compactMap { sleepers.removeValue(forKey: $0) }
        for sleeper in readySleepers {
            sleeper.continuation.resume()
        }
    }

    func waitForSleeperCount(_ count: Int) async {
        while sleepers.count < count {
            await Task.yield()
        }
    }

    func cancelSleep(id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        sleeper.continuation.resume()
    }
}

actor OptionalBoolRecorder {
    private(set) var value: Bool?

    func record(_ value: Bool) {
        self.value = value
    }
}

struct BudgetAwareDiagnosticCheck: DiagnosticCheck {
    let id: NetworkDiagnosticCheckID = .path
    let probe: BudgetAwareDiagnosticProbe

    func run() async throws -> NetworkDiagnosticResult {
        try await probe.run()
        return .init(id: id, status: .normal, summary: id.rawValue)
    }
}

actor StubDNSResolver: DNSResolving {
    var outcomes: [DNSResolutionOutcome]
    var outcomeIndex = 0
    private(set) var invocationCount = 0

    init(_ outcome: DNSResolutionOutcome) {
        outcomes = [outcome]
    }

    init(outcomes: [DNSResolutionOutcome]) {
        precondition(!outcomes.isEmpty)
        self.outcomes = outcomes
    }

    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome {
        invocationCount += 1
        defer { outcomeIndex += 1 }
        return outcomes[min(outcomeIndex, outcomes.endIndex - 1)]
    }
}

struct MappingDNSResolver: DNSResolving {
    let outcomes: [String: DNSResolutionOutcome]

    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome {
        outcomes[host] ?? .indeterminate
    }
}

actor CancellationAwareDNSResolver: DNSResolving {
    var invocationWaiter: CheckedContinuation<Void, Never>?
    private(set) var invocationCount = 0

    func resolve(host: String, timeout: Duration) async -> DNSResolutionOutcome {
        invocationCount += 1
        invocationWaiter?.resume()
        invocationWaiter = nil
        try? await Task.sleep(for: timeout)
        return .indeterminate
    }

    func waitForInvocation() async {
        guard invocationCount == 0 else { return }
        await withCheckedContinuation { invocationWaiter = $0 }
    }
}

struct StubControlLoader: ControlEndpointLoading {
    let httpsStatus: Int?
    let httpsErrorCode: String?
    let httpStatus: Int?
    let httpBody: String?
    let httpErrorCode: String?
    let recorder: ControlEndpointTestRecorder?

    init(
        httpsStatus: Int?,
        httpsErrorCode: String? = nil,
        httpStatus: Int?,
        httpBody: String?,
        httpErrorCode: String? = nil,
        recorder: ControlEndpointTestRecorder? = nil
    ) {
        self.httpsStatus = httpsStatus
        self.httpsErrorCode = httpsErrorCode
        self.httpStatus = httpStatus
        self.httpBody = httpBody
        self.httpErrorCode = httpErrorCode
        self.recorder = recorder
    }

    func load(url: URL, timeout: Duration) async -> ControlEndpointLoadResult {
        await recorder?.record(url: url, timeout: timeout)
        if url.host == "captive.apple.com" {
            return .init(status: httpStatus, body: httpBody, errorCode: httpErrorCode)
        }
        return .init(status: httpsStatus, body: nil, errorCode: httpsErrorCode)
    }
}

struct StubIPv6Loader: IPv6ControlEndpointLoading {
    let outcome: IPv6ControlEndpointLoadOutcome

    init(_ outcome: IPv6ControlEndpointLoadOutcome) {
        self.outcome = outcome
    }

    func load(url: URL, timeout: Duration) async -> IPv6ControlEndpointLoadOutcome {
        outcome
    }
}

struct StubIPv6RouteSource: DiagnosticIPv6RouteSourcing {
    let route: DiagnosticIPv6RouteTarget?

    init(_ route: DiagnosticIPv6RouteTarget?) {
        self.route = route
    }

    func currentIPv6Route(timeout: Duration) async -> DiagnosticIPv6RouteTarget? {
        route
    }
}

struct StubGlobalIPv6AddressSource: GlobalIPv6AddressSourcing {
    let hasAddress: Bool

    func hasGlobalIPv6Address() -> Bool {
        hasAddress
    }
}

struct StubIPv6AddressResolver: IPv6AddressResolving {
    let outcome: IPv6AddressResolutionOutcome

    init(addresses: [String]) {
        outcome = addresses.isEmpty ? .noAAAA : .addresses(addresses)
    }

    init(outcome: IPv6AddressResolutionOutcome) {
        self.outcome = outcome
    }

    func resolveAAAA(host: String, timeout: Duration) async -> IPv6AddressResolutionOutcome {
        outcome
    }
}

actor RecordingIPv6AddressResolver: IPv6AddressResolving {
    let addresses: [String]
    private(set) var hosts: [String] = []

    init(addresses: [String]) {
        self.addresses = addresses
    }

    func resolveAAAA(host: String, timeout: Duration) async -> IPv6AddressResolutionOutcome {
        hosts.append(host)
        return addresses.isEmpty ? .noAAAA : .addresses(addresses)
    }
}

struct IPv6LoaderTestRequest: Equatable, Sendable {
    let url: URL
    let ipv6Address: String
    let serverName: String
    let timeout: Duration
}

actor IPv6LoaderTestRecorder {
    private(set) var requests: [IPv6LoaderTestRequest] = []

    func record(_ request: IPv6LoaderTestRequest) {
        requests.append(request)
    }
}

struct RecordingIPv6HTTPSConnector: IPv6HTTPSConnecting {
    let succeeds: Bool
    let recorder: IPv6LoaderTestRecorder

    func load(
        url: URL,
        ipv6Address: String,
        serverName: String,
        timeout: Duration
    ) async -> IPv6HTTPSConnectionOutcome {
        await recorder.record(.init(
            url: url,
            ipv6Address: ipv6Address,
            serverName: serverName,
            timeout: timeout
        ))
        return succeeds ? .succeeded : .failed
    }
}

struct StubIPv6HTTPSConnector: IPv6HTTPSConnecting {
    let succeeds: Bool

    func load(
        url: URL,
        ipv6Address: String,
        serverName: String,
        timeout: Duration
    ) async -> IPv6HTTPSConnectionOutcome {
        succeeds ? .succeeded : .failed
    }
}

actor SequencedIPv6HTTPSConnector: IPv6HTTPSConnecting {
    let successfulAddress: String
    private(set) var addresses: [String] = []
    private(set) var timeouts: [Duration] = []

    init(successfulAddress: String) {
        self.successfulAddress = successfulAddress
    }

    func load(
        url: URL,
        ipv6Address: String,
        serverName: String,
        timeout: Duration
    ) async -> IPv6HTTPSConnectionOutcome {
        addresses.append(ipv6Address)
        timeouts.append(timeout)
        return ipv6Address == successfulAddress ? .succeeded : .failed
    }
}

actor ControlEndpointTestRecorder {
    private(set) var urls: [String] = []
    private(set) var timeouts: [Duration] = []

    func record(url: URL, timeout: Duration) {
        urls.append(url.absoluteString)
        timeouts.append(timeout)
    }
}

struct StubProxyConfigurationResolver: ProxyConfigurationResolving {
    let storedResolutions: [ProxyResolutionDirective]

    init(_ resolution: ProxyResolutionDirective) {
        storedResolutions = [resolution]
    }

    init(_ resolutions: [ProxyResolutionDirective]) {
        storedResolutions = resolutions
    }

    func resolutions(for url: URL) -> [ProxyResolutionDirective] {
        storedResolutions
    }
}

struct PACResolutionTestRequest: Equatable, Sendable {
    let pacURL: URL
    let targetURL: URL
    let timeout: Duration
}

actor PACResolutionTestRecorder {
    private(set) var requests: [PACResolutionTestRequest] = []

    func record(pacURL: URL, targetURL: URL, timeout: Duration) {
        requests.append(.init(pacURL: pacURL, targetURL: targetURL, timeout: timeout))
    }
}

struct PACCallbackTestRequest: Equatable, Sendable {
    let source: PACSource
    let targetURL: URL
}

final class ControlledPACCallbackExecution: PACCallbackExecution, @unchecked Sendable {
    let lock = NSLock()
    var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

final class ControlledPACCallbackExecutor: PACCallbackExecuting, @unchecked Sendable {
    let lock = NSLock()
    let requestStream: AsyncStream<PACCallbackTestRequest>
    let requestContinuation: AsyncStream<PACCallbackTestRequest>.Continuation
    var callback: (@Sendable (PACCallbackOutcome) -> Void)?
    var execution: ControlledPACCallbackExecution?

    init() {
        let pair = AsyncStream<PACCallbackTestRequest>.makeStream()
        requestStream = pair.stream
        requestContinuation = pair.continuation
    }

    var executionWasCancelled: Bool {
        lock.withLock { execution?.isCancelled == true }
    }

    func execute(
        source: PACSource,
        targetURL: URL,
        callback: @escaping @Sendable (PACCallbackOutcome) -> Void
    ) -> any PACCallbackExecution {
        let execution = ControlledPACCallbackExecution()
        lock.withLock {
            self.callback = callback
            self.execution = execution
        }
        requestContinuation.yield(.init(source: source, targetURL: targetURL))
        return execution
    }

    func nextRequest() async -> PACCallbackTestRequest? {
        for await request in requestStream {
            return request
        }
        return nil
    }

    func complete(_ outcome: PACCallbackOutcome) {
        let callback = lock.withLock {
            let callback = self.callback
            self.callback = nil
            return callback
        }
        callback?(outcome)
    }
}

struct StubPACResolver: PACResolving {
    let resolution: ProxyCandidateResolution
    let recorder: PACResolutionTestRecorder?

    init(_ resolution: EffectiveProxy, recorder: PACResolutionTestRecorder? = nil) {
        switch resolution {
        case .unavailable(let reason):
            self.resolution = ProxyCandidateResolution(candidates: [], evidenceCodes: [reason])
        default:
            self.resolution = ProxyCandidateResolution(candidates: [resolution], evidenceCodes: [])
        }
        self.recorder = recorder
    }

    init(_ resolution: ProxyCandidateResolution, recorder: PACResolutionTestRecorder? = nil) {
        self.resolution = resolution
        self.recorder = recorder
    }

    func resolve(
        pacURL: URL,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        await recorder?.record(pacURL: pacURL, targetURL: targetURL, timeout: timeout)
        return resolution
    }
}

actor CancellationIgnoringPACResolver: PACResolving {
    var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    var hasInvoked = false

    func resolve(
        pacURL: URL,
        targetURL: URL,
        timeout: Duration
    ) async -> ProxyCandidateResolution {
        hasInvoked = true
        invocationWaiters.forEach { $0.resume() }
        invocationWaiters = []
        try? await Task.sleep(for: .seconds(30))
        return ProxyCandidateResolution(candidates: [], evidenceCodes: ["pac-cancelled"])
    }

    func waitForInvocation() async {
        guard !hasInvoked else { return }
        await withCheckedContinuation { invocationWaiters.append($0) }
    }
}

struct StubProxyResolver: ProxyResolving {
    let resolution: ProxyCandidateResolution

    init(_ resolution: EffectiveProxy) {
        switch resolution {
        case .unavailable(let reason):
            self.resolution = ProxyCandidateResolution(candidates: [], evidenceCodes: [reason])
        default:
            self.resolution = ProxyCandidateResolution(candidates: [resolution], evidenceCodes: [])
        }
    }

    init(_ resolution: ProxyCandidateResolution) {
        self.resolution = resolution
    }

    func resolve(for url: URL) async -> ProxyCandidateResolution {
        resolution
    }
}

struct StubProxyTunnelStateReader: ProxyTunnelStateReading {
    let state: ProxyTunnelState?

    init(
        interface: String?,
        source: ProxyTunnelDetectionSource = .nwpath
    ) {
        self.state = interface.map {
            ProxyTunnelState(interface: $0, source: source)
        }
    }

    func tunnelState() async -> ProxyTunnelState? {
        state
    }
}

final class TunnelTimeoutCancellationProbe: @unchecked Sendable {
    let lock = NSLock()
    var parkedContinuation: CheckedContinuation<Void, Never>?
    var cancelled = false

    var didCancel: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func park() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume()
                } else {
                    parkedContinuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            lock.lock()
            cancelled = true
            parkedContinuation?.resume()
            parkedContinuation = nil
            lock.unlock()
        }
    }
}

final class LockedFlag: @unchecked Sendable {
    let lock = NSLock()
    var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

actor ProxyResolutionTestRecorder {
    private(set) var urls: [String] = []

    func record(_ url: URL) {
        urls.append(url.absoluteString)
    }
}

struct RecordingProxyResolver: ProxyResolving {
    let resolutions: [URL: ProxyCandidateResolution]
    let defaultResolution: ProxyCandidateResolution?
    let recorder: ProxyResolutionTestRecorder?

    init(
        resolutions: [URL: ProxyCandidateResolution],
        recorder: ProxyResolutionTestRecorder? = nil
    ) {
        self.resolutions = resolutions
        defaultResolution = nil
        self.recorder = recorder
    }

    init(
        defaultResolution: ProxyCandidateResolution,
        recorder: ProxyResolutionTestRecorder? = nil
    ) {
        resolutions = [:]
        self.defaultResolution = defaultResolution
        self.recorder = recorder
    }

    func resolve(for url: URL) async -> ProxyCandidateResolution {
        await recorder?.record(url)
        return resolutions[url]
            ?? defaultResolution
            ?? ProxyCandidateResolution(candidates: [], evidenceCodes: ["fixture-missing"])
    }
}

actor CancellationIgnoringProxyResolver: ProxyResolving {
    private(set) var urls: [String] = []
    var invocationWaiters: [CheckedContinuation<Void, Never>] = []

    func resolve(for url: URL) async -> ProxyCandidateResolution {
        urls.append(url.absoluteString)
        if urls.count == 1 {
            invocationWaiters.forEach { $0.resume() }
            invocationWaiters = []
            try? await Task.sleep(for: .seconds(30))
        }
        return ProxyCandidateResolution(candidates: [.direct], evidenceCodes: [])
    }

    func waitForInvocation() async {
        guard urls.isEmpty else { return }
        await withCheckedContinuation { invocationWaiters.append($0) }
    }
}

func proxyDictionary(
    type: CFString,
    host: String? = nil,
    port: Int? = nil
) -> NSDictionary {
    let dictionary = NSMutableDictionary()
    dictionary[kCFProxyTypeKey] = type
    if let host { dictionary[kCFProxyHostNameKey] = host }
    if let port { dictionary[kCFProxyPortNumberKey] = NSNumber(value: port) }
    return dictionary
}

struct ProxyEgressTestRequest: Equatable, Sendable {
    let url: URL
    let proxy: EffectiveProxy
}

actor ProxyEgressTestRecorder {
    private(set) var requests: [ProxyEgressTestRequest] = []

    func record(url: URL, proxy: EffectiveProxy) {
        requests.append(.init(url: url, proxy: proxy))
    }
}

struct StubProxyEgressLoader: ProxyEgressLoading {
    let statusCode: Int?
    let errorCode: String?
    let recorder: ProxyEgressTestRecorder?

    init(
        statusCode: Int?,
        errorCode: String? = nil,
        recorder: ProxyEgressTestRecorder? = nil
    ) {
        self.statusCode = statusCode
        self.errorCode = errorCode
        self.recorder = recorder
    }

    func load(
        url: URL,
        through proxy: EffectiveProxy,
        timeout: Duration
    ) async -> ProxyEgressResponse {
        await recorder?.record(url: url, proxy: proxy)
        return ProxyEgressResponse(statusCode: statusCode, errorCode: errorCode)
    }
}

actor SequencedProxyEgressLoader: ProxyEgressLoading {
    let responses: [ProxyEgressResponse]
    let delays: [Duration]
    private(set) var timeouts: [Duration] = []
    var invocationCount = 0

    init(responses: [ProxyEgressResponse], delays: [Duration]) {
        self.responses = responses
        self.delays = delays
    }

    func load(
        url: URL,
        through proxy: EffectiveProxy,
        timeout: Duration
    ) async -> ProxyEgressResponse {
        let index = invocationCount
        invocationCount += 1
        timeouts.append(timeout)
        if delays.indices.contains(index) {
            try? await Task.sleep(for: delays[index])
        }
        guard responses.indices.contains(index) else {
            return ProxyEgressResponse(statusCode: nil, errorCode: "fixture-exhausted")
        }
        return responses[index]
    }
}

final class SequencedProxyCheckClock: ProxyCheckClock, @unchecked Sendable {
    let lock = NSLock()
    let instants: [ContinuousClock.Instant]
    var index = 0

    init(offsets: [Duration]) {
        let origin = ContinuousClock().now
        instants = offsets.map { origin.advanced(by: $0) }
    }

    func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        precondition(index < instants.count, "Proxy test clock exhausted")
        defer { index += 1 }
        return instants[index]
    }
}

actor CancellationIgnoringProxyEgressLoader: ProxyEgressLoading {
    var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var invocationCount = 0

    func load(
        url: URL,
        through proxy: EffectiveProxy,
        timeout: Duration
    ) async -> ProxyEgressResponse {
        invocationCount += 1
        if invocationCount == 1 {
            invocationWaiters.forEach { $0.resume() }
            invocationWaiters = []
            try? await Task.sleep(for: .seconds(30))
        }
        return ProxyEgressResponse(statusCode: nil, errorCode: "cancelled-fixture")
    }

    func waitForInvocation() async {
        guard invocationCount == 0 else { return }
        await withCheckedContinuation { invocationWaiters.append($0) }
    }
}

struct StubProxyConnector: ProxyEndpointConnecting {
    let reachable: Bool

    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        reachable
    }
}

struct EndpointSelectiveProxyConnector: ProxyEndpointConnecting {
    let reachableHosts: Set<String>

    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        reachableHosts.contains(endpoint.host)
    }
}

actor ProxyConnectorTestRecorder {
    private(set) var endpoints: [ProxyEndpoint] = []

    func record(_ endpoint: ProxyEndpoint) {
        endpoints.append(endpoint)
    }
}

actor SequencedProxyConnector: ProxyEndpointConnecting {
    let outcomes: [Bool]
    private(set) var endpoints: [ProxyEndpoint] = []
    private(set) var timeouts: [Duration] = []
    var invocationCount = 0

    init(outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        let index = invocationCount
        invocationCount += 1
        endpoints.append(endpoint)
        timeouts.append(timeout)
        return outcomes.indices.contains(index) ? outcomes[index] : false
    }
}

actor CancellationIgnoringProxyConnector: ProxyEndpointConnecting {
    var invocationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var endpoints: [ProxyEndpoint] = []

    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        endpoints.append(endpoint)
        if endpoints.count == 1 {
            invocationWaiters.forEach { $0.resume() }
            invocationWaiters = []
            try? await Task.sleep(for: .seconds(30))
        }
        return false
    }

    func waitForInvocation() async {
        guard endpoints.isEmpty else { return }
        await withCheckedContinuation { invocationWaiters.append($0) }
    }
}

struct RecordingProxyConnector: ProxyEndpointConnecting {
    let reachable: Bool
    let recorder: ProxyConnectorTestRecorder

    func canConnect(to endpoint: ProxyEndpoint, timeout: Duration) async -> Bool {
        await recorder.record(endpoint)
        return reachable
    }
}

actor DiagnosticTestRecorder {
    private(set) var values: [NetworkDiagnosticCheckID] = []

    func record(_ value: NetworkDiagnosticCheckID) {
        values.append(value)
    }
}

/// Isolated guidance harness: in-memory store, fixed clock, collecting event
/// sink. Keeps diagnostics view-model tests hermetic (no real UserDefaults,
/// no Launch Services queries).
@MainActor
final class IsolatedGuidance {
    let store: InMemoryGuidanceStateStore
    let coordinator: GuidanceCoordinator
    let eventBox: DiagnosticGuidanceEventBox

    var events: [GuidanceEvent] { eventBox.events }

    init(completionCount: Int = 0) {
        let calendar = Self.makeCalendar()
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12))!
        let box = DiagnosticGuidanceEventBox()
        store = InMemoryGuidanceStateStore(initial: GuidanceState(
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: completionCount
        ))
        var configuration = GuidanceConfiguration()
        configuration.invitationEnabled = true
        coordinator = GuidanceCoordinator(
            configuration: configuration,
            stateStore: store,
            now: { now },
            calendar: calendar,
            appVersion: { "2.1.0" },
            isProAppInstalled: { false },
            eventSink: { event in
                box.events.append(event)
            }
        )
        eventBox = box
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}

@MainActor
final class DiagnosticGuidanceEventBox {
    var events: [GuidanceEvent] = []
}

struct StubDiagnosticCheck: DiagnosticCheck {
    let id: NetworkDiagnosticCheckID
    let result: NetworkDiagnosticResult
    let recorder: DiagnosticTestRecorder

    func run() async -> NetworkDiagnosticResult {
        await recorder.record(id)
        return result
    }
}

actor RestartableDiagnosticProbe {
    let blockFirstInvocation: Bool
    var firstInvocationContinuation: CheckedContinuation<Void, Never>?
    var invocationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var invocationCount = 0

    init(blockFirstInvocation: Bool = false) {
        self.blockFirstInvocation = blockFirstInvocation
    }

    func run() async {
        invocationCount += 1
        let completedCount = invocationCount
        let readyWaiters = invocationWaiters.filter { $0.count <= completedCount }
        invocationWaiters.removeAll { $0.count <= completedCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }

        guard blockFirstInvocation, completedCount == 1 else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                firstInvocationContinuation = continuation
            }
        } onCancel: {
            Task { await self.releaseFirstInvocation() }
        }
    }

    func waitForInvocationCount(_ expectedCount: Int) async {
        guard invocationCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            invocationWaiters.append((expectedCount, continuation))
        }
    }

    func releaseFirstInvocation() {
        firstInvocationContinuation?.resume()
        firstInvocationContinuation = nil
    }
}

struct ProbeDiagnosticCheck: DiagnosticCheck {
    let id: NetworkDiagnosticCheckID
    let result: NetworkDiagnosticResult
    let rerunPolicy: DiagnosticCheckRerunPolicy
    let probe: RestartableDiagnosticProbe

    func run() async -> NetworkDiagnosticResult {
        await probe.run()
        return result
    }
}

actor BlockingDiagnosticProbe {
    var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    var invocationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var invocationCount = 0

    func run() async {
        invocationCount += 1
        let invocation = invocationCount
        let readyWaiters = invocationWaiters.filter { $0.count <= invocation }
        invocationWaiters.removeAll { $0.count <= invocation }
        readyWaiters.forEach { $0.continuation.resume() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuations[invocation] = $0 }
        } onCancel: {
            Task { await self.release(invocation: invocation) }
        }
    }

    func waitForInvocationCount(_ expectedCount: Int) async {
        guard invocationCount < expectedCount else { return }
        await withCheckedContinuation {
            invocationWaiters.append((expectedCount, $0))
        }
    }

    func release(invocation: Int) {
        continuations.removeValue(forKey: invocation)?.resume()
    }
}

struct BlockingProbeDiagnosticCheck: DiagnosticCheck {
    let id: NetworkDiagnosticCheckID
    let probe: BlockingDiagnosticProbe

    func run() async -> NetworkDiagnosticResult {
        await probe.run()
        return .init(id: id, status: .normal, summary: id.rawValue)
    }
}

actor CancellationIgnoringDiagnosticProbe {
    var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    var invocationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var invocationCount = 0

    func run() async {
        invocationCount += 1
        let invocation = invocationCount
        let readyWaiters = invocationWaiters.filter { $0.count <= invocation }
        invocationWaiters.removeAll { $0.count <= invocation }
        readyWaiters.forEach { $0.continuation.resume() }

        await withCheckedContinuation { continuation in
            continuations[invocation] = continuation
        }
    }

    func waitForInvocationCount(_ expectedCount: Int) async {
        guard invocationCount < expectedCount else { return }
        await withCheckedContinuation {
            invocationWaiters.append((expectedCount, $0))
        }
    }

    func release(invocation: Int) {
        continuations.removeValue(forKey: invocation)?.resume()
    }
}

struct CancellationIgnoringProbeDiagnosticCheck: DiagnosticCheck {
    let id: NetworkDiagnosticCheckID = .path
    let probe: CancellationIgnoringDiagnosticProbe

    func run() async -> NetworkDiagnosticResult {
        await probe.run()
        return .init(id: id, status: .normal, summary: id.rawValue)
    }
}

actor ControlledNetworkFingerprintMonitor: NetworkFingerprintMonitoring {
    let initial: NetworkFingerprint
    var lastFingerprint: NetworkFingerprint
    var continuation: AsyncStream<NetworkFingerprint>.Continuation?
    var pending: [NetworkFingerprint] = []

    init(initial: NetworkFingerprint) {
        self.initial = initial
        self.lastFingerprint = initial
    }

    func observation() async -> NetworkFingerprintObservation? {
        let pair = AsyncStream<NetworkFingerprint>.makeStream()
        install(pair.continuation)
        return NetworkFingerprintObservation(baseline: initial, changes: pair.stream)
    }

    func send(_ fingerprint: NetworkFingerprint) {
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        guard let continuation else {
            pending.append(fingerprint)
            return
        }
        continuation.yield(fingerprint)
    }

    func install(_ continuation: AsyncStream<NetworkFingerprint>.Continuation) {
        self.continuation = continuation
        for fingerprint in pending {
            continuation.yield(fingerprint)
        }
        pending = []
    }
}

actor CancellationIgnoringNetworkFingerprintMonitor: NetworkFingerprintMonitoring {
    var continuation: CheckedContinuation<NetworkFingerprintObservation?, Never>?

    func observation() async -> NetworkFingerprintObservation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitForInvocation() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

struct SilentNetworkPathFingerprintSource: NetworkPathFingerprintSourcing {
    func pathFingerprintChanges() -> AsyncStream<NetworkPathFingerprint> {
        AsyncStream { $0.finish() }
    }
}

struct FiniteNetworkPathFingerprintSource: NetworkPathFingerprintSourcing {
    let values: [NetworkPathFingerprint]

    func pathFingerprintChanges() -> AsyncStream<NetworkPathFingerprint> {
        AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

final class BufferedGapNetworkPathFingerprintSource: NetworkPathFingerprintSourcing, @unchecked Sendable {
    let lock = NSLock()
    let values: [NetworkPathFingerprint]
    var requestCount = 0

    init(values: [NetworkPathFingerprint]) {
        self.values = values
    }

    var streamRequestCount: Int {
        lock.withLock { requestCount }
    }

    func pathFingerprintChanges() -> AsyncStream<NetworkPathFingerprint> {
        lock.withLock { requestCount += 1 }
        return AsyncStream { continuation in
            values.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

struct ImmediateNetworkFingerprintSettingsPoller: NetworkFingerprintSettingsPolling {
    func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.yield(())
            continuation.finish()
        }
    }
}

struct FixedCountNetworkFingerprintSettingsPoller: NetworkFingerprintSettingsPolling {
    let count: Int

    func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream { continuation in
            for _ in 0..<count {
                continuation.yield(())
            }
            continuation.finish()
        }
    }
}

struct SilentNetworkFingerprintSettingsPoller: NetworkFingerprintSettingsPolling {
    func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}

final class MutableFingerprintSettingsReader: NetworkFingerprintSettingsReading, @unchecked Sendable {
    let lock = NSLock()
    var dnsHash: UInt64
    let proxyHash: UInt64

    init(dnsHash: UInt64, proxyHash: UInt64) {
        self.dnsHash = dnsHash
        self.proxyHash = proxyHash
    }

    func dnsSettingsHash() -> UInt64 {
        lock.withLock { dnsHash }
    }

    func staticProxySettingsHash() -> UInt64 {
        proxyHash
    }

    func setDNSHash(_ value: UInt64) {
        lock.withLock { dnsHash = value }
    }
}

actor SequencedFingerprintRouteStateSource: NetworkFingerprintRouteStateSourcing {
    let values: [NetworkFingerprintRouteState]
    var index = 0

    init(values: [NetworkFingerprintRouteState]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func currentState() async -> NetworkFingerprintRouteState? {
        defer { index += 1 }
        return values[min(index, values.endIndex - 1)]
    }
}

final class SequencedFingerprintSettingsReader: NetworkFingerprintSettingsReading, @unchecked Sendable {
    let lock = NSLock()
    let dnsHashes: [UInt64]
    let proxyHash: UInt64
    var dnsIndex = 0

    init(dnsHashes: [UInt64], proxyHash: UInt64) {
        self.dnsHashes = dnsHashes
        self.proxyHash = proxyHash
    }

    func dnsSettingsHash() -> UInt64 {
        lock.withLock {
            guard !dnsHashes.isEmpty else { return 0 }
            let index = min(dnsIndex, dnsHashes.count - 1)
            dnsIndex += 1
            return dnsHashes[index]
        }
    }

    func staticProxySettingsHash() -> UInt64 {
        proxyHash
    }
}

struct StubNetworkInterfaceSource: NetworkInterfaceInfoSourcing {
    let interface: NetworkInterfaceInfo?

    func currentInterface() async -> NetworkInterfaceInfo? {
        interface
    }
}

actor RecordingGatewayPingProcessRunner: GatewayPingProcessRunning {
    let latency: Double?
    private(set) var executablePath: String?
    private(set) var arguments: [String] = []

    init(latency: Double?) {
        self.latency = latency
    }

    func run(executablePath: String, arguments: [String]) async -> Double? {
        self.executablePath = executablePath
        self.arguments = arguments
        return latency
    }

    func cancel() async {}
}

actor ControlledGatewayPingProcessRunner: GatewayPingProcessRunning {
    private var activeContinuations: [Int: CheckedContinuation<Double?, Never>] = [:]
    private var invocationWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var invocationCount = 0
    private(set) var cancelledInvocationIDs: [Int] = []

    func run(executablePath: String, arguments: [String]) async -> Double? {
        invocationCount += 1
        let invocationID = invocationCount
        resumeInvocationWaiters()
        return await withCheckedContinuation { continuation in
            activeContinuations[invocationID] = continuation
        }
    }

    func cancel() {
        guard let invocationID = activeContinuations.keys.max(),
              let continuation = activeContinuations.removeValue(forKey: invocationID) else {
            return
        }
        cancelledInvocationIDs.append(invocationID)
        continuation.resume(returning: nil)
    }

    func waitUntilInvocationCount(_ target: Int) async {
        if invocationCount >= target { return }
        await withCheckedContinuation { invocationWaiters.append((target, $0)) }
    }

    private func resumeInvocationWaiters() {
        let ready = invocationWaiters.filter { invocationCount >= $0.target }
        invocationWaiters.removeAll { invocationCount >= $0.target }
        ready.forEach { $0.continuation.resume() }
    }
}

actor RecordingDiagnosticGatewayMeasurer: DiagnosticGatewayMeasuring {
    private(set) var targets: [DiagnosticGatewayTarget] = []

    func measure(target: DiagnosticGatewayTarget) async -> GatewayLatencyResult {
        targets.append(target)
        return GatewayLatencyResult(
            timestamp: Date(),
            routerIP: target.address,
            latencyMs: 2.5
        )
    }
}

actor SequencedDiagnosticRouteSource: DiagnosticRouteSourcing {
    let values: [DiagnosticRouteSelection]
    var index = 0
    private(set) var invocationCount = 0

    init(values: [DiagnosticRouteSelection]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func currentRoute(timeout: Duration) async -> DiagnosticRouteSelection {
        invocationCount += 1
        defer { index += 1 }
        return values[min(index, values.endIndex - 1)]
    }
}

struct StubNetworkInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    let interfaces: [NetworkInterfaceInfo]

    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: Date(),
            interfaces: interfaces
        )
    }
}

struct StubGatewayLatencyProvider: GatewayLatencyProviding {
    let result: GatewayLatencyResult

    func measure(routerIP: String?) async -> GatewayLatencyResult {
        result
    }
}

func makeNetworkInterface(name: String = "en0", router: String?) -> NetworkInterfaceInfo {
    NetworkInterfaceInfo(
        interfaceName: name,
        hardwareMAC: "00:11:22:33:44:55",
        ipv4Addresses: ["192.0.2.10"],
        subnetMasks: ["255.255.255.0"],
        router: router,
        dnsServers: ["192.0.2.53"],
        ssid: "Test Network",
        bssid: nil,
        channel: nil,
        band: nil,
        rssi: nil,
        txRate: nil,
        phyMode: nil,
        security: "WPA2"
    )
}

func makeDiagnosticContext(
    pathState: NetworkPathState?,
    route: DiagnosticRouteSelection,
    interfaces: [NetworkInterfaceInfo] = []
) -> DiagnosticNetworkContext {
    DiagnosticNetworkContext(
        runID: UUID(),
        capturedAt: Date(),
        pathState: pathState,
        route: route,
        interfaces: NetworkInterfaceSnapshot(
            cycleID: UUID(),
            capturedAt: Date(),
            interfaces: interfaces
        )
    )
}
