import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

struct MACVendorCSVParserTests {
    private let parser = MACVendorCSVParser(
        minimumRecordCounts: Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) })
    )

    private func input(
        name: String,
        registry: MACVendorRegistry,
        assignment: String,
        organization: String = "Example, Inc."
    ) -> MACVendorRegistryInput {
        let csv = "Registry,Assignment,Organization Name\n\(registry.rawValue),\(assignment),\"\(organization)\"\n"
        return MACVendorRegistryInput(displayName: name, data: Data(csv.utf8))
    }

    private func assignment(for registry: MACVendorRegistry) -> String {
        switch registry {
        case .maL: "001122"
        case .maM: "0011223"
        case .maS: "001122334"
        case .iab: "001122335"
        }
    }

    private func completeInputs() -> [MACVendorRegistryInput] {
        MACVendorRegistry.allCases.map { registry in
            input(
                name: "\(registry.rawValue).csv",
                registry: registry,
                assignment: assignment(for: registry)
            )
        }
    }

    @Test func parsesOneCompleteRegistrySetAndOrdersLongestPrefixFirst() throws {
        let database = try parser.parse(
            inputs: [
                input(name: "large.csv", registry: .maL, assignment: "001122"),
                input(name: "medium.csv", registry: .maM, assignment: "0011223"),
                input(name: "small.csv", registry: .maS, assignment: "001122334"),
                input(name: "iab.csv", registry: .iab, assignment: "001122335"),
            ],
            source: .manualImport,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(database.entries.map(\.prefixLength) == [36, 36, 28, 24])
        #expect(database.registries.map(\.registry) == MACVendorRegistry.allCases)
        #expect(database.registries.allSatisfy { $0.validRecordCount == 1 })
    }

    @Test func acceptsBOMQuotedCommasAndUnicode() throws {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data("\u{FEFF}Registry,Assignment,Organization Name\r\nMA-L,001122,\"株式会社 Example, Inc.\"\r\n".utf8)
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.organization == "株式会社 Example, Inc." })
    }

    @Test func rejectsMissingAndDuplicateRegistries() {
        let large = input(name: "large.csv", registry: .maL, assignment: "001122")
        let medium = input(name: "medium.csv", registry: .maM, assignment: "0011223")
        let small = input(name: "small.csv", registry: .maS, assignment: "001122334")

        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: [large, medium, small], source: .manualImport, createdAt: .distantPast)
        }
        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: [large, large, medium, small], source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsMissingOrganizationHeader() {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data("Registry,Assignment,Organization\nMA-L,001122,Example\n".utf8)
        )
        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsAssignmentWithWrongBitLength() {
        var inputs = completeInputs()
        inputs[1] = input(name: "medium.csv", registry: .maM, assignment: "001122")
        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsNonASCIIHexAssignment() {
        var inputs = completeInputs()
        inputs[0] = input(name: "large.csv", registry: .maL, assignment: "００１１２２")

        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func omitsAssignmentWithConflictingOrganizations() throws {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data(
                "Registry,Assignment,Organization Name\nMA-L,001122,First\nMA-L,001122,Second\nMA-L,001123,Stable\n".utf8
            )
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)

        #expect(!database.entries.contains { $0.prefix == "001122" })
        #expect(database.entries.contains { $0.prefix == "001123" && $0.organization == "Stable" })
    }

    @Test func rejectsControlCharactersInOrganization() {
        var inputs = completeInputs()
        inputs[0] = input(
            name: "large.csv",
            registry: .maL,
            assignment: "001122",
            organization: "Bad\u{0001}Name"
        )
        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func removesIEEEFormatCharactersBeforeParsing() throws {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "oui.csv",
            data: Data(
                "Registry,Assignment,Organization Name,Organization Address\nMA-L,48BCA6,\"\u{200B}ASUNG TECHNO CO.,Ltd\",\"\u{200C}Room 1\"\n".utf8
            )
        )

        let database = try parser.parse(
            inputs: inputs,
            source: .ieeeDownload,
            createdAt: .distantPast
        )

        #expect(database.entries.contains {
            $0.prefix == "48BCA6" && $0.organization == "ASUNG TECHNO CO.,Ltd"
        })
    }

    @Test func rejectsOversizedInputBeforeParsing() {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(repeating: 0x41, count: 65))
        let sizeLimitedParser = MACVendorCSVParser(
            minimumRecordCounts: Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) }),
            maximumFileBytes: 64,
            maximumTotalBytes: 256
        )
        #expect(throws: MACVendorDatabaseError.self) {
            try sizeLimitedParser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func decodesSupportedNamedAndNumericEntities() throws {
        var inputs = completeInputs()
        inputs[0] = input(
            name: "large.csv",
            registry: .maL,
            assignment: "001122",
            organization: "A &amp; B &#233; &#x00E9; &lt;Corp&gt; &quot;Q&quot; &#39;S&#39;"
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.organization == "A & B é é <Corp> \"Q\" 'S'" })
    }

    @Test func decodesEntityAfterRawAmpersand() throws {
        var inputs = completeInputs()
        inputs[0] = input(
            name: "large.csv",
            registry: .maL,
            assignment: "001122",
            organization: "R&D &amp; Labs"
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.organization == "R&D & Labs" })
    }

    @Test func preservesManyRawAmpersandsWithBoundedEntityScanning() throws {
        let rawPrefix = String(repeating: "&", count: 220) + ";"
        let organization = rawPrefix + " &amp; Labs"
        var inputs = completeInputs()
        inputs[0] = input(
            name: "large.csv",
            registry: .maL,
            assignment: "001122",
            organization: organization
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        let parsedOrganization = try #require(
            database.entries.first { $0.prefix == "001122" && $0.prefixLength == 24 }
        ).organization
        #expect(parsedOrganization == rawPrefix + " & Labs")
        #expect(parsedOrganization.unicodeScalars.count < 256)

        let baselineOrganization = String(repeating: "A", count: 220) + "; & Labs"
        var baselineInputs = completeInputs()
        baselineInputs[0] = input(
            name: "large.csv",
            registry: .maL,
            assignment: "001122",
            organization: baselineOrganization
        )

        let clock = ContinuousClock()
        let baselineDuration = try clock.measure {
            for _ in 0..<500 {
                _ = try parser.parse(inputs: baselineInputs, source: .manualImport, createdAt: .distantPast)
            }
        }
        let rawAmpersandDuration = try clock.measure {
            for _ in 0..<500 {
                _ = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
            }
        }
        #expect(rawAmpersandDuration < baselineDuration * 2)
    }

    @Test func acceptsAssignmentSeparators() throws {
        var inputs = completeInputs()
        inputs[0] = input(name: "large.csv", registry: .maL, assignment: "00:11:22")
        inputs[1] = input(name: "medium.csv", registry: .maM, assignment: "00-11-223")

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.prefix == "001122" && $0.prefixLength == 24 })
        #expect(database.entries.contains { $0.prefix == "0011223" && $0.prefixLength == 28 })
    }

    @Test func collapsesIdenticalDuplicateAssignments() throws {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data("Registry,Assignment,Organization Name\nMA-L,001122,Example\nMA-L,001122,Example\n".utf8)
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.filter { $0.prefix == "001122" && $0.prefixLength == 24 }.count == 1)
        #expect(database.registries.first { $0.registry == .maL }?.validRecordCount == 1)
    }

    @Test func skipsPrivateAndEmptyOrganizations() throws {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data(
                "Registry,Assignment,Organization Name\nMA-L,001122,private\nMA-L,001123,   \nMA-L,001124,Public\n".utf8
            )
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(!database.entries.contains { $0.organization.lowercased() == "private" })
        #expect(database.entries.contains { $0.prefix == "001124" && $0.organization == "Public" })
        #expect(database.registries.first { $0.registry == .maL }?.validRecordCount == 1)
    }

    @Test func rejectsMalformedQuotedCSV() {
        var inputs = completeInputs()
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data("Registry,Assignment,Organization Name\nMA-L,001122,\"Unterminated\n".utf8)
        )

        #expect(throws: MACVendorDatabaseError.self) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsMoreThan250000RowsIncludingEmptyRows() {
        var inputs = completeInputs()
        let csv = "Registry,Assignment,Organization Name\n" + String(repeating: "\n", count: 250_000)
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(csv.utf8))

        #expect(throws: MACVendorDatabaseError.malformedCSV(file: "large.csv")) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsRowsWithMoreThan16Fields() {
        var inputs = completeInputs()
        let header = (["Registry", "Assignment", "Organization Name"]
            + Array(repeating: "Unused", count: 14)).joined(separator: ",")
        let csv = "\(header)\nMA-L,001122,Example\n"
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(csv.utf8))

        #expect(throws: MACVendorDatabaseError.malformedCSV(file: "large.csv")) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsMoreThan1000000Fields() {
        var inputs = completeInputs()
        let empty16FieldRow = String(repeating: ",", count: 15)
        let csv = "Registry,Assignment,Organization Name\n"
            + String(repeating: "\(empty16FieldRow)\n", count: 62_500)
            + "MA-L,001122,Example"
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(csv.utf8))

        #expect(throws: MACVendorDatabaseError.malformedCSV(file: "large.csv")) {
            try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func acceptsRowsWithExactly16Fields() throws {
        var inputs = completeInputs()
        let header = (["Registry", "Assignment", "Organization Name"]
            + Array(repeating: "Unused", count: 13)).joined(separator: ",")
        let row = "MA-L,001122,Example" + String(repeating: ",", count: 13)
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data("\(header)\n\(row)".utf8)
        )

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.prefix == "001122" && $0.prefixLength == 24 })
    }

    @Test func acceptsExactly1000000Fields() throws {
        var inputs = completeInputs()
        let header = (["Registry", "Assignment", "Organization Name"]
            + Array(repeating: "Unused", count: 13)).joined(separator: ",")
        let empty16FieldRow = String(repeating: ",", count: 15)
        let valid16FieldRow = "MA-L,001122,Example" + String(repeating: ",", count: 13)
        let csv = "\(header)\n"
            + String(repeating: "\(empty16FieldRow)\n", count: 62_498)
            + valid16FieldRow
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(csv.utf8))

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.prefix == "001122" && $0.prefixLength == 24 })
    }

    @Test func acceptsExactly250000Rows() throws {
        var inputs = completeInputs()
        let emptyRow = ""
        let csv = "Registry,Assignment,Organization Name\n"
            + String(repeating: "\(emptyRow)\n", count: 249_998)
            + "MA-L,001122,Example"
        inputs[0] = MACVendorRegistryInput(displayName: "large.csv", data: Data(csv.utf8))

        let database = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        #expect(database.entries.contains { $0.prefix == "001122" && $0.prefixLength == 24 })
    }

    @Test func rejectsTotalSizeBeforeParsing() {
        let inputs = completeInputs()
        let totalSizeLimitedParser = MACVendorCSVParser(
            minimumRecordCounts: Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) }),
            maximumFileBytes: 1_024,
            maximumTotalBytes: inputs.map(\.data.count).reduce(0, +) - 1
        )

        #expect(throws: MACVendorDatabaseError.self) {
            try totalSizeLimitedParser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func rejectsRegistryBelowMinimumRecordCount() {
        let minimums = Dictionary(uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, $0 == .maL ? 2 : 1) })
        let stricterParser = MACVendorCSVParser(minimumRecordCounts: minimums)

        #expect(throws: MACVendorDatabaseError.self) {
            try stricterParser.parse(inputs: completeInputs(), source: .manualImport, createdAt: .distantPast)
        }
    }

    @Test func automaticAndManualImportsProduceEquivalentRecords() throws {
        let inputs = completeInputs()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let automatic = try parser.parse(inputs: inputs, source: .ieeeDownload, createdAt: createdAt)
        let manual = try parser.parse(inputs: inputs, source: .manualImport, createdAt: createdAt)

        #expect(automatic.entries == manual.entries)
        #expect(automatic.registries.map(\.registry) == manual.registries.map(\.registry))
        #expect(automatic.registries.map(\.validRecordCount) == manual.registries.map(\.validRecordCount))
        #expect(automatic.registries.map(\.sha256) == manual.registries.map(\.sha256))
        #expect(automatic.registries.allSatisfy { metadata in
            metadata.sha256.count == 64
                && metadata.sha256.allSatisfy { "0123456789abcdef".contains($0) }
        })
        #expect(automatic.registries.allSatisfy { $0.sourceURL == $0.registry.downloadURL })
        #expect(manual.registries.allSatisfy { $0.sourceURL == nil })
    }

    @Test func parsesCurrentIEEERegistriesWhenFixtureDirectoryIsProvided() throws {
        let directory = ProcessInfo.processInfo.environment["WIFI_LENS_IEEE_REGISTRY_DIR"]
            ?? "/private/tmp/wifi-lens-ieee-current"
        guard FileManager.default.fileExists(atPath: directory) else {
            return
        }

        let root = URL(filePath: directory, directoryHint: .isDirectory)
        let inputs = try MACVendorRegistry.allCases.map { registry in
            let fileURL = root.appending(path: registry.downloadURL.lastPathComponent)
            return MACVendorRegistryInput(
                displayName: fileURL.lastPathComponent,
                data: try Data(contentsOf: fileURL)
            )
        }

        let database = try MACVendorCSVParser().parse(
            inputs: inputs,
            source: .ieeeDownload,
            createdAt: .distantPast
        )

        #expect(database.registries.count == MACVendorRegistry.allCases.count)
        #expect(database.registries.allSatisfy { metadata in
            metadata.validRecordCount >= (MACVendorCSVParser.productionMinimums[metadata.registry] ?? 0)
        })
        #expect(database.entries.contains {
            $0.prefix == "48BCA6" && $0.organization == "ASUNG TECHNO CO.,Ltd"
        })
    }

    @Test func cancellationBeforeValidationIsPreserved() async {
        let parser = parser
        let inputs = completeInputs()
        let task = Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return try parser.parse(
                inputs: inputs,
                source: .manualImport,
                createdAt: .distantPast
            )
        }

        do {
            _ = try await task.value
            Issue.record("Expected parser cancellation to be preserved")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }

    @Test func cancellationAtThousandRowCheckpointIsPreserved() {
        var inputs = completeInputs()
        let rows = (0..<1_001).map { index in
            let assignment = String(format: "%06X", 0x100000 + index)
            return "MA-L,\(assignment),Example \(index)"
        }
        let csv = (["Registry,Assignment,Organization Name"] + rows).joined(separator: "\n")
        inputs[0] = MACVendorRegistryInput(
            displayName: "large.csv",
            data: Data(csv.utf8)
        )
        let parser = MACVendorCSVParser(
            minimumRecordCounts: Dictionary(
                uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) }
            ),
            cancellationCheck: { point in
                if point == .records(1_000) {
                    throw CancellationError()
                }
            }
        )

        do {
            _ = try parser.parse(inputs: inputs, source: .manualImport, createdAt: .distantPast)
            Issue.record("Expected the thousand-row cancellation checkpoint to throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }

    @Test(arguments: [
        MACVendorCSVParserCancellationPoint.beforeFinalSort,
        .afterFinalSort,
    ])
    func cancellationAroundFinalSortIsPreserved(
        point: MACVendorCSVParserCancellationPoint
    ) {
        let parser = MACVendorCSVParser(
            minimumRecordCounts: Dictionary(
                uniqueKeysWithValues: MACVendorRegistry.allCases.map { ($0, 1) }
            ),
            cancellationCheck: { currentPoint in
                if currentPoint == point {
                    throw CancellationError()
                }
            }
        )

        do {
            _ = try parser.parse(
                inputs: completeInputs(),
                source: .manualImport,
                createdAt: .distantPast
            )
            Issue.record("Expected final-sort cancellation at \(point)")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }
    }
}
