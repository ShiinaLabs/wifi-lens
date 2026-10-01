import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct MACVendorDatabaseStoreTests {
    @Test func missingFileLoadsAsNil() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)

        #expect(try await store.load() == nil)
    }

    @Test func replacesAndLoadsDatabase() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)
        let database = makeDatabase(organization: "Example Networks")

        try await store.replace(with: database)

        #expect(try await store.load() == database)
    }

    @Test func replacesExistingDatabase() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)
        let oldDatabase = makeDatabase(organization: "Old Networks")
        let newDatabase = makeDatabase(organization: "New Networks")

        try await store.replace(with: oldDatabase)
        try await store.replace(with: newDatabase)

        #expect(try await store.load() == newDatabase)
    }

    @Test func clearRemovesInstalledDatabaseAndIsIdempotent() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)
        try await store.replace(with: makeDatabase())

        try await store.clear()
        try await store.clear()

        #expect(try await store.load() == nil)
    }

    @Test func clearRemovesPendingDatabaseWhenInstalledDatabaseIsMissing() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pendingURL = root.appending(path: "database-v1.json.pending")
        try Data("interrupted installation".utf8).write(to: pendingURL)
        let store = MACVendorDatabaseStore(baseDirectory: root)

        try await store.clear()

        #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
    }

    @Test func corruptJSONFailsWithoutDeletingInstalledFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "database-v1.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: databaseURL)
        let store = MACVendorDatabaseStore(baseDirectory: root)

        do {
            _ = try await store.load()
            Issue.record("Expected corrupt JSON to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .persistenceFailure)
        }

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(try Data(contentsOf: databaseURL) == corruptData)
    }

    @Test func unsupportedSchemaFailsWithoutDeletingInstalledFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "database-v1.json")
        let installedData = Data(
            #"{"futureDatabase":{"format":"v2"},"schemaVersion":2}"#.utf8
        )
        try installedData.write(to: databaseURL)
        let store = MACVendorDatabaseStore(baseDirectory: root)

        do {
            _ = try await store.load()
            Issue.record("Expected schema version 2 to be rejected")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .unsupportedSchema(2))
        }

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(try Data(contentsOf: databaseURL) == installedData)
    }

    @Test func missingSchemaVersionIsPersistenceFailureWithoutDeletingInstalledFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appending(path: "database-v1.json")
        let installedData = Data(#"{"futureDatabase":{"format":"unknown"}}"#.utf8)
        try installedData.write(to: databaseURL)
        let store = MACVendorDatabaseStore(baseDirectory: root)

        do {
            _ = try await store.load()
            Issue.record("Expected the missing schema version to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .persistenceFailure)
        }

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(try Data(contentsOf: databaseURL) == installedData)
    }

    @Test func failedCommitPreservesInstalledDatabaseAndRemovesPendingFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let oldDatabase = makeDatabase(organization: "Installed Networks")
        let replacement = makeDatabase(organization: "Replacement Networks")
        let initialStore = MACVendorDatabaseStore(baseDirectory: root)
        try await initialStore.replace(with: oldDatabase)
        let failingStore = MACVendorDatabaseStore(
            baseDirectory: root,
            commitPendingFile: { pendingURL, _ in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                _ = try decoder.decode(MACVendorDatabase.self, from: Data(contentsOf: pendingURL))
                throw MACVendorDatabaseError.persistenceFailure
            }
        )

        do {
            try await failingStore.replace(with: replacement)
            Issue.record("Expected the injected commit to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .persistenceFailure)
        }

        #expect(try await failingStore.load() == oldDatabase)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "database-v1.json.pending").path))
    }

    @Test func directoryCreationFailureIsReportedAndLeavesBaseFileUntouched() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseFile = root.appending(path: "not-a-directory")
        let originalData = Data("base-file".utf8)
        try originalData.write(to: baseFile)
        let store = MACVendorDatabaseStore(baseDirectory: baseFile)

        do {
            try await store.replace(with: makeDatabase())
            Issue.record("Expected directory creation to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .persistenceFailure)
        }

        #expect(try Data(contentsOf: baseFile) == originalData)
    }

    @Test func persistedJSONUsesISO8601DatesAndSortedKeys() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)
        try await store.replace(with: makeDatabase())

        let data = try Data(contentsOf: root.appending(path: "database-v1.json"))
        let json = try #require(String(data: data, encoding: .utf8))
        let createdAtIndex = try #require(json.range(of: "\"createdAt\"")?.lowerBound)
        let entriesIndex = try #require(json.range(of: "\"entries\"")?.lowerBound)
        let registriesIndex = try #require(json.range(of: "\"registries\"")?.lowerBound)
        let schemaVersionIndex = try #require(json.range(of: "\"schemaVersion\"")?.lowerBound)
        let sourceIndex = try #require(json.range(of: "\"source\"")?.lowerBound)

        #expect(json.contains("\"createdAt\":\"2023-11-14T22:13:20Z\""))
        #expect(createdAtIndex < entriesIndex)
        #expect(entriesIndex < registriesIndex)
        #expect(registriesIndex < schemaVersionIndex)
        #expect(schemaVersionIndex < sourceIndex)
    }

    @Test func readsImportFilesIntoMemoryInInputOrder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appending(path: "first.csv")
        let secondURL = root.appending(path: "second.csv")
        let firstData = Data("first".utf8)
        let secondData = Data("second".utf8)
        try firstData.write(to: firstURL)
        try secondData.write(to: secondURL)
        let store = MACVendorDatabaseStore(baseDirectory: root.appending(path: "store"))

        let inputs = try await store.readImportFiles([secondURL, firstURL])

        #expect(inputs.map(\.displayName) == ["second.csv", "first.csv"])
        #expect(inputs.map(\.data) == [secondData, firstData])
    }

    @Test func importReadRejectsFileOverAcquisitionLimit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let importURL = root.appending(path: "large.csv")
        try Data(repeating: 0x41, count: 9).write(to: importURL)
        let store = MACVendorDatabaseStore(baseDirectory: root.appending(path: "store"))

        do {
            _ = try await store.readImportFiles(
                [importURL],
                maximumFileBytes: 8,
                maximumTotalBytes: 16
            )
            Issue.record("Expected the acquisition-time file limit to reject the import")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .fileTooLarge(file: "large.csv", maximumBytes: 8))
        } catch {
            Issue.record("Unexpected import-size error: \(error)")
        }
    }

    @Test func importReadRejectsAggregateSizeDuringAcquisition() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstURL = root.appending(path: "first.csv")
        let secondURL = root.appending(path: "second.csv")
        try Data(repeating: 0x41, count: 5).write(to: firstURL)
        try Data(repeating: 0x42, count: 5).write(to: secondURL)
        let store = MACVendorDatabaseStore(baseDirectory: root.appending(path: "store"))

        do {
            _ = try await store.readImportFiles(
                [firstURL, secondURL],
                maximumFileBytes: 8,
                maximumTotalBytes: 9
            )
            Issue.record("Expected the acquisition-time total limit to reject the import")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .totalSizeExceeded(maximumBytes: 9))
        } catch {
            Issue.record("Unexpected aggregate import-size error: \(error)")
        }
    }

    @Test func importReadFailureUsesDisplayName() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MACVendorDatabaseStore(baseDirectory: root)

        do {
            _ = try await store.readImportFiles([root.appending(path: "missing.csv")])
            Issue.record("Expected the missing import file to fail")
        } catch let error as MACVendorDatabaseError {
            #expect(error == .fileReadFailed("missing.csv"))
        }
    }

    @Test func cancelledImportReadPreservesCancellationError() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let importURL = root.appending(path: "import.csv")
        try Data("contents".utf8).write(to: importURL)
        let store = MACVendorDatabaseStore(baseDirectory: root.appending(path: "store"))

        let task = Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try await store.readImportFiles([importURL])
        }

        do {
            _ = try await task.value
            Issue.record("Expected import cancellation to be preserved")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDatabase(
        schemaVersion: Int = MACVendorDatabase.schemaVersion,
        organization: String = "Example Networks"
    ) -> MACVendorDatabase {
        MACVendorDatabase(
            schemaVersion: schemaVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .manualImport,
            registries: [
                MACVendorRegistryMetadata(
                    registry: .maL,
                    validRecordCount: 1,
                    sha256: String(repeating: "a", count: 64),
                    sourceURL: nil
                ),
            ],
            entries: [
                MACVendorEntry(prefix: "001122", prefixLength: 24, organization: organization),
            ]
        )
    }
}
