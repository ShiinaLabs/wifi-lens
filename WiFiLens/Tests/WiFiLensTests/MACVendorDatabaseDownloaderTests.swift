import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct MACVendorDatabaseDownloaderTests {
    @Test func downloadsOnlyTheFourFixedRegistryURLs() async throws {
        let transport = RecordingMACVendorHTTPTransport(responses: validResponses())
        let downloader = MACVendorDatabaseDownloader(transport: transport)

        let inputs = try await downloader.downloadAll { _ in }
        let requests = await transport.requests

        #expect(inputs.count == 4)
        #expect(inputs.map(\.displayName) == ["oui.csv", "mam.csv", "oui36.csv", "iab.csv"])
        #expect(Set(requests.compactMap(\.url)) == Set(MACVendorRegistry.allCases.map(\.downloadURL)))
        #expect(requests.allSatisfy { request in
            request.httpMethod == "GET"
                && request.httpBody == nil
                && request.value(forHTTPHeaderField: "Cookie") == nil
        })
        #expect(await transport.maximumByteLimits == Array(repeating: 16 * 1_024 * 1_024, count: 4))
    }

    @Test func sendsOnlyRequiredStaticHeadersAndNoScanData() async throws {
        let transport = RecordingMACVendorHTTPTransport(responses: validResponses())
        let downloader = MACVendorDatabaseDownloader(transport: transport)

        _ = try await downloader.downloadAll { _ in }

        for request in await transport.requests {
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/csv, application/octet-stream")
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
            let userAgent = request.value(forHTTPHeaderField: "User-Agent")
            #expect(userAgent?.hasPrefix("WiFiLens/") == true)
            #expect(userAgent?.hasSuffix(" (+https://github.com/SHIINASAMA/wifi-lens)") == true)

            let serializedRequest = [
                request.url?.absoluteString,
                request.allHTTPHeaderFields?.description,
                request.httpBody.flatMap { String(data: $0, encoding: .utf8) },
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            #expect(!serializedRequest.contains("Nearby Network"))
            #expect(!serializedRequest.contains("AA:BB:CC:DD:EE:FF"))
            #expect(!serializedRequest.contains("-42"))
        }
    }

    @Test func startsAllRegistryDownloadsWithoutWaitingForEarlierFiles() async {
        let transport = BlockingMACVendorHTTPTransport()
        let downloader = MACVendorDatabaseDownloader(transport: transport)
        let task = Task {
            try await downloader.downloadAll { _ in }
        }

        await transport.waitUntilAllRequestsStarted()

        #expect(await transport.startedCount == MACVendorRegistry.allCases.count)
        task.cancel()
        _ = try? await task.value
    }

    @Test func reportsEveryCompletedRegistry() async throws {
        let transport = RecordingMACVendorHTTPTransport(responses: validResponses())
        let completions = RegistryCompletionRecorder()
        let downloader = MACVendorDatabaseDownloader(transport: transport)

        _ = try await downloader.downloadAll { registry in
            await completions.append(registry)
        }

        #expect(Set(await completions.registries) == Set(MACVendorRegistry.allCases))
        #expect(await completions.registries.count == MACVendorRegistry.allCases.count)
    }

    @Test func failureInLaterRegistryCancelsAllPeersWhenEarlierRegistryIsSuspended() async {
        let transport = FailingAndSuspendingMACVendorHTTPTransport()
        let downloader = MACVendorDatabaseDownloader(transport: transport)
        let task = Task {
            try await downloader.downloadAll { _ in }
        }

        await transport.waitUntilAllRequestsStart()
        await transport.waitUntilPeersSuspend()
        await transport.releaseFailure()

        do {
            _ = try await task.value
            Issue.record("Expected the automatic download batch to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .automaticDownloadFailed)
        } catch {
            Issue.record("Unexpected automatic download error: \(error)")
        }

        #expect(await transport.startedCount == MACVendorRegistry.allCases.count)
        #expect(await transport.cancelledCount == MACVendorRegistry.allCases.count - 1)
    }

    @Test func parentCancellationWinsOverConcurrentRegistryFailure() async {
        let transport = CancellationRacingFailureMACVendorHTTPTransport()
        let downloader = MACVendorDatabaseDownloader(transport: transport)
        let task = Task {
            try await downloader.downloadAll { registry in
                if registry == .maL {
                    await transport.recordFirstCompletion()
                }
            }
        }

        await transport.waitUntilFirstCompletion()
        task.cancel()
        await transport.releaseFailure()
        await transport.waitUntilFailureWillReturn()
        await transport.releasePeers()

        do {
            _ = try await task.value
            Issue.record("Expected parent cancellation to be preserved")
        } catch is CancellationError {
            // Expected cancellation path.
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
    }

    @Test func rejectsResponseOverPerFileLimit() async {
        var responses = Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { registry in
            (
                registry.downloadURL,
                MACVendorHTTPResponse(
                    data: Data([0x41]),
                    statusCode: 200,
                    finalURL: registry.downloadURL
                )
            )
        })
        responses[MACVendorRegistry.maL.downloadURL] = MACVendorHTTPResponse(
            data: Data(repeating: 0x41, count: 17),
            statusCode: 200,
            finalURL: MACVendorRegistry.maL.downloadURL
        )
        let transport = RecordingMACVendorHTTPTransport(responses: responses)
        let downloader = MACVendorDatabaseDownloader(transport: transport, maximumFileBytes: 16)

        do {
            _ = try await downloader.downloadAll { _ in }
            Issue.record("Expected an oversized response to be rejected")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .automaticDownloadFailed)
        } catch {
            Issue.record("Unexpected response-size error: \(error)")
        }

        #expect(await transport.maximumByteLimits == Array(repeating: 16, count: 4))
    }

    @Test func rejectsAggregateResponsesOverTotalDownloadLimit() async {
        let responses = Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { registry in
            (
                registry.downloadURL,
                MACVendorHTTPResponse(
                    data: Data(repeating: 0x41, count: 9),
                    statusCode: 200,
                    finalURL: registry.downloadURL
                )
            )
        })
        let transport = RecordingMACVendorHTTPTransport(responses: responses)
        let downloader = MACVendorDatabaseDownloader(
            transport: transport,
            maximumFileBytes: 16,
            maximumTotalBytes: 32
        )

        do {
            _ = try await downloader.downloadAll { _ in }
            Issue.record("Expected aggregate download size to be rejected")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .automaticDownloadFailed)
        } catch {
            Issue.record("Unexpected aggregate-size error: \(error)")
        }
    }

    @Test func concurrentFailuresUseStableAutomaticDownloadError() async {
        let transport = OrderedFailureMACVendorHTTPTransport()
        let downloader = MACVendorDatabaseDownloader(transport: transport)

        do {
            _ = try await downloader.downloadAll { _ in }
            Issue.record("Expected registry download failures")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .automaticDownloadFailed)
        } catch {
            Issue.record("Unexpected concurrent failure: \(error)")
        }
    }

    @Test func rejectsDisallowedFinalHost() async {
        var responses = validResponses()
        responses[MACVendorRegistry.maL.downloadURL] = MACVendorHTTPResponse(
            data: fixtureCSV,
            statusCode: 200,
            finalURL: URL(string: "https://example.com/oui.csv")!
        )
        let transport = RecordingMACVendorHTTPTransport(responses: responses)
        let downloader = MACVendorDatabaseDownloader(transport: transport)

        do {
            _ = try await downloader.downloadAll { _ in }
            Issue.record("Expected a disallowed final host to be rejected")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .automaticDownloadFailed)
        } catch {
            Issue.record("Unexpected redirect error: \(error)")
        }
    }

    @Test func cancellationStopsTheActiveDownload() async {
        let transport = SuspendingMACVendorHTTPTransport()
        let downloader = MACVendorDatabaseDownloader(transport: transport)
        let task = Task {
            try await downloader.downloadAll { _ in }
        }

        await transport.waitUntilFetchStarts()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the active download to be cancelled")
        } catch is CancellationError {
            // Expected cancellation path.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    @Test func productionSessionConfigurationDoesNotPersistRequestState() {
        let configuration = URLSessionMACVendorHTTPTransport.makeConfiguration()

        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == 60)
        #expect(configuration.timeoutIntervalForResource == 300)
    }

    @Test func productionURLPolicyAllowsOnlyHTTPSOnTheIEEERegistryHost() {
        #expect(URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(
            URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!
        ))
        #expect(!URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(
            URL(string: "http://standards-oui.ieee.org/oui/oui.csv")!
        ))
        #expect(!URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(
            URL(string: "https://standards-oui.ieee.org.example.com/oui.csv")!
        ))
        #expect(!URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(
            URL(string: "https://user@standards-oui.ieee.org/oui/oui.csv")!
        ))
        #expect(!URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(
            URL(string: "https://standards-oui.ieee.org:444/oui/oui.csv")!
        ))
    }

    @Test func productionTransportPreservesChunkedResponseData() async throws {
        let url = productionTestURL("chunked")
        MACVendorStubURLProtocol.register(url: url) { stub in
            stub.respond(chunks: [Data("alpha".utf8), Data("beta".utf8)])
        }
        defer { MACVendorStubURLProtocol.unregister(url: url) }

        let response = try await productionTransport().fetch(
            URLRequest(url: url),
            maximumBytes: 32,
            byteBudget: MACVendorDownloadByteBudget(maximumBytes: 32)
        )

        #expect(response.data == Data("alphabeta".utf8))
        #expect(response.statusCode == 200)
        #expect(response.finalURL == url)
    }

    @Test func productionTransportEnforcesPerFileLimitWhileReceiving() async {
        let url = productionTestURL("file-limit")
        MACVendorStubURLProtocol.register(url: url) { stub in
            stub.respond(chunks: [Data(repeating: 0x41, count: 6), Data(repeating: 0x42, count: 6)])
        }
        defer { MACVendorStubURLProtocol.unregister(url: url) }

        do {
            _ = try await productionTransport().fetch(
                URLRequest(url: url),
                maximumBytes: 8,
                byteBudget: MACVendorDownloadByteBudget(maximumBytes: 32)
            )
            Issue.record("Expected production transport to enforce its per-file limit")
        } catch MACVendorHTTPTransportError.maximumBytesExceeded {
            // Expected.
        } catch {
            Issue.record("Unexpected per-file transport error: \(error)")
        }
    }

    @Test func productionTransportEnforcesAggregateLimitWhileReceiving() async {
        let url = productionTestURL("aggregate-limit")
        MACVendorStubURLProtocol.register(url: url) { stub in
            stub.respond(chunks: [Data(repeating: 0x41, count: 6), Data(repeating: 0x42, count: 6)])
        }
        defer { MACVendorStubURLProtocol.unregister(url: url) }

        do {
            _ = try await productionTransport().fetch(
                URLRequest(url: url),
                maximumBytes: 16,
                byteBudget: MACVendorDownloadByteBudget(maximumBytes: 8)
            )
            Issue.record("Expected production transport to enforce the aggregate limit")
        } catch MACVendorHTTPTransportError.totalBytesExceeded(8) {
            // Expected.
        } catch {
            Issue.record("Unexpected aggregate transport error: \(error)")
        }
    }

    @Test func productionTransportPropagatesMidResponseFailure() async {
        let url = productionTestURL("mid-response-failure")
        MACVendorStubURLProtocol.register(url: url) { stub in
            stub.respond(chunks: [Data("partial".utf8)], finish: false)
            stub.fail(with: URLError(.networkConnectionLost))
        }
        defer { MACVendorStubURLProtocol.unregister(url: url) }

        do {
            _ = try await productionTransport().fetch(
                URLRequest(url: url),
                maximumBytes: 32,
                byteBudget: MACVendorDownloadByteBudget(maximumBytes: 32)
            )
            Issue.record("Expected the mid-response failure to propagate")
        } catch let error as URLError {
            #expect(error.code == .networkConnectionLost)
        } catch {
            Issue.record("Unexpected mid-response error: \(error)")
        }
    }

    @Test func productionTransportCancellationStopsLoading() async {
        let url = productionTestURL("cancellation")
        let started = AsyncSignal()
        let stopped = AsyncSignal()
        MACVendorStubURLProtocol.register(url: url) { stub in
            started.signal()
            stub.onStop = { stopped.signal() }
            stub.respond(chunks: [Data("partial".utf8)], finish: false)
        }
        defer { MACVendorStubURLProtocol.unregister(url: url) }
        let transport = productionTransport()
        let task = Task {
            try await transport.fetch(
                URLRequest(url: url),
                maximumBytes: 32,
                byteBudget: MACVendorDownloadByteBudget(maximumBytes: 32)
            )
        }

        await started.wait()
        task.cancel()
        _ = try? await task.value

        await stopped.wait()
    }

}

private actor RecordingMACVendorHTTPTransport: MACVendorHTTPTransport {
    private let responses: [URL: MACVendorHTTPResponse]
    private(set) var requests: [URLRequest] = []
    private(set) var maximumByteLimits: [Int] = []

    init(responses: [URL: MACVendorHTTPResponse]) {
        self.responses = responses
    }

    var requestedURLs: [URL?] {
        requests.map(\.url)
    }

    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        requests.append(request)
        maximumByteLimits.append(maximumBytes)
        guard let url = request.url, let response = responses[url] else {
            throw RecordingTransportError.missingResponse
        }
        try byteBudget.consume(response.data.count)
        return response
    }
}

private actor SuspendingMACVendorHTTPTransport: MACVendorHTTPTransport {
    private var fetchStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        fetchStarted = true
        startContinuation?.resume()
        startContinuation = nil
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            throw URLError(.cancelled)
        }
        throw RecordingTransportError.unexpectedResume
    }

    func waitUntilFetchStarts() async {
        guard !fetchStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }
}

private actor BlockingMACVendorHTTPTransport: MACVendorHTTPTransport {
    private(set) var startedCount = 0
    private var allStartedWaiters: [CheckedContinuation<Void, Never>] = []

    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        startedCount += 1
        if startedCount == MACVendorRegistry.allCases.count {
            let pending = allStartedWaiters
            allStartedWaiters.removeAll()
            pending.forEach { $0.resume() }
        }
        try await Task.sleep(for: .seconds(60))
        throw RecordingTransportError.unexpectedResume
    }

    func waitUntilAllRequestsStarted() async {
        if startedCount == MACVendorRegistry.allCases.count { return }
        await withCheckedContinuation { allStartedWaiters.append($0) }
    }
}

private actor FailingAndSuspendingMACVendorHTTPTransport: MACVendorHTTPTransport {
    private(set) var startedCount = 0
    private(set) var cancelledCount = 0
    private var suspendedPeerCount = 0
    private var allRequestsStartedContinuation: CheckedContinuation<Void, Never>?
    private var peersSuspendedContinuation: CheckedContinuation<Void, Never>?
    private var failureContinuation: CheckedContinuation<Void, Never>?

    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        startedCount += 1
        let url = try #require(request.url)
        let registry = try #require(MACVendorRegistry.allCases.first { $0.downloadURL == url })
        if registry == .maM {
            allRequestsStartedContinuation?.resume()
            allRequestsStartedContinuation = nil
            await withCheckedContinuation { continuation in
                failureContinuation = continuation
            }
            return response(for: registry, statusCode: 503)
        }
        suspendedPeerCount += 1
        if startedCount == MACVendorRegistry.allCases.count {
            allRequestsStartedContinuation?.resume()
            allRequestsStartedContinuation = nil
        }
        if suspendedPeerCount == MACVendorRegistry.allCases.count - 1 {
            peersSuspendedContinuation?.resume()
            peersSuspendedContinuation = nil
        }
        do {
            try await Task.sleep(for: .seconds(30))
            return response(for: registry)
        } catch is CancellationError {
            cancelledCount += 1
            throw CancellationError()
        }
    }

    func waitUntilAllRequestsStart() async {
        guard startedCount < MACVendorRegistry.allCases.count else { return }
        await withCheckedContinuation { continuation in
            allRequestsStartedContinuation = continuation
        }
    }

    func waitUntilPeersSuspend() async {
        guard suspendedPeerCount < MACVendorRegistry.allCases.count - 1 else { return }
        await withCheckedContinuation { continuation in
            peersSuspendedContinuation = continuation
        }
    }

    func releaseFailure() {
        failureContinuation?.resume()
        failureContinuation = nil
    }
}

private actor CancellationRacingFailureMACVendorHTTPTransport: MACVendorHTTPTransport {
    private var startedCount = 0
    private var firstCompletionRecorded = false
    private var allRequestsStartedContinuation: CheckedContinuation<Void, Never>?
    private var failureContinuation: CheckedContinuation<Void, Never>?
    private var failureWillReturn = false
    private var failureWillReturnContinuation: CheckedContinuation<Void, Never>?
    private var peerContinuations: [CheckedContinuation<Void, Never>] = []
    private var firstCompletionContinuation: CheckedContinuation<Void, Never>?

    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        let url = try #require(request.url)
        let registry = try #require(MACVendorRegistry.allCases.first { $0.downloadURL == url })
        startedCount += 1
        if startedCount == MACVendorRegistry.allCases.count {
            allRequestsStartedContinuation?.resume()
            allRequestsStartedContinuation = nil
        }

        switch registry {
        case .maL:
            await waitUntilAllRequestsStart()
            return response(for: registry)
        case .maM:
            await withCheckedContinuation { continuation in
                failureContinuation = continuation
            }
            failureWillReturn = true
            failureWillReturnContinuation?.resume()
            failureWillReturnContinuation = nil
            return response(for: registry, statusCode: 503)
        case .maS, .iab:
            await withCheckedContinuation { continuation in
                peerContinuations.append(continuation)
            }
            return response(for: registry)
        }
    }

    func recordFirstCompletion() {
        firstCompletionRecorded = true
        firstCompletionContinuation?.resume()
        firstCompletionContinuation = nil
    }

    func waitUntilFirstCompletion() async {
        guard !firstCompletionRecorded else { return }
        await withCheckedContinuation { continuation in
            firstCompletionContinuation = continuation
        }
    }

    func releaseFailure() {
        failureContinuation?.resume()
        failureContinuation = nil
    }

    func waitUntilFailureWillReturn() async {
        guard !failureWillReturn else { return }
        await withCheckedContinuation { continuation in
            failureWillReturnContinuation = continuation
        }
    }

    func releasePeers() {
        for continuation in peerContinuations {
            continuation.resume()
        }
        peerContinuations.removeAll()
    }

    private func waitUntilAllRequestsStart() async {
        guard startedCount < MACVendorRegistry.allCases.count else { return }
        await withCheckedContinuation { continuation in
            allRequestsStartedContinuation = continuation
        }
    }
}

private actor OrderedFailureMACVendorHTTPTransport: MACVendorHTTPTransport {
    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        let url = try #require(request.url)
        let registry = try #require(MACVendorRegistry.allCases.first { $0.downloadURL == url })
        if registry == .maL {
            try await Task.sleep(for: .milliseconds(50))
            return response(for: registry, statusCode: 503)
        }
        if registry == .maM {
            return response(for: registry, statusCode: 502)
        }
        return response(for: registry)
    }
}

private actor RegistryCompletionRecorder {
    private(set) var registries: [MACVendorRegistry] = []

    func append(_ registry: MACVendorRegistry) {
        registries.append(registry)
    }
}

private enum RecordingTransportError: Error {
    case missingResponse
    case unexpectedResume
}

private final class MACVendorStubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (MACVendorStubURLProtocol) -> Void

    private static let handlersLock = NSLock()
    nonisolated(unsafe) private static var handlers: [URL: Handler] = [:]

    private let stateLock = NSLock()
    private var stopped = false
    var onStop: (@Sendable () -> Void)?

    static func register(url: URL, handler: @escaping Handler) {
        handlersLock.withLock { handlers[url] = handler }
    }

    static func unregister(url: URL) {
        handlersLock.withLock { handlers[url] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return handlersLock.withLock { handlers[url] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let handler = Self.handlersLock.withLock({ Self.handlers[url] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        handler(self)
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
        onStop?()
    }

    func respond(chunks: [Data], finish: Bool = true) {
        guard !isStopped, let url = request.url else { return }
        let length = chunks.reduce(0) { $0 + $1.count }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(length)]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks where !isStopped {
            client?.urlProtocol(self, didLoad: chunk)
        }
        if finish, !isStopped { client?.urlProtocolDidFinishLoading(self) }
    }

    func fail(with error: Error) {
        guard !isStopped else { return }
        client?.urlProtocol(self, didFailWithError: error)
    }

    private var isStopped: Bool {
        stateLock.withLock { stopped }
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        var pending: [CheckedContinuation<Void, Never>] = []
        lock.withLock {
            isSignaled = true
            pending = waiters
            waiters.removeAll()
        }
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            var resumeImmediately = false
            lock.withLock {
                if isSignaled {
                    resumeImmediately = true
                } else {
                    waiters.append(continuation)
                }
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }
}

private func productionTestURL(_ name: String) -> URL {
    URL(string: "https://standards-oui.ieee.org/codex-tests/\(name).csv")!
}

private func productionTransport() -> URLSessionMACVendorHTTPTransport {
    let configuration = URLSessionMACVendorHTTPTransport.makeConfiguration()
    configuration.protocolClasses = [MACVendorStubURLProtocol.self]
    return URLSessionMACVendorHTTPTransport(configuration: configuration)
}

private let fixtureCSV = Data("Registry,Assignment,Organization Name\nMA-L,001122,Example Networks\n".utf8)

private func response(
    for registry: MACVendorRegistry,
    statusCode: Int = 200,
    finalURL: URL? = nil
) -> MACVendorHTTPResponse {
    MACVendorHTTPResponse(
        data: fixtureCSV,
        statusCode: statusCode,
        finalURL: finalURL ?? registry.downloadURL
    )
}

private func validResponses() -> [URL: MACVendorHTTPResponse] {
    Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { registry in
        (registry.downloadURL, response(for: registry))
    })
}
