import Foundation
import Testing

@testable import WiFiLensCore

struct OpenSourceLicenseCatalogTests {
    @Test func componentIdentifiersAreUnique() {
        let identifiers = OpenSourceLicenseCatalog.components.map(\.id)

        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func openSourceEditionListsLinkedComponentsInOrder() {
        let identifiers = OpenSourceLicenseCatalog.components(for: .openSource).map(\.id)

        #expect(
            identifiers == [
                "chart-lens",
                "eventsource",
                "markdownkit",
                "swift-sdk",
                "sparkle",
                "splitview",
                "swift-system",
                "swift-log",
            ])
    }

    @Test func proEditionListsLinkedComponentsInOrder() {
        let identifiers = OpenSourceLicenseCatalog.components(for: .pro).map(\.id)

        #expect(
            identifiers == [
                "chart-lens",
                "eventsource",
                "grdb.swift",
                "hdrhistogram-swift",
                "markdownkit",
                "swift-sdk",
                "splitview",
                "swift-numerics",
                "swift-system",
                "swift-log",
            ])
    }

    @Test func everyComponentCarriesDisplayMetadataAndALicense() {
        for component in OpenSourceLicenseCatalog.components {
            #expect(!component.name.isEmpty)
            #expect(!component.version.isEmpty)
            #expect(!component.licenses.isEmpty)
            #expect(!component.editions.isEmpty)
            #expect(component.repositoryURL != nil)
        }
    }

    @Test func licenseTextsAreAvailable() {
        for license in OpenSourceLicense.allCases {
            #expect(!license.text.isEmpty)
        }

        #expect(OpenSourceLicense.apache2.text.contains("Apache License"))
        #expect(OpenSourceLicense.mit.text.contains("Permission is hereby granted"))
        #expect(OpenSourceLicense.bsd2.text.contains("Redistribution and use"))
        #expect(OpenSourceLicense.zlib.text.contains("provided 'as-is'"))
    }

    @Test func requiredNoticesAccompanyTheirComponents() {
        let components = Dictionary(
            uniqueKeysWithValues: OpenSourceLicenseCatalog.components.map { ($0.id, $0) })

        #expect(components["swift-log"]?.additionalNotices.contains { $0.contains("SwiftLog") } == true)
        #expect(components["sparkle"]?.additionalNotices.contains { $0.contains("EXTERNAL LICENSES") } == true)
    }

    @Test func ieeeVendorDatabaseIsDisclosedAsADataSource() {
        let source = OpenSourceLicenseCatalog.dataSources.first { $0.id == "ieee-mac-vendor" }

        #expect(source?.provider == "IEEE Registration Authority")
        #expect(source?.url != nil)
        #expect(source?.note.contains("does not endorse WiFi Lens") == true)
    }
}
