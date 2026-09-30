import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct MACVendorDatabaseManagerTests {
    @Test func bundledLaunchAvailabilityIsAvailableWithoutLoadingPersistedDatabase() async {
        let summary = makeDatabase(organization: "Bundled Name").summary
        let service = FakeMACVendorDatabaseService()
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service,
            initialAvailability: .installed(summary)
        )

        await manager.loadInstalledDatabase()

        #expect(manager.availability == .installed(summary))
        #expect(manager.databaseRevision == 0)
        #expect(await service.loadCallCount == 0)
    }

    @Test func missingLaunchDatabasePublishesNotInstalled() async {
        let resolver = makeResolver(organization: "Stale Name")
        let service = FakeMACVendorDatabaseService()
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)

        await manager.loadInstalledDatabase()

        #expect(manager.availability == .notInstalled)
        #expect(manager.operation == .idle)
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .unknown)
    }

    @Test func validLaunchDatabaseInstallsResolverAndPublishesSummary() async {
        let database = makeDatabase(organization: "Installed Name")
        let resolver = MACVendorResolver(entries: [])
        let service = FakeMACVendorDatabaseService(loadedDatabase: database)
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)

        await manager.loadInstalledDatabase()

        #expect(manager.availability == .installed(database.summary))
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Installed Name"))
    }

    @Test func corruptLaunchDatabaseIsUnavailableWithoutPresentingBlockingError() async {
        let resolver = MACVendorResolver(entries: [])
        let service = FakeMACVendorDatabaseService(loadError: .persistenceFailure)
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)

        await manager.loadInstalledDatabase()

        #expect(manager.availability == .unavailable(.persistenceFailure))
        #expect(manager.operation == .idle)
        #expect(manager.presentedError == nil)
        #expect(resolver.resolve(testAddress) == .unknown)
    }

    @Test func downloadInstallsOnlyAfterPersistenceSucceeds() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let newDatabase = makeDatabase(organization: "New Name", source: .ieeeDownload)
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            downloadedDatabase: newDatabase,
            suspendInstall: true
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilInstallCalled()

        #expect(manager.operation == .installing)
        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))

        await service.releaseInstall()
        await downloadTask.value

        #expect(manager.availability == .installed(newDatabase.summary))
        #expect(manager.databaseRevision == 2)
        #expect(resolver.resolve(testAddress) == .registered("New Name"))
    }

    @Test func oneRegistryDownloadFailurePreservesInstalledResolverAndAvailability() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            downloadError: .downloadFailed(.maM)
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.downloadAndInstall()

        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(manager.presentedError == .downloadFailed(.maM))
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
    }

    @Test func validationFailurePreservesInstalledResolverAndAvailability() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            downloadError: .tooFewRecords(registry: .maS, minimum: 1_000, actual: 999)
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.downloadAndInstall()

        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(manager.presentedError == .tooFewRecords(registry: .maS, minimum: 1_000, actual: 999))
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
    }

    @Test func persistenceFailurePreservesInstalledResolverAndAvailability() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let newDatabase = makeDatabase(organization: "New Name", source: .ieeeDownload)
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            downloadedDatabase: newDatabase,
            installError: .persistenceFailure
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.downloadAndInstall()

        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(manager.presentedError == .persistenceFailure)
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
    }

    @Test func manualPreparationDoesNotInstallUntilConfirmed() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let preparedDatabase = makeDatabase(organization: "New Name", source: .manualImport)
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            preparedDatabase: preparedDatabase
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.prepareManualImport(urls: fourFixtureURLs())

        #expect(manager.pendingManualImport(for: nil) == preparedDatabase.summary)
        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
        #expect(await service.installCallCount == 0)

        await manager.confirmManualImport()

        #expect(manager.pendingManualImport(for: nil) == nil)
        #expect(manager.availability == .installed(preparedDatabase.summary))
        #expect(manager.databaseRevision == 2)
        #expect(resolver.resolve(testAddress) == .registered("New Name"))
    }

    @Test func failedManualConfirmationKeepsPreparedDatabaseAndOldInstallation() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let preparedDatabase = makeDatabase(organization: "New Name")
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            preparedDatabase: preparedDatabase,
            installError: .persistenceFailure
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()
        await manager.prepareManualImport(urls: fourFixtureURLs())

        await manager.confirmManualImport()

        #expect(manager.pendingManualImport(for: nil) == preparedDatabase.summary)
        #expect(manager.availability == .installed(oldDatabase.summary))
        #expect(manager.presentedError == .persistenceFailure)
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
    }

    @Test func failedManualReselectionDiscardsPreviouslyPreparedDatabase() async {
        let preparedDatabase = makeDatabase(organization: "Previously Prepared")
        let service = FakeMACVendorDatabaseService(preparedDatabase: preparedDatabase)
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )
        await manager.prepareManualImport(urls: fourFixtureURLs())
        #expect(manager.pendingManualImport(for: nil) == preparedDatabase.summary)

        await service.setPreparationError(.malformedCSV(file: "oui.csv"))
        await manager.prepareManualImport(urls: fourFixtureURLs())

        #expect(manager.pendingManualImport(for: nil) == nil)
        #expect(manager.presentedError == .malformedCSV(file: "oui.csv"))
        await manager.confirmManualImport()
        #expect(manager.presentedError == .noPreparedImport)
        #expect(await service.installCallCount == 0)
    }

    @Test func confirmationWithoutPreparedImportPublishesTypedError() async {
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: FakeMACVendorDatabaseService()
        )

        await manager.confirmManualImport()

        #expect(manager.presentedError == .noPreparedImport)
        #expect(manager.operation == .idle)
        #expect(manager.databaseRevision == 0)
    }

    @Test func discardRemovesPreparedImportWithoutChangingResolver() async {
        let preparedDatabase = makeDatabase(organization: "New Name")
        let resolver = makeResolver(organization: "Old Name")
        let manager = MACVendorDatabaseManager(
            resolver: resolver,
            service: FakeMACVendorDatabaseService(preparedDatabase: preparedDatabase)
        )
        await manager.prepareManualImport(urls: fourFixtureURLs())

        manager.discardPreparedManualImport()

        #expect(manager.pendingManualImport(for: nil) == nil)
        #expect(manager.databaseRevision == 0)
        #expect(resolver.resolve(testAddress) == .registered("Old Name"))
    }

    @Test func onlyOperationOwnerCanCancelDownload() async throws {
        let ownerA = UUID()
        let ownerB = UUID()
        let service = FakeMACVendorDatabaseService(suspendDownload: true)
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )

        let downloadTask = Task { await manager.downloadAndInstall(ownerID: ownerA) }
        await service.waitUntilDownloadCalled()

        #expect(manager.cancelCurrentOperation(ownerID: ownerB) == nil)
        #expect(manager.operation != .idle)
        #expect(manager.operation(for: ownerA) == manager.operation)
        #expect(manager.operation(for: ownerB) == .idle)
        #expect(await service.observedDownloadCancellation == false)

        let ownerAHandle = try #require(manager.cancelCurrentOperation(ownerID: ownerA))
        await manager.waitForCancellation(ownerAHandle)
        await downloadTask.value

        #expect(manager.operation == .idle)
        #expect(await service.observedDownloadCancellation)
    }

    @Test func onlyOperationOwnerCanObserveOrCancelManualPreparation() async throws {
        let ownerA = UUID()
        let ownerB = UUID()
        let service = FakeMACVendorDatabaseService(suspendPreparation: true)
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )

        let preparationTask = Task {
            await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerA)
        }
        await service.waitUntilPrepareCalled()

        #expect(manager.operation(for: ownerA) == .readingFiles)
        #expect(manager.operation(for: ownerB) == .idle)
        #expect(manager.cancelCurrentOperation(ownerID: ownerB) == nil)
        #expect(await service.observedPreparationCancellation == false)

        let ownerAHandle = try #require(manager.cancelCurrentOperation(ownerID: ownerA))
        await manager.waitForCancellation(ownerAHandle)
        await preparationTask.value

        #expect(manager.operation(for: ownerA) == .idle)
        #expect(await service.observedPreparationCancellation)
    }

    @Test func onlyPreparedImportOwnerCanDiscardOrConfirmIt() async {
        let ownerA = UUID()
        let ownerB = UUID()
        let oldDatabase = makeDatabase(organization: "Old Name")
        let preparedDatabase = makeDatabase(organization: "Prepared Name")
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            preparedDatabase: preparedDatabase
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerA)

        #expect(manager.pendingManualImport(for: ownerA) == preparedDatabase.summary)
        #expect(manager.pendingManualImport(for: ownerB) == nil)

        manager.discardPreparedManualImport(ownerID: ownerB)
        await manager.confirmManualImport(ownerID: ownerB)

        #expect(manager.pendingManualImport(for: ownerA) == preparedDatabase.summary)
        #expect(manager.pendingManualImport(for: ownerB) == nil)
        #expect(await service.installCallCount == 0)
        #expect(manager.availability == .installed(oldDatabase.summary))

        manager.discardPreparedManualImport(ownerID: ownerA)
        #expect(manager.pendingManualImport(for: ownerA) == nil)

        await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerA)
        await manager.confirmManualImport(ownerID: ownerA)

        #expect(manager.pendingManualImport(for: ownerA) == nil)
        #expect(manager.availability == .installed(preparedDatabase.summary))
        #expect(await service.installCallCount == 1)
        #expect(resolver.resolve(testAddress) == .registered("Prepared Name"))
    }

    @Test func otherOwnerCannotReplacePreparedManualImport() async {
        let ownerA = UUID()
        let ownerB = UUID()
        let preparedDatabase = makeDatabase(organization: "Prepared Name")
        let service = FakeMACVendorDatabaseService(preparedDatabase: preparedDatabase)
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )

        await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerA)
        await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerB)

        #expect(manager.pendingManualImport(for: ownerA) == preparedDatabase.summary)
        #expect(manager.pendingManualImport(for: ownerB) == nil)
        #expect(await service.prepareCallCount == 1)
    }

    @Test func preparedImportOwnerCanDiscardDuringAnotherOwnersOperation() async throws {
        let ownerA = UUID()
        let ownerB = UUID()
        let preparedDatabase = makeDatabase(organization: "Prepared Name")
        let service = FakeMACVendorDatabaseService(
            preparedDatabase: preparedDatabase,
            suspendDownload: true
        )
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )
        await manager.prepareManualImport(urls: fourFixtureURLs(), ownerID: ownerA)

        let downloadTask = Task { await manager.downloadAndInstall(ownerID: ownerB) }
        await service.waitUntilDownloadCalled()

        #expect(manager.cancelCurrentOperation(ownerID: ownerA) == nil)
        manager.discardPreparedManualImport(ownerID: ownerA)

        #expect(manager.pendingManualImport(for: ownerA) == nil)
        #expect(manager.operation(for: ownerB) != .idle)
        #expect(manager.operation(for: ownerA) == .idle)
        #expect(await service.observedDownloadCancellation == false)

        let ownerBHandle = try #require(manager.cancelCurrentOperation(ownerID: ownerB))
        await manager.waitForCancellation(ownerBHandle)
        await downloadTask.value
    }

    @Test func operationErrorIsVisibleAndDismissibleOnlyByItsOwner() async {
        let ownerA = UUID()
        let ownerB = UUID()
        let service = FakeMACVendorDatabaseService(downloadError: .downloadFailed(.maM))
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )

        await manager.downloadAndInstall(ownerID: ownerA)

        #expect(manager.presentedError(for: ownerA) == .downloadFailed(.maM))
        #expect(manager.presentedError(for: ownerB) == nil)
        #expect(manager.presentedError == nil)

        manager.dismissPresentedError(ownerID: ownerB)
        #expect(manager.presentedError(for: ownerA) == .downloadFailed(.maM))

        manager.dismissPresentedError(ownerID: ownerA)
        #expect(manager.presentedError(for: ownerA) == nil)
    }

    @Test func processErrorRemainsGlobalAndCannotBeDismissedBySheetOwner() async {
        let owner = UUID()
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: FakeMACVendorDatabaseService(clearError: .persistenceFailure)
        )

        await manager.clear()

        #expect(manager.presentedError == .persistenceFailure)
        #expect(manager.presentedError(for: owner) == nil)

        manager.dismissPresentedError(ownerID: owner)
        #expect(manager.presentedError == .persistenceFailure)

        manager.dismissPresentedError()
        #expect(manager.presentedError == nil)
    }

    @Test func clearEmptiesResolverCacheAndPublishesRevision() async {
        let database = makeDatabase(organization: "Installed Name")
        let resolver = makeResolver(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(loadedDatabase: database)
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()
        #expect(resolver.resolve(testAddress) == .registered("Installed Name"))

        await manager.clear()

        #expect(manager.availability == .notInstalled)
        #expect(manager.pendingManualImport(for: nil) == nil)
        #expect(manager.databaseRevision == 2)
        #expect(resolver.resolve(testAddress) == .unknown)
    }

    @Test func clearFailurePreservesInstalledState() async {
        let database = makeDatabase(organization: "Installed Name")
        let resolver = makeResolver(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: database,
            clearError: .persistenceFailure
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        await manager.clear()

        #expect(manager.availability == .installed(database.summary))
        #expect(manager.presentedError == .persistenceFailure)
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Installed Name"))
    }

    @Test func cancellingAcquisitionPreservesInstalledStateAndCancellationIdentity() async {
        let database = makeDatabase(organization: "Installed Name")
        let resolver = makeResolver(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: database,
            suspendDownload: true
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilDownloadCalled()
        manager.cancelCurrentOperation()
        await downloadTask.value

        #expect(manager.operation == .idle)
        #expect(manager.availability == .installed(database.summary))
        #expect(manager.presentedError == nil)
        #expect(manager.databaseRevision == 1)
        #expect(resolver.resolve(testAddress) == .registered("Installed Name"))
        #expect(await service.observedDownloadCancellation)
    }

    @Test func cancellingManualReadPreservesInstalledState() async {
        let database = makeDatabase(organization: "Installed Name")
        let resolver = makeResolver(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: database,
            suspendPreparation: true
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        let preparationTask = Task { await manager.prepareManualImport(urls: fourFixtureURLs()) }
        await service.waitUntilPrepareCalled()
        manager.cancelCurrentOperation()
        await preparationTask.value

        #expect(manager.operation == .idle)
        #expect(manager.pendingManualImport(for: nil) == nil)
        #expect(manager.availability == .installed(database.summary))
        #expect(manager.presentedError == nil)
        #expect(await service.observedPreparationCancellation)
    }

    @Test func waitingCurrentCancellationHandleReturnsAfterOperationSettles() async throws {
        let database = makeDatabase(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: database,
            suspendDownload: true
        )
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )
        await manager.loadInstalledDatabase()

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilDownloadCalled()

        let handle = try #require(manager.cancelCurrentOperation())
        await manager.waitForCancellation(handle)

        #expect(manager.operation == .idle)
        #expect(await service.observedDownloadCancellation)
        await downloadTask.value
    }

    @Test func waitingStaleCancellationHandleCannotSettleReplacementOperation() async throws {
        let service = FakeMACVendorDatabaseService(
            suspendDownload: true,
            suspendPreparation: true
        )
        let manager = MACVendorDatabaseManager(
            resolver: MACVendorResolver(entries: []),
            service: service
        )

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilDownloadCalled()
        let staleHandle = try #require(manager.cancelCurrentOperation())
        await downloadTask.value
        #expect(manager.operation == .idle)

        let preparationTask = Task {
            await manager.prepareManualImport(urls: fourFixtureURLs())
        }
        await service.waitUntilPrepareCalled()
        #expect(manager.operation == .readingFiles)

        await manager.waitForCancellation(staleHandle)

        #expect(manager.operation == .readingFiles)
        #expect(await service.prepareCallCount == 1)

        let replacementHandle = try #require(manager.cancelCurrentOperation())
        await manager.waitForCancellation(replacementHandle)
        await preparationTask.value
    }

    @Test func cancellationIsIgnoredAfterInstallingBegins() async {
        let oldDatabase = makeDatabase(organization: "Old Name")
        let newDatabase = makeDatabase(organization: "New Name", source: .ieeeDownload)
        let resolver = makeResolver(organization: "Old Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: oldDatabase,
            downloadedDatabase: newDatabase,
            suspendInstall: true
        )
        let manager = MACVendorDatabaseManager(resolver: resolver, service: service)
        await manager.loadInstalledDatabase()

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilInstallCalled()
        manager.cancelCurrentOperation()
        await service.releaseInstall()
        await downloadTask.value

        #expect(manager.availability == .installed(newDatabase.summary))
        #expect(manager.presentedError == nil)
        #expect(manager.databaseRevision == 2)
        #expect(resolver.resolve(testAddress) == .registered("New Name"))
    }

    @Test func competingOperationsAreRejectedWithoutChangingCurrentState() async {
        let database = makeDatabase(organization: "Installed Name")
        let service = FakeMACVendorDatabaseService(
            loadedDatabase: database,
            suspendDownload: true
        )
        let manager = MACVendorDatabaseManager(resolver: MACVendorResolver(entries: []), service: service)
        await manager.loadInstalledDatabase()

        let downloadTask = Task { await manager.downloadAndInstall() }
        await service.waitUntilDownloadCalled()
        let operationBeforeCompetition = manager.operation

        await manager.prepareManualImport(urls: fourFixtureURLs())
        await manager.clear()

        #expect(manager.operation == operationBeforeCompetition)
        #expect(await service.prepareCallCount == 0)
        #expect(await service.clearCallCount == 0)

        manager.cancelCurrentOperation()
        await downloadTask.value
    }
}

struct MACVendorDatabaseServiceTests {
    @Test func downloadedDatabaseIsNotPersistedUntilInstall() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)
        let parser = MACVendorCSVParser(minimumRecordCounts: oneRecordMinimums)
        let transport = FixtureMACVendorHTTPTransport()
        let service = MACVendorDatabaseService(
            parser: parser,
            store: store,
            downloader: MACVendorDatabaseDownloader(transport: transport)
        )

        let database = try await service.download(createdAt: fixtureDate) { _ in }

        #expect(database.source == .ieeeDownload)
        #expect(try await service.load() == nil)

        try await service.install(database)

        #expect(try await service.load() == database)
    }

    @Test func manualPreparationReadsAndValidatesWithoutInstalling() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let importRoot = root.appending(path: "imports")
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        let urls = try makeCSVFixtures(in: importRoot)
        let service = MACVendorDatabaseService(
            parser: MACVendorCSVParser(minimumRecordCounts: oneRecordMinimums),
            store: MACVendorDatabaseStore(baseDirectory: root.appending(path: "store")),
            downloader: MACVendorDatabaseDownloader(transport: FixtureMACVendorHTTPTransport())
        )

        let database = try await service.prepareManualImport(urls: urls, createdAt: fixtureDate)

        #expect(database.source == .manualImport)
        #expect(try await service.load() == nil)
    }

    @Test func manualPreparationRejectsWrongFileCountBeforeReading() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MACVendorDatabaseService(
            parser: MACVendorCSVParser(minimumRecordCounts: oneRecordMinimums),
            store: MACVendorDatabaseStore(baseDirectory: root),
            downloader: MACVendorDatabaseDownloader(transport: FixtureMACVendorHTTPTransport())
        )

        do {
            _ = try await service.prepareManualImport(
                urls: [root.appending(path: "missing.csv")],
                createdAt: fixtureDate
            )
            Issue.record("Expected manual file count validation to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .wrongFileCount(expected: 4, actual: 1))
        }
    }

    @Test func manualReadFailurePreservesTypedFileNameAfterCountValidation() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MACVendorDatabaseService(
            parser: MACVendorCSVParser(minimumRecordCounts: oneRecordMinimums),
            store: MACVendorDatabaseStore(baseDirectory: root),
            downloader: MACVendorDatabaseDownloader(transport: FixtureMACVendorHTTPTransport())
        )
        let missingURLs = (0..<4).map { index in
            root.appending(path: "missing-\(index).csv")
        }

        do {
            _ = try await service.prepareManualImport(
                urls: missingURLs,
                createdAt: fixtureDate
            )
            Issue.record("Expected manual file acquisition to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .fileReadFailed("missing-0.csv"))
        }
    }

    @Test func downloadChecksCancellationAfterParsing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let parser = MACVendorCSVParser(
            minimumRecordCounts: oneRecordMinimums,
            cancellationCheck: cancelCurrentTaskAfterFinalSort
        )
        let service = MACVendorDatabaseService(
            parser: parser,
            store: MACVendorDatabaseStore(baseDirectory: root),
            downloader: MACVendorDatabaseDownloader(transport: FixtureMACVendorHTTPTransport())
        )
        let task = Task.detached {
            try await service.download(createdAt: fixtureDate) { _ in }
        }

        do {
            _ = try await task.value
            Issue.record("Expected download cancellation after parsing to be preserved")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }

    @Test func manualImportChecksCancellationAfterParsing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let importRoot = root.appending(path: "imports")
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        let urls = try makeCSVFixtures(in: importRoot)
        let parser = MACVendorCSVParser(
            minimumRecordCounts: oneRecordMinimums,
            cancellationCheck: cancelCurrentTaskAfterFinalSort
        )
        let service = MACVendorDatabaseService(
            parser: parser,
            store: MACVendorDatabaseStore(baseDirectory: root.appending(path: "store")),
            downloader: MACVendorDatabaseDownloader(transport: FixtureMACVendorHTTPTransport())
        )
        let task = Task.detached {
            try await service.prepareManualImport(urls: urls, createdAt: fixtureDate)
        }

        do {
            _ = try await task.value
            Issue.record("Expected manual import cancellation after parsing to be preserved")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }
}

private actor FakeMACVendorDatabaseService: MACVendorDatabaseServicing {
    private let loadedDatabase: MACVendorDatabase?
    private let downloadedDatabase: MACVendorDatabase
    private let preparedDatabase: MACVendorDatabase
    private let loadError: MACVendorDatabaseError?
    private let downloadError: MACVendorDatabaseError?
    private var preparationError: MACVendorDatabaseError?
    private let installError: MACVendorDatabaseError?
    private let clearError: MACVendorDatabaseError?
    private let suspendDownload: Bool
    private let suspendPreparation: Bool
    private let suspendInstall: Bool
    private var installReleased = false
    private var downloadWaiters: [CheckedContinuation<Void, Never>] = []
    private var prepareWaiters: [CheckedContinuation<Void, Never>] = []
    private var installWaiters: [CheckedContinuation<Void, Never>] = []

    private(set) var loadCallCount = 0
    private(set) var downloadCallCount = 0
    private(set) var prepareCallCount = 0
    private(set) var installCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var observedDownloadCancellation = false
    private(set) var observedPreparationCancellation = false

    init(
        loadedDatabase: MACVendorDatabase? = nil,
        downloadedDatabase: MACVendorDatabase = makeDatabase(organization: "Downloaded Name"),
        preparedDatabase: MACVendorDatabase = makeDatabase(organization: "Prepared Name"),
        loadError: MACVendorDatabaseError? = nil,
        downloadError: MACVendorDatabaseError? = nil,
        preparationError: MACVendorDatabaseError? = nil,
        installError: MACVendorDatabaseError? = nil,
        clearError: MACVendorDatabaseError? = nil,
        suspendDownload: Bool = false,
        suspendPreparation: Bool = false,
        suspendInstall: Bool = false
    ) {
        self.loadedDatabase = loadedDatabase
        self.downloadedDatabase = downloadedDatabase
        self.preparedDatabase = preparedDatabase
        self.loadError = loadError
        self.downloadError = downloadError
        self.preparationError = preparationError
        self.installError = installError
        self.clearError = clearError
        self.suspendDownload = suspendDownload
        self.suspendPreparation = suspendPreparation
        self.suspendInstall = suspendInstall
    }

    func load() async throws -> MACVendorDatabase? {
        loadCallCount += 1
        if let loadError { throw loadError }
        return loadedDatabase
    }

    func download(
        createdAt: Date,
        progress: @Sendable (Int) async -> Void
    ) async throws -> MACVendorDatabase {
        downloadCallCount += 1
        let pendingDownloadWaiters = downloadWaiters
        downloadWaiters.removeAll()
        pendingDownloadWaiters.forEach { $0.resume() }
        for completed in 1...MACVendorRegistry.allCases.count {
            await progress(completed)
        }
        do {
            while suspendDownload {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        } catch is CancellationError {
            observedDownloadCancellation = true
            throw CancellationError()
        }
        if let downloadError { throw downloadError }
        return downloadedDatabase
    }

    func prepareManualImport(urls: [URL], createdAt: Date) async throws -> MACVendorDatabase {
        prepareCallCount += 1
        let pendingPrepareWaiters = prepareWaiters
        prepareWaiters.removeAll()
        pendingPrepareWaiters.forEach { $0.resume() }
        do {
            while suspendPreparation {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(5))
            }
        } catch is CancellationError {
            observedPreparationCancellation = true
            throw CancellationError()
        }
        if let preparationError { throw preparationError }
        return preparedDatabase
    }

    func install(_ database: MACVendorDatabase) async throws {
        installCallCount += 1
        let pendingInstallWaiters = installWaiters
        installWaiters.removeAll()
        pendingInstallWaiters.forEach { $0.resume() }
        while suspendInstall, !installReleased {
            try await Task.sleep(for: .milliseconds(5))
        }
        if let installError { throw installError }
    }

    func clear() async throws {
        clearCallCount += 1
        if let clearError { throw clearError }
    }

    func releaseInstall() {
        installReleased = true
    }

    func setPreparationError(_ error: MACVendorDatabaseError?) {
        preparationError = error
    }

    func waitUntilDownloadCalled() async {
        if downloadCallCount > 0 { return }
        await withCheckedContinuation { downloadWaiters.append($0) }
    }

    func waitUntilPrepareCalled() async {
        if prepareCallCount > 0 { return }
        await withCheckedContinuation { prepareWaiters.append($0) }
    }

    func waitUntilInstallCalled() async {
        if installCallCount > 0 { return }
        await withCheckedContinuation { installWaiters.append($0) }
    }
}

private actor FixtureMACVendorHTTPTransport: MACVendorHTTPTransport {
    func fetch(
        _ request: URLRequest,
        maximumBytes: Int,
        byteBudget: MACVendorDownloadByteBudget
    ) async throws -> MACVendorHTTPResponse {
        let url = try #require(request.url)
        let registry = try #require(MACVendorRegistry.allCases.first { $0.downloadURL == url })
        let assignment: String
        switch registry {
        case .maL: assignment = "001122"
        case .maM: assignment = "0011223"
        case .maS: assignment = "001122334"
        case .iab: assignment = "001122335"
        }
        let data = Data(
            "Registry,Assignment,Organization Name\n\(registry.rawValue),\(assignment),Example\n".utf8
        )
        try byteBudget.consume(data.count)
        return MACVendorHTTPResponse(data: data, statusCode: 200, finalURL: url)
    }
}

private let testAddress = "00:11:22:33:44:55"
private let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)
private let oneRecordMinimums = Dictionary(
    uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) }
)
private let cancelCurrentTaskAfterFinalSort: @Sendable (
    MACVendorCSVParserCancellationPoint
) throws -> Void = { point in
    if point == .afterFinalSort {
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
    }
}

@MainActor
private func makeResolver(organization: String) -> MACVendorResolver {
    MACVendorResolver(entries: [
        MACVendorEntry(prefix: "001122", prefixLength: 24, organization: organization),
    ])
}

private func makeDatabase(
    organization: String,
    source: MACVendorDatabaseSource = .manualImport
) -> MACVendorDatabase {
    MACVendorDatabase(
        schemaVersion: MACVendorDatabase.schemaVersion,
        createdAt: fixtureDate,
        source: source,
        registries: MACVendorRegistry.allCases.map { registry in
            MACVendorRegistryMetadata(
                registry: registry,
                validRecordCount: 1,
                sha256: String(repeating: String(registry.rawValue.first ?? "a"), count: 64),
                sourceURL: source == .ieeeDownload ? registry.downloadURL : nil
            )
        },
        entries: [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: organization),
        ]
    )
}

private func fourFixtureURLs() -> [URL] {
    MACVendorRegistry.allCases.map { URL(fileURLWithPath: "/tmp/\($0.rawValue).csv") }
}

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeCSVFixtures(in directory: URL) throws -> [URL] {
    try MACVendorRegistry.allCases.map { registry in
        let assignment: String
        switch registry {
        case .maL: assignment = "001122"
        case .maM: assignment = "0011223"
        case .maS: assignment = "001122334"
        case .iab: assignment = "001122335"
        }
        let url = directory.appending(path: "\(registry.rawValue).csv")
        let data = Data(
            "Registry,Assignment,Organization Name\n\(registry.rawValue),\(assignment),Example\n".utf8
        )
        try data.write(to: url)
        return url
    }
}
