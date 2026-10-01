import Foundation

public enum MACVendorRegistry: String, CaseIterable, Codable, Hashable, Sendable {
    case maL = "MA-L"
    case maM = "MA-M"
    case maS = "MA-S"
    case iab = "IAB"

    public var prefixLength: Int {
        switch self {
        case .maL: 24
        case .maM: 28
        case .maS, .iab: 36
        }
    }

    public var downloadURL: URL {
        switch self {
        case .maL: URL(string: "https://standards-oui.ieee.org/oui/oui.csv")!
        case .maM: URL(string: "https://standards-oui.ieee.org/oui28/mam.csv")!
        case .maS: URL(string: "https://standards-oui.ieee.org/oui36/oui36.csv")!
        case .iab: URL(string: "https://standards-oui.ieee.org/iab/iab.csv")!
        }
    }
}

public enum MACVendorDatabaseSource: String, Codable, Equatable, Sendable {
    case ieeeDownload
    case manualImport
}

public struct MACVendorRegistryInput: Sendable {
    public let displayName: String
    public let data: Data

    public init(displayName: String, data: Data) {
        self.displayName = displayName
        self.data = data
    }
}

public struct MACVendorRegistryMetadata: Codable, Equatable, Sendable {
    public let registry: MACVendorRegistry
    public let validRecordCount: Int
    public let sha256: String
    public let sourceURL: URL?

    public init(registry: MACVendorRegistry, validRecordCount: Int, sha256: String, sourceURL: URL?) {
        self.registry = registry
        self.validRecordCount = validRecordCount
        self.sha256 = sha256
        self.sourceURL = sourceURL
    }
}

public struct MACVendorEntry: Codable, Equatable, Sendable {
    public let prefix: String
    public let prefixLength: Int
    public let organization: String

    public init(prefix: String, prefixLength: Int, organization: String) {
        self.prefix = prefix
        self.prefixLength = prefixLength
        self.organization = organization
    }
}

public struct MACVendorDatabase: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let schemaVersion: Int
    public let createdAt: Date
    public let source: MACVendorDatabaseSource
    public let registries: [MACVendorRegistryMetadata]
    public let entries: [MACVendorEntry]

    public init(schemaVersion: Int, createdAt: Date, source: MACVendorDatabaseSource, registries: [MACVendorRegistryMetadata], entries: [MACVendorEntry]) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.source = source
        self.registries = registries
        self.entries = entries
    }

    public var summary: MACVendorDatabaseSummary {
        MACVendorDatabaseSummary(
            source: source,
            createdAt: createdAt,
            registryCounts: Dictionary(uniqueKeysWithValues: registries.map { ($0.registry, $0.validRecordCount) }),
            totalRecordCount: entries.count
        )
    }
}

public struct MACVendorDatabaseSummary: Equatable, Sendable {
    public let source: MACVendorDatabaseSource
    public let createdAt: Date
    public let registryCounts: [MACVendorRegistry: Int]
    public let totalRecordCount: Int

    public init(source: MACVendorDatabaseSource, createdAt: Date, registryCounts: [MACVendorRegistry: Int], totalRecordCount: Int) {
        self.source = source
        self.createdAt = createdAt
        self.registryCounts = registryCounts
        self.totalRecordCount = totalRecordCount
    }
}

public enum MACVendorDatabaseError: Error, Equatable, Sendable {
    case wrongFileCount(expected: Int, actual: Int)
    case fileTooLarge(file: String, maximumBytes: Int)
    case totalSizeExceeded(maximumBytes: Int)
    case invalidEncoding(file: String)
    case malformedCSV(file: String)
    case missingColumns(file: String, columns: [String])
    case mixedRegistries(file: String)
    case duplicateRegistry(MACVendorRegistry)
    case missingRegistry(MACVendorRegistry)
    case invalidAssignment(file: String, registry: MACVendorRegistry, assignment: String)
    case invalidOrganization(file: String)
    case tooFewRecords(registry: MACVendorRegistry, minimum: Int, actual: Int)
    case conflictingAssignment(prefix: String, prefixLength: Int)
    case invalidHTTPStatus(registry: MACVendorRegistry, statusCode: Int)
    case disallowedRedirect(URL)
    case downloadFailed(MACVendorRegistry)
    case automaticDownloadFailed
    case fileReadFailed(String)
    case unsupportedSchema(Int)
    case persistenceFailure
    case noPreparedImport
}
