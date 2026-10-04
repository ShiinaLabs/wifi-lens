import Foundation

/// The canonical locations used by WiFi Lens persistent storage.
///
/// Runtime-specific namespaces come from ``AppEnvironment.storageNamespace`` so
/// Production, Development, and Capture retain their configured isolation.
public struct StorageLocations: Sendable {
    public let applicationSupportRoot: URL

    public let observationDatabase: URL
    public let logs: URL
    public let crashLogs: URL
    public let metrics: URL
    public let macVendorDatabase: URL

    public let cachesRoot: URL

    public let migrationBackup: URL
    public let contractMarker: URL

    public init(
        environment: AppEnvironment,
        applicationSupportDirectory: URL,
        cachesDirectory: URL
    ) {
        let root = applicationSupportDirectory.appendingPathComponent(
            environment.storageNamespace,
            isDirectory: true
        )
        applicationSupportRoot = root
        observationDatabase = root.appendingPathComponent(
            "wifi_observation_events.sqlite",
            isDirectory: false
        )
        logs = root.appendingPathComponent("Logs", isDirectory: true)
        crashLogs = root.appendingPathComponent("CrashLogs", isDirectory: true)
        metrics = root.appendingPathComponent("Metrics", isDirectory: true)
        macVendorDatabase = root.appendingPathComponent("MACVendorDatabase", isDirectory: true)
        cachesRoot = cachesDirectory.appendingPathComponent(
            environment.storageNamespace,
            isDirectory: true
        )
        migrationBackup = root.appendingPathComponent("MigrationBackup", isDirectory: true)
        contractMarker = root.appendingPathComponent(".storage-contract.json", isDirectory: false)
    }

    public static let current: StorageLocations = {
        let fileManager = FileManager.default
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let cachesDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return StorageLocations(
            environment: .current,
            applicationSupportDirectory: applicationSupportDirectory,
            cachesDirectory: cachesDirectory
        )
    }()
}
