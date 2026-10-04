import Foundation
import Testing
@testable import WiFiLensCore

struct StorageLocationsTests {
    @Test func resolvesProductionLocations() {
        assertLocations(kind: .production, namespace: "WiFiLens")
    }

    @Test func resolvesDevelopmentLocations() {
        assertLocations(kind: .development, namespace: "WiFiLens-Dev")
    }

    @Test func resolvesCaptureLocations() {
        assertLocations(kind: .capture, namespace: "WiFiLens-Pro-Capture")
    }

    private func assertLocations(kind: AppEnvironment.Kind, namespace: String) {
        let environment = AppEnvironment(
            environmentValue: kind.rawValue,
            bundleIdentity: "com.example.wifi-lens",
            displayName: "WiFi Lens",
            storageNamespace: namespace,
            defaultMCPPort: 19840,
            mcpServerName: "wifi-lens"
        )
        let applicationSupport = URL(fileURLWithPath: "/tmp/storage-tests/Application Support")
        let caches = URL(fileURLWithPath: "/tmp/storage-tests/Caches")

        let locations = StorageLocations(
            environment: environment,
            applicationSupportDirectory: applicationSupport,
            cachesDirectory: caches
        )

        let root = applicationSupport.appendingPathComponent(namespace, isDirectory: true)
        #expect(locations.applicationSupportRoot == root)
        #expect(locations.observationDatabase == root.appendingPathComponent("wifi_observation_events.sqlite"))
        #expect(locations.logs == root.appendingPathComponent("Logs", isDirectory: true))
        #expect(locations.crashLogs == root.appendingPathComponent("CrashLogs", isDirectory: true))
        #expect(locations.metrics == root.appendingPathComponent("Metrics", isDirectory: true))
        #expect(locations.macVendorDatabase == root.appendingPathComponent("MACVendorDatabase", isDirectory: true))
        #expect(locations.cachesRoot == caches.appendingPathComponent(namespace, isDirectory: true))
        #expect(locations.migrationBackup == root.appendingPathComponent("MigrationBackup", isDirectory: true))
        #expect(locations.contractMarker == root.appendingPathComponent(".storage-contract.json"))
    }
}
