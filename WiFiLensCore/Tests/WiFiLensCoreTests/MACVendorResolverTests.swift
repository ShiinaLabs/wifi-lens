import Foundation
import Observation
import Testing
@testable import WiFiLensCore
@MainActor
struct MACVendorResolverTests {
    private func makeResolver() -> MACVendorResolver {
        MACVendorResolver(entries: [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "Large Networks"),
            MACVendorEntry(prefix: "0011223", prefixLength: 28, organization: "Medium Networks"),
            MACVendorEntry(prefix: "001122334", prefixLength: 36, organization: "Small Networks"),
        ])
    }

    @Test func usesLongestMatchingPrefix() {
        let resolver = makeResolver()

        #expect(resolver.resolve("00:11:22:33:44:55") == .registered("Small Networks"))
        #expect(resolver.resolve("00:11:22:3f:44:55") == .registered("Medium Networks"))
        #expect(resolver.resolve("00:11:22:ff:44:55") == .registered("Large Networks"))
    }

    @Test func acceptsCommonMACAddressFormats() {
        let resolver = makeResolver()

        #expect(resolver.resolve("00:11:22:33:44:55") == .registered("Small Networks"))
        #expect(resolver.resolve("00-11-22-33-44-55") == .registered("Small Networks"))
        #expect(resolver.resolve("001122334455") == .registered("Small Networks"))
    }

    @Test func rejectsGroupAndNullAddressesBeforeLookup() {
        let resolver = MACVendorResolver(entries: [
            MACVendorEntry(prefix: "000000", prefixLength: 24, organization: "XEROX CORPORATION"),
            MACVendorEntry(prefix: "011122", prefixLength: 24, organization: "Group Mapping"),
            MACVendorEntry(prefix: "FFFFFF", prefixLength: 24, organization: "Broadcast Mapping"),
        ])

        #expect(resolver.resolve("00:00:00:00:00:00") == .invalid)
        #expect(resolver.resolve("01:11:22:33:44:55") == .invalid)
        #expect(resolver.resolve("ff:ff:ff:ff:ff:ff") == .invalid)
    }

    @Test func missingBundledDatabaseFallsBackToUnknown() {
        let resolver = MACVendorResolver(database: nil)

        #expect(resolver.resolve("00:03:93:00:00:00") == .unknown)
    }

    @Test func bundledDatabasePreservesSnapshotDateAndEntries() throws {
        let data = try #require(
            """
            {"schemaVersion":1,"retrievedAt":"2026-07-31","sourceUpdatedAt":"2026-07-30","sources":[],"ambiguousPrefixCount":0,"notice":"","entries":[{"prefix":"001122","prefixLength":24,"organization":"Example Networks"}]}
            """.data(using: .utf8)
        )
        let database = try JSONDecoder().decode(MACVendorBundledDatabase.self, from: data)
        let resolver = MACVendorResolver(database: database)

        #expect(database.retrievedAt == "2026-07-31")
        #expect(database.sourceUpdatedAt == "2026-07-30")
        #expect(database.totalRecordCount == 1)
        #expect(database.summary.sourceUpdatedAt == "2026-07-30")
        #expect(database.summary.totalRecordCount == 1)
        #expect(resolver.resolve("00:11:22:33:44:55") == .registered("Example Networks"))
    }

    @Test func replacingEntriesClearsCachedResults() {
        let resolver = MACVendorResolver(entries: [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "Old Name"),
        ])
        #expect(resolver.resolve("00:11:22:33:44:55") == .registered("Old Name"))

        resolver.replaceEntries([
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "New Name"),
        ])

        #expect(resolver.resolve("00:11:22:33:44:55") == .registered("New Name"))
    }

    @Test func locallyAdministeredAddressesDoNotUseRegistryMappings() {
        let resolver = MACVendorResolver(entries: [
            MACVendorEntry(prefix: "021122", prefixLength: 24, organization: "Should Not Match"),
        ])

        #expect(resolver.resolve("02:11:22:33:44:55") == .locallyAdministered)
    }

    @Test func distinguishesUnknownFromInvalidAddresses() {
        let resolver = makeResolver()

        #expect(resolver.resolve("10:20:30:40:50:60") == .unknown)
        #expect(resolver.resolve("not-a-mac") == .invalid)
        #expect(resolver.resolve("00:11:22:33:44") == .invalid)
        #expect(resolver.resolve("00x11x22x33x44x55") == .invalid)
        #expect(resolver.resolve("00:11-22:33:44:55") == .invalid)
    }

    @Test func unsupportedDatabaseSchemaFallsBackToAnEmptyDatabase() throws {
        let data = try #require(
            """
            {"schemaVersion":2,"createdAt":0,"source":"manualImport","registries":[],"entries":[{"prefix":"001122","prefixLength":24,"organization":"Example"}]}
            """.data(using: .utf8)
        )
        let resolver = MACVendorResolver(databaseData: data)

        #expect(resolver.resolve("00:11:22:33:44:55") == .unknown)
    }

    @Test func scannerProjectsRegisteredVendorIntoTableRows() {
        let resolver = MACVendorResolver(entries: [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "Example Networks"),
        ])
        let viewModel = ScannerViewModel(vendorResolver: resolver)
        let network = WiFiNetwork(
            ssid: "TestWiFi",
            bssid: "00:11:22:33:44:55",
            rssi: -50,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 44)
        )

        viewModel.debugApplyNetworksForTesting([network], supportedBands: [.band5GHz])

        #expect(viewModel.combinedTableRows.first?.vendor == "Example Networks")
    }

    @Test func scannerLeavesVendorBlankForNonRegisteredAddresses() {
        let viewModel = ScannerViewModel(vendorResolver: MACVendorResolver(entries: []))
        let unknown = WiFiNetwork(
            ssid: "Unknown",
            bssid: "10:20:30:40:50:60",
            rssi: -50,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 44)
        )

        viewModel.debugApplyNetworksForTesting([unknown], supportedBands: [.band5GHz])

        #expect(viewModel.combinedTableRows.first?.vendor == "")
    }

    @Test func scannerRefreshSeamReprojectsExistingRowsWithoutAnotherScan() async {
        let resolver = MACVendorResolver(entries: [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "Old Name"),
        ])
        let viewModel = ScannerViewModel(vendorResolver: resolver)
        let network = WiFiNetwork(
            ssid: "TestWiFi",
            bssid: "00:11:22:33:44:55",
            rssi: -50,
            channel: WiFiChannel(band: .band5GHz, channelNumber: 44)
        )
        viewModel.debugApplyNetworksForTesting([network], supportedBands: [.band5GHz])
        let initialRevision = viewModel.vendorDatabaseRevision

        await confirmation("Combined table rows invalidated", expectedCount: 1) { invalidated in
            withObservationTracking {
                _ = viewModel.combinedTableRows
            } onChange: {
                invalidated()
            }

            resolver.replaceEntries([
                MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "New Name"),
            ])
            viewModel.vendorDatabaseDidChange()
        }

        #expect(viewModel.vendorDatabaseRevision == initialRevision + 1)
        #expect(viewModel.combinedTableRows.first?.vendor == "New Name")
    }
}
