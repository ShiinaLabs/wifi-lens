import Foundation
import Observation

public enum MACVendorDatabaseAvailability: Equatable, Sendable {
    case loading
    case notInstalled
    case installed(MACVendorDatabaseSummary)
    case unavailable(MACVendorDatabaseError)
}

extension MACVendorDatabaseAvailability {
    public var isVendorColumnAvailable: Bool {
        if case .installed = self {
            return true
        }
        return false
    }
}

public enum MACVendorDatabaseOperation: Equatable, Sendable {
    case idle
    case downloading(completed: Int, total: Int)
    case readingFiles
    case validating
    case installing
    case clearing
}

@MainActor
@Observable
public final class MACVendorDatabaseManager {
    public struct CancellationHandle: Sendable {
        fileprivate let operationID: UUID
        fileprivate let task: Task<Void, Never>
    }

    public private(set) var availability: MACVendorDatabaseAvailability
    public private(set) var operation: MACVendorDatabaseOperation = .idle
    private var pendingManualImport: MACVendorDatabaseSummary?
    public private(set) var databaseRevision = 0
    private var processPresentedError: MACVendorDatabaseError?
    private var ownerPresentedErrors: [UUID: MACVendorDatabaseError] = [:]

    public var presentedError: MACVendorDatabaseError? {
        processPresentedError
    }

    private let resolver: MACVendorResolver
    private let service: any MACVendorDatabaseServicing
    private var preparedManualDatabase: MACVendorDatabase?
    private var preparedManualImportOwnerID: UUID?
    private var currentTask: Task<Void, Never>?
    private var currentOperationID: UUID?
    private var currentOperationOwnerID: UUID?

    public init(
        resolver: MACVendorResolver,
        service: any MACVendorDatabaseServicing,
        initialAvailability: MACVendorDatabaseAvailability = .loading
    ) {
        self.resolver = resolver
        self.service = service
        availability = initialAvailability
    }

    public func loadInstalledDatabase() async {
        guard availability == .loading else { return }
        await run(operation: .idle) { [weak self] in
            await self?.performLoad()
        }
    }

    public func downloadAndInstall(ownerID: UUID? = nil) async {
        await run(
            operation: .downloading(completed: 0, total: MACVendorRegistry.allCases.count),
            ownerID: ownerID
        ) { [weak self] in
            await self?.performDownloadAndInstall()
        }
    }

    public func prepareManualImport(urls: [URL], ownerID: UUID? = nil) async {
        guard currentTask == nil else { return }
        guard preparedManualImportOwnerID == nil || preparedManualImportOwnerID == ownerID else { return }
        preparedManualDatabase = nil
        pendingManualImport = nil
        preparedManualImportOwnerID = nil
        setPresentedError(nil, ownerID: ownerID)
        await run(operation: .readingFiles, ownerID: ownerID) { [weak self] in
            await self?.performManualPreparation(urls: urls, ownerID: ownerID)
        }
    }

    public func confirmManualImport(ownerID: UUID? = nil) async {
        guard currentTask == nil else { return }
        guard preparedManualImportOwnerID == ownerID else { return }
        guard let preparedManualDatabase else {
            setPresentedError(.noPreparedImport, ownerID: ownerID)
            return
        }

        await run(operation: .installing, ownerID: ownerID) { [weak self] in
            await self?.performInstall(preparedManualDatabase, clearsPreparedImport: true)
        }
    }

    public func discardPreparedManualImport(ownerID: UUID? = nil) {
        guard currentTask == nil || currentOperationOwnerID != ownerID else { return }
        guard preparedManualImportOwnerID == ownerID else { return }
        preparedManualDatabase = nil
        pendingManualImport = nil
        preparedManualImportOwnerID = nil
    }

    public func operation(for ownerID: UUID) -> MACVendorDatabaseOperation {
        guard currentOperationOwnerID == ownerID else { return .idle }
        return operation
    }

    public func pendingManualImport(for ownerID: UUID?) -> MACVendorDatabaseSummary? {
        guard preparedManualImportOwnerID == ownerID else { return nil }
        return pendingManualImport
    }

    public func presentedError(for ownerID: UUID) -> MACVendorDatabaseError? {
        ownerPresentedErrors[ownerID]
    }

    public func dismissPresentedError(ownerID: UUID? = nil) {
        setPresentedError(nil, ownerID: ownerID)
    }

    public func clear() async {
        await run(operation: .clearing, ownerID: nil) { [weak self] in
            await self?.performClear()
        }
    }

    @discardableResult
    public func cancelCurrentOperation(ownerID: UUID? = nil) -> CancellationHandle? {
        switch operation {
        case .downloading, .readingFiles, .validating:
            break
        case .idle, .installing, .clearing:
            return nil
        }

        guard currentOperationOwnerID == ownerID,
              let operationID = currentOperationID,
              let task = currentTask
        else {
            return nil
        }

        let handle = CancellationHandle(operationID: operationID, task: task)
        task.cancel()
        return handle
    }

    public func waitForCancellation(_ handle: CancellationHandle) async {
        await handle.task.value
        settleOperation(id: handle.operationID)
    }

    private func run(
        operation initialOperation: MACVendorDatabaseOperation,
        ownerID: UUID? = nil,
        body: @escaping @MainActor @Sendable () async -> Void
    ) async {
        guard currentTask == nil else { return }

        let operationID = UUID()
        operation = initialOperation
        let task = Task { @MainActor in
            await body()
        }
        currentOperationID = operationID
        currentOperationOwnerID = ownerID
        currentTask = task

        await task.value
        settleOperation(id: operationID)
    }

    private func settleOperation(id operationID: UUID) {
        guard currentOperationID == operationID else { return }
        currentTask = nil
        currentOperationID = nil
        currentOperationOwnerID = nil
        operation = .idle
    }

    private func performLoad() async {
        do {
            let database = try await service.load()
            if let database {
                resolver.replaceEntries(database.entries)
                availability = .installed(database.summary)
            } else {
                resolver.replaceEntries([])
                availability = .notInstalled
            }
            databaseRevision &+= 1
            setPresentedError(nil, ownerID: nil)
        } catch is CancellationError {
            return
        } catch let error as MACVendorDatabaseError {
            availability = .unavailable(error)
        } catch {
            availability = .unavailable(.persistenceFailure)
        }
    }

    private func performDownloadAndInstall() async {
        do {
            let database = try await service.download(createdAt: Date()) { [weak self] completed in
                await self?.publishDownloadProgress(completed)
            }
            try Task.checkCancellation()
            operation = .installing
            try await service.install(database)
            publishInstalled(database, clearsPreparedImport: false)
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            return
        } catch let error as MACVendorDatabaseError {
            setPresentedError(error, ownerID: currentOperationOwnerID)
        } catch {
            setPresentedError(.downloadFailed(.maL), ownerID: currentOperationOwnerID)
        }
    }

    private func publishDownloadProgress(_ completed: Int) {
        let total = MACVendorRegistry.allCases.count
        guard completed < total else {
            operation = .validating
            return
        }
        operation = .downloading(completed: max(0, completed), total: total)
    }

    private func performManualPreparation(urls: [URL], ownerID: UUID?) async {
        do {
            let database = try await service.prepareManualImport(urls: urls, createdAt: Date())
            try Task.checkCancellation()
            preparedManualDatabase = database
            pendingManualImport = database.summary
            preparedManualImportOwnerID = ownerID
            setPresentedError(nil, ownerID: ownerID)
        } catch is CancellationError {
            return
        } catch where Task.isCancelled {
            return
        } catch let error as MACVendorDatabaseError {
            setPresentedError(error, ownerID: ownerID)
        } catch {
            setPresentedError(
                .fileReadFailed(urls.first?.lastPathComponent ?? ""),
                ownerID: ownerID
            )
        }
    }

    private func performInstall(
        _ database: MACVendorDatabase,
        clearsPreparedImport: Bool
    ) async {
        do {
            try await service.install(database)
            publishInstalled(database, clearsPreparedImport: clearsPreparedImport)
        } catch let error as MACVendorDatabaseError {
            setPresentedError(error, ownerID: currentOperationOwnerID)
        } catch {
            setPresentedError(.persistenceFailure, ownerID: currentOperationOwnerID)
        }
    }

    private func publishInstalled(
        _ database: MACVendorDatabase,
        clearsPreparedImport: Bool
    ) {
        resolver.replaceEntries(database.entries)
        availability = .installed(database.summary)
        if clearsPreparedImport {
            preparedManualDatabase = nil
            pendingManualImport = nil
            preparedManualImportOwnerID = nil
        }
        databaseRevision &+= 1
        setPresentedError(nil, ownerID: currentOperationOwnerID)
    }

    private func performClear() async {
        do {
            try await service.clear()
            resolver.replaceEntries([])
            availability = .notInstalled
            preparedManualDatabase = nil
            pendingManualImport = nil
            preparedManualImportOwnerID = nil
            databaseRevision &+= 1
            setPresentedError(nil, ownerID: nil)
        } catch let error as MACVendorDatabaseError {
            setPresentedError(error, ownerID: nil)
        } catch {
            setPresentedError(.persistenceFailure, ownerID: nil)
        }
    }

    private func setPresentedError(
        _ error: MACVendorDatabaseError?,
        ownerID: UUID?
    ) {
        if let ownerID {
            ownerPresentedErrors[ownerID] = error
        } else {
            processPresentedError = error
        }
    }
}
