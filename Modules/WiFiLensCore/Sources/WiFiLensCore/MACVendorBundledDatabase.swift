import Foundation
import Logging

public struct MACVendorBundledDatabaseSummary: Equatable, Sendable {
    public let sourceUpdatedAt: String
    public let sourceUpdatedDate: Date?
    public let totalRecordCount: Int

    public var legacyDatabaseSummary: MACVendorDatabaseSummary {
        MACVendorDatabaseSummary(
            source: .ieeeDownload,
            createdAt: sourceUpdatedDate ?? .distantPast,
            registryCounts: [:],
            totalRecordCount: totalRecordCount
        )
    }
}

public struct MACVendorBundledDatabase: Decodable, Equatable, Sendable {
    private static let logger = Logger(label: "scanner")
    struct Source: Decodable, Equatable, Sendable {
        let url: String
        let lastModifiedAt: String?
    }

    public let schemaVersion: Int
    let retrievedAt: String
    let sourceUpdatedAt: String
    let sources: [Source]
    public let entries: [MACVendorEntry]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case retrievedAt
        case sourceUpdatedAt
        case sources
        case entries
    }

    public var totalRecordCount: Int { entries.count }

    public var sourceUpdatedDate: Date? {
        ISO8601DateFormatter().date(from: sourceUpdatedAt)
    }

    public var summary: MACVendorBundledDatabaseSummary {
        MACVendorBundledDatabaseSummary(
            sourceUpdatedAt: sourceUpdatedAt,
            sourceUpdatedDate: sourceUpdatedDate,
            totalRecordCount: totalRecordCount
        )
    }

    public static func load(from bundle: Bundle = .main) -> MACVendorBundledDatabase? {
        guard let url = bundle.url(forResource: "mac-vendor-database", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            logger.warning("Bundled MAC vendor database resource is unavailable")
            return nil
        }

        do {
            let database = try JSONDecoder().decode(Self.self, from: data)
            guard database.schemaVersion == 1 else {
                logger.warning(
                    "Unsupported bundled MAC vendor database schema: \(database.schemaVersion)"
                )
                return nil
            }
            return database
        } catch {
            logger.error("Failed to decode bundled MAC vendor database: \(error)")
            return nil
        }
    }
}
