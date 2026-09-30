import Foundation
import WiFiLensCore

protocol MACVendorDatabaseServicing: Sendable {
    func load() async throws -> MACVendorDatabase?
    func download(
        createdAt: Date,
        progress: @Sendable (Int) async -> Void
    ) async throws -> MACVendorDatabase
    func prepareManualImport(urls: [URL], createdAt: Date) async throws -> MACVendorDatabase
    func install(_ database: MACVendorDatabase) async throws
    func clear() async throws
}

actor MACVendorDatabaseService: MACVendorDatabaseServicing {
    private let parser: MACVendorCSVParser
    private let store: MACVendorDatabaseStore
    private let downloader: MACVendorDatabaseDownloader

    init(
        parser: MACVendorCSVParser = MACVendorCSVParser(),
        store: MACVendorDatabaseStore = MACVendorDatabaseStore(),
        downloader: MACVendorDatabaseDownloader = MACVendorDatabaseDownloader()
    ) {
        self.parser = parser
        self.store = store
        self.downloader = downloader
    }

    func load() async throws -> MACVendorDatabase? {
        do {
            try Task.checkCancellation()
            let database = try await store.load()
            try Task.checkCancellation()
            return database
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.persistenceFailure
        }
    }

    func download(
        createdAt: Date,
        progress: @Sendable (Int) async -> Void
    ) async throws -> MACVendorDatabase {
        let progressCounter = MACVendorDownloadProgressCounter()

        do {
            let inputs = try await downloader.downloadAll { _ in
                let completed = await progressCounter.increment()
                await progress(completed)
            }
            try Task.checkCancellation()
            let database = try parser.parse(
                inputs: inputs,
                source: .ieeeDownload,
                createdAt: createdAt
            )
            try Task.checkCancellation()
            return database
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.downloadFailed(.maL)
        }
    }

    func prepareManualImport(urls: [URL], createdAt: Date) async throws -> MACVendorDatabase {
        do {
            try Task.checkCancellation()
            guard urls.count == MACVendorRegistry.allCases.count else {
                throw MACVendorDatabaseError.wrongFileCount(
                    expected: MACVendorRegistry.allCases.count,
                    actual: urls.count
                )
            }
            let inputs = try await store.readImportFiles(urls)
            try Task.checkCancellation()
            let database = try parser.parse(
                inputs: inputs,
                source: .manualImport,
                createdAt: createdAt
            )
            try Task.checkCancellation()
            return database
        } catch is CancellationError {
            throw CancellationError()
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.fileReadFailed(urls.first?.lastPathComponent ?? "")
        }
    }

    func install(_ database: MACVendorDatabase) async throws {
        do {
            try await store.replace(with: database)
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.persistenceFailure
        }
    }

    func clear() async throws {
        do {
            try await store.clear()
        } catch let error as MACVendorDatabaseError {
            throw error
        } catch {
            throw MACVendorDatabaseError.persistenceFailure
        }
    }
}

private actor MACVendorDownloadProgressCounter {
    private var completed = 0

    func increment() -> Int {
        completed += 1
        return completed
    }
}
