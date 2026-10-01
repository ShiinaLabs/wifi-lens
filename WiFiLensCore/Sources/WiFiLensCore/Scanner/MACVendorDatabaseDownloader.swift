import Foundation

struct MACVendorHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let finalURL: URL
}

protocol MACVendorHTTPTransport: Sendable {
    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse
}

final class MACVendorDownloadByteBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var consumedBytes = 0

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func consume(_ byteCount: Int) throws {
        try lock.withLock {
            guard byteCount >= 0,
                  byteCount <= maximumBytes - consumedBytes
            else {
                throw MACVendorHTTPTransportError.totalBytesExceeded(maximumBytes)
            }
            consumedBytes += byteCount
        }
    }
}

final class URLSessionMACVendorHTTPTransport: Sendable {
    private let session: URLSession

    convenience init() {
        self.init(configuration: URLSessionMACVendorHTTPTransport.makeConfiguration())
    }

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return configuration
    }

    static func isAllowedIEEEURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "standards-oui.ieee.org"
            && url.user == nil
            && url.password == nil
            && (url.port == nil || url.port == 443)
    }
}

extension URLSessionMACVendorHTTPTransport: MACVendorHTTPTransport {
    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        let delegate = MACVendorDownloadDelegate(
            maximumFileBytes: maximumBytes,
            byteBudget: byteBudget
        )

        do {
            let (temporaryURL, response) = try await session.download(
                for: request,
                delegate: delegate
            )
            try Task.checkCancellation()
            if let rejection = delegate.rejection { throw rejection }

            let finalURL = response.url ?? request.url
            guard let finalURL else {
                throw MACVendorHTTPTransportError.missingFinalURL
            }
            let attributes = try FileManager.default.attributesOfItem(
                atPath: temporaryURL.path
            )
            let fileByteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            try delegate.validateCompletedFile(byteCount: fileByteCount)
            let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)

            return MACVendorHTTPResponse(
                data: data,
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                finalURL: finalURL
            )
        } catch {
            if let rejection = delegate.rejection { throw rejection }
            throw error
        }
    }
}

struct MACVendorDatabaseDownloader: Sendable {
    let transport: any MACVendorHTTPTransport
    let maximumFileBytes: Int
    let maximumTotalBytes: Int

    init(
        transport: any MACVendorHTTPTransport = URLSessionMACVendorHTTPTransport(),
        maximumFileBytes: Int = 16 * 1_024 * 1_024,
        maximumTotalBytes: Int = 32 * 1_024 * 1_024
    ) {
        self.transport = transport
        self.maximumFileBytes = maximumFileBytes
        self.maximumTotalBytes = maximumTotalBytes
    }

    func downloadAll(
        onCompleted: @Sendable (MACVendorRegistry) async -> Void
    ) async throws -> [MACVendorRegistryInput] {
        let byteBudget = MACVendorDownloadByteBudget(maximumBytes: maximumTotalBytes)
        return try await withThrowingTaskGroup(
            of: (MACVendorRegistry, MACVendorRegistryInput).self
        ) { group in
            for registry in MACVendorRegistry.allCases {
                group.addTask {
                    try Task.checkCancellation()
                    return (registry, try await download(registry, byteBudget: byteBudget))
                }
            }

            var inputsByRegistry: [MACVendorRegistry: MACVendorRegistryInput] = [:]
            do {
                while let (registry, input) = try await group.next() {
                    try Task.checkCancellation()
                    inputsByRegistry[registry] = input
                    await onCompleted(registry)
                }
            } catch is CancellationError {
                group.cancelAll()
                throw CancellationError()
            } catch where Task.isCancelled {
                group.cancelAll()
                throw CancellationError()
            } catch {
                group.cancelAll()
                throw MACVendorDatabaseError.automaticDownloadFailed
            }

            try Task.checkCancellation()
            return MACVendorRegistry.allCases.compactMap { inputsByRegistry[$0] }
        }
    }

    private func download(
        _ registry: MACVendorRegistry,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorRegistryInput {
        try Task.checkCancellation()
        let request = makeRequest(for: registry)
        let response: MACVendorHTTPResponse

        do {
            response = try await transport.fetch(
                request,
                maximumBytes: maximumFileBytes,
                byteBudget: byteBudget
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch MACVendorHTTPTransportError.maximumBytesExceeded {
            throw MACVendorDatabaseError.fileTooLarge(
                file: registry.downloadURL.lastPathComponent,
                maximumBytes: maximumFileBytes
            )
        } catch let MACVendorHTTPTransportError.totalBytesExceeded(maximumBytes) {
            throw MACVendorDatabaseError.totalSizeExceeded(maximumBytes: maximumBytes)
        } catch let MACVendorHTTPTransportError.disallowedRedirect(url) {
            throw MACVendorDatabaseError.disallowedRedirect(url)
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.downloadFailed(registry)
        }

        guard URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(response.finalURL) else {
            throw MACVendorDatabaseError.disallowedRedirect(response.finalURL)
        }
        guard response.statusCode == 200 else {
            throw MACVendorDatabaseError.invalidHTTPStatus(
                registry: registry,
                statusCode: response.statusCode
            )
        }
        guard response.data.count <= maximumFileBytes else {
            throw MACVendorDatabaseError.fileTooLarge(
                file: registry.downloadURL.lastPathComponent,
                maximumBytes: maximumFileBytes
            )
        }

        return MACVendorRegistryInput(
            displayName: registry.downloadURL.lastPathComponent,
            data: response.data
        )
    }

    private func makeRequest(for registry: MACVendorRegistry) -> URLRequest {
        var request = URLRequest(url: registry.downloadURL)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.setValue("text/csv, application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        return "WiFiLens/\(version) (+https://github.com/SHIINASAMA/wifi-lens)"
    }()
}

private final class MACVendorDownloadDelegate: NSObject,
    URLSessionDownloadDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let maximumFileBytes: Int
    private let byteBudget: MACVendorDownloadByteBudget
    private var storedRejection: MACVendorHTTPTransportError?
    private var accountedBytes = 0

    init(maximumFileBytes: Int, byteBudget: MACVendorDownloadByteBudget) {
        self.maximumFileBytes = maximumFileBytes
        self.byteBudget = byteBudget
    }

    var rejection: MACVendorHTTPTransportError? {
        lock.withLock { storedRejection }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, URLSessionMACVendorHTTPTransport.isAllowedIEEEURL(url) else {
            if let url = request.url {
                storeRejection(.disallowedRedirect(url))
            } else {
                storeRejection(.missingFinalURL)
            }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard rejection == nil else {
            downloadTask.cancel()
            return
        }
        do {
            guard totalBytesWritten <= Int64(maximumFileBytes) else {
                throw MACVendorHTTPTransportError.maximumBytesExceeded
            }
            try byteBudget.consume(Int(bytesWritten))
            lock.withLock { accountedBytes += Int(bytesWritten) }
        } catch let error as MACVendorHTTPTransportError {
            storeRejection(error)
            downloadTask.cancel()
        } catch {
            storeRejection(.totalBytesExceeded(0))
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func validateCompletedFile(byteCount: Int) throws {
        guard byteCount <= maximumFileBytes else {
            throw MACVendorHTTPTransportError.maximumBytesExceeded
        }
        let unaccountedBytes = lock.withLock { max(0, byteCount - accountedBytes) }
        try byteBudget.consume(unaccountedBytes)
        lock.withLock { accountedBytes += unaccountedBytes }
    }

    private func storeRejection(_ error: MACVendorHTTPTransportError) {
        lock.withLock {
            if storedRejection == nil { storedRejection = error }
        }
    }
}

enum MACVendorHTTPTransportError: Error, Sendable {
    case maximumBytesExceeded
    case totalBytesExceeded(Int)
    case missingFinalURL
    case disallowedRedirect(URL)
}
