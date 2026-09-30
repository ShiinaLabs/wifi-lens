import CryptoKit
import Foundation

enum MACVendorCSVParserCancellationPoint: Equatable, Sendable {
    case routine
    case records(Int)
    case beforeFinalSort
    case afterFinalSort
}

struct MACVendorCSVParser: Sendable {
    typealias CancellationCheck = @Sendable (
        MACVendorCSVParserCancellationPoint
    ) throws -> Void

    static let productionMinimums: [MACVendorRegistry: Int] = [
        .maL: 1_000,
        .maM: 1_000,
        .maS: 1_000,
        .iab: 1_000,
    ]

    let minimumRecordCounts: [MACVendorRegistry: Int]
    let maximumFileBytes: Int
    let maximumTotalBytes: Int
    let cancellationCheck: CancellationCheck

    init(
        minimumRecordCounts: [MACVendorRegistry: Int] = Self.productionMinimums,
        maximumFileBytes: Int = 16 * 1_024 * 1_024,
        maximumTotalBytes: Int = 32 * 1_024 * 1_024,
        cancellationCheck: @escaping CancellationCheck = { _ in
            try Task.checkCancellation()
        }
    ) {
        self.minimumRecordCounts = minimumRecordCounts
        self.maximumFileBytes = maximumFileBytes
        self.maximumTotalBytes = maximumTotalBytes
        self.cancellationCheck = cancellationCheck
    }

    func parse(
        inputs: [MACVendorRegistryInput],
        source: MACVendorDatabaseSource,
        createdAt: Date
    ) throws -> MACVendorDatabase {
        try cancellationCheck(.routine)
        guard inputs.count == MACVendorRegistry.allCases.count else {
            throw MACVendorDatabaseError.wrongFileCount(
                expected: MACVendorRegistry.allCases.count,
                actual: inputs.count
            )
        }

        var totalBytes = 0
        for input in inputs {
            try cancellationCheck(.routine)
            guard input.data.count <= maximumFileBytes else {
                throw MACVendorDatabaseError.fileTooLarge(
                    file: input.displayName,
                    maximumBytes: maximumFileBytes
                )
            }
            totalBytes += input.data.count
            guard totalBytes <= maximumTotalBytes else {
                throw MACVendorDatabaseError.totalSizeExceeded(maximumBytes: maximumTotalBytes)
            }
        }

        var parsedByRegistry: [MACVendorRegistry: ParsedRegistry] = [:]
        for input in inputs {
            try cancellationCheck(.routine)
            let parsed = try parse(input)
            guard parsedByRegistry[parsed.registry] == nil else {
                throw MACVendorDatabaseError.duplicateRegistry(parsed.registry)
            }
            parsedByRegistry[parsed.registry] = parsed
        }

        for registry in MACVendorRegistry.allCases where parsedByRegistry[registry] == nil {
            throw MACVendorDatabaseError.missingRegistry(registry)
        }

        var entriesByAssignment: [AssignmentKey: MACVendorEntry] = [:]
        var ambiguousAssignments: Set<AssignmentKey> = []
        for registry in MACVendorRegistry.allCases {
            guard let parsed = parsedByRegistry[registry] else {
                continue
            }
            for (index, entry) in parsed.entries.enumerated() {
                if index > 0, index.isMultiple(of: 1_000) {
                    try cancellationCheck(.records(index))
                }
                let key = AssignmentKey(prefix: entry.prefix, prefixLength: entry.prefixLength)
                guard !ambiguousAssignments.contains(key) else {
                    continue
                }
                if let existing = entriesByAssignment[key] {
                    if existing.organization != entry.organization {
                        entriesByAssignment.removeValue(forKey: key)
                        ambiguousAssignments.insert(key)
                    }
                } else {
                    entriesByAssignment[key] = entry
                }
            }
        }

        let metadata = MACVendorRegistry.allCases.compactMap { registry -> MACVendorRegistryMetadata? in
            guard let parsed = parsedByRegistry[registry] else {
                return nil
            }
            return MACVendorRegistryMetadata(
                registry: registry,
                validRecordCount: parsed.entries.count,
                sha256: parsed.sha256,
                sourceURL: source == .ieeeDownload ? registry.downloadURL : nil
            )
        }

        try cancellationCheck(.beforeFinalSort)
        let entries = entriesByAssignment.values.sorted {
            if $0.prefixLength != $1.prefixLength {
                return $0.prefixLength > $1.prefixLength
            }
            return $0.prefix < $1.prefix
        }
        try cancellationCheck(.afterFinalSort)

        return MACVendorDatabase(
            schemaVersion: MACVendorDatabase.schemaVersion,
            createdAt: createdAt,
            source: source,
            registries: metadata,
            entries: entries
        )
    }

    private func parse(_ input: MACVendorRegistryInput) throws -> ParsedRegistry {
        try cancellationCheck(.routine)
        guard var csv = String(data: input.data, encoding: .utf8) else {
            throw MACVendorDatabaseError.invalidEncoding(file: input.displayName)
        }
        if csv.first == "\u{FEFF}" {
            csv.removeFirst()
        }
        csv = String(csv.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        })

        let rows = try CSVReader.parse(
            csv,
            file: input.displayName,
            cancellationCheck: cancellationCheck
        )
        guard let header = rows.first else {
            throw MACVendorDatabaseError.malformedCSV(file: input.displayName)
        }

        let requiredColumns = ["Registry", "Assignment", "Organization Name"]
        let missingColumns = requiredColumns.filter { !header.contains($0) }
        guard missingColumns.isEmpty else {
            throw MACVendorDatabaseError.missingColumns(
                file: input.displayName,
                columns: missingColumns
            )
        }
        guard let registryIndex = header.firstIndex(of: "Registry"),
              let assignmentIndex = header.firstIndex(of: "Assignment"),
              let organizationIndex = header.firstIndex(of: "Organization Name")
        else {
            throw MACVendorDatabaseError.malformedCSV(file: input.displayName)
        }

        let greatestIndex = max(registryIndex, assignmentIndex, organizationIndex)
        var fileRegistry: MACVendorRegistry?
        var entriesByAssignment: [AssignmentKey: MACVendorEntry] = [:]
        var ambiguousAssignments: Set<AssignmentKey> = []

        for (index, row) in rows.dropFirst().enumerated() {
            if index > 0, index.isMultiple(of: 1_000) {
                try cancellationCheck(.records(index))
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            guard row.indices.contains(greatestIndex),
                  let registry = MACVendorRegistry(rawValue: row[registryIndex])
            else {
                throw MACVendorDatabaseError.mixedRegistries(file: input.displayName)
            }
            if let fileRegistry, fileRegistry != registry {
                throw MACVendorDatabaseError.mixedRegistries(file: input.displayName)
            }
            fileRegistry = registry

            let assignment = row[assignmentIndex]
            let normalizedAssignment = assignment
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
                .uppercased()
            guard normalizedAssignment.count == registry.prefixLength / 4,
                  normalizedAssignment.allSatisfy({
                      ("0"..."9").contains($0) || ("A"..."F").contains($0)
                  })
            else {
                throw MACVendorDatabaseError.invalidAssignment(
                    file: input.displayName,
                    registry: registry,
                    assignment: assignment
                )
            }

            guard let organization = try normalizeOrganization(
                row[organizationIndex],
                file: input.displayName
            ) else {
                continue
            }

            let key = AssignmentKey(prefix: normalizedAssignment, prefixLength: registry.prefixLength)
            guard !ambiguousAssignments.contains(key) else {
                continue
            }
            if let existing = entriesByAssignment[key] {
                if existing.organization != organization {
                    entriesByAssignment.removeValue(forKey: key)
                    ambiguousAssignments.insert(key)
                }
            } else {
                entriesByAssignment[key] = MACVendorEntry(
                    prefix: normalizedAssignment,
                    prefixLength: registry.prefixLength,
                    organization: organization
                )
            }
        }

        guard let registry = fileRegistry else {
            throw MACVendorDatabaseError.mixedRegistries(file: input.displayName)
        }
        let minimum = minimumRecordCounts[registry] ?? 0
        guard entriesByAssignment.count >= minimum else {
            throw MACVendorDatabaseError.tooFewRecords(
                registry: registry,
                minimum: minimum,
                actual: entriesByAssignment.count
            )
        }

        return ParsedRegistry(
            registry: registry,
            entries: Array(entriesByAssignment.values),
            sha256: SHA256.hash(data: input.data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func normalizeOrganization(_ value: String, file: String) throws -> String? {
        let decoded = decodeEntities(in: value)
        var normalized = ""
        var hasPendingSpace = false

        for scalar in decoded.unicodeScalars {
            if scalar.properties.isWhitespace {
                hasPendingSpace = !normalized.isEmpty
                continue
            }
            guard !CharacterSet.controlCharacters.contains(scalar) else {
                throw MACVendorDatabaseError.invalidOrganization(file: file)
            }
            if hasPendingSpace {
                normalized.append(" ")
                hasPendingSpace = false
            }
            normalized.unicodeScalars.append(scalar)
        }

        guard normalized.unicodeScalars.count <= 256 else {
            throw MACVendorDatabaseError.invalidOrganization(file: file)
        }
        guard !normalized.isEmpty, normalized.caseInsensitiveCompare("private") != .orderedSame else {
            return nil
        }
        return normalized
    }

    private func decodeEntities(in value: String) -> String {
        var result = ""
        var cursor = value.startIndex

        while cursor < value.endIndex {
            guard value[cursor] == "&" else {
                result.append(value[cursor])
                cursor = value.index(after: cursor)
                continue
            }

            let entityStart = value.index(after: cursor)
            if let (decoded, nextIndex) = decodeEntityCandidate(in: value, startingAt: entityStart) {
                result.unicodeScalars.append(decoded)
                cursor = nextIndex
            } else {
                result.append("&")
                cursor = entityStart
            }
        }
        return result
    }

    private func decodeEntityCandidate(
        in value: String,
        startingAt startIndex: String.Index
    ) -> (scalar: Unicode.Scalar, nextIndex: String.Index)? {
        let maximumCandidateLength = 8
        var candidate = ""
        var cursor = startIndex

        while cursor < value.endIndex {
            let character = value[cursor]
            if character == "&" {
                return nil
            }
            if character == ";" {
                guard let scalar = decodeEntity(candidate) else {
                    return nil
                }
                return (scalar, value.index(after: cursor))
            }
            guard candidate.count < maximumCandidateLength else {
                return nil
            }
            candidate.append(character)
            cursor = value.index(after: cursor)
        }
        return nil
    }

    private func decodeEntity(_ entity: String) -> Unicode.Scalar? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "#39": return "'"
        default:
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                return UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
            }
            if entity.hasPrefix("#") {
                return UInt32(entity.dropFirst(), radix: 10).flatMap(Unicode.Scalar.init)
            }
            return nil
        }
    }
}

private extension MACVendorCSVParser {
    struct AssignmentKey: Hashable {
        let prefix: String
        let prefixLength: Int
    }

    struct ParsedRegistry {
        let registry: MACVendorRegistry
        let entries: [MACVendorEntry]
        let sha256: String
    }

    enum CSVReader {
        private static let maximumRows = 250_000
        private static let maximumFieldsPerRow = 16
        private static let maximumTotalFields = 1_000_000

        static func parse(
            _ csv: String,
            file: String,
            cancellationCheck: MACVendorCSVParser.CancellationCheck
        ) throws -> [[String]] {
            var rows: [[String]] = []
            var row: [String] = []
            var field = ""
            var totalFields = 0
            var insideQuotes = false
            var afterClosingQuote = false
            var endedWithRowTerminator = false
            var index = csv.startIndex

            func appendField() throws {
                guard row.count < maximumFieldsPerRow,
                      totalFields < maximumTotalFields
                else {
                    throw MACVendorDatabaseError.malformedCSV(file: file)
                }
                row.append(field)
                totalFields += 1
                field = ""
            }

            func appendRow() throws {
                guard rows.count < maximumRows else {
                    throw MACVendorDatabaseError.malformedCSV(file: file)
                }
                rows.append(row)
                row = []
            }

            while index < csv.endIndex {
                let character = csv[index]
                let nextIndex = csv.index(after: index)

                if insideQuotes {
                    if character == "\"" {
                        if nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                            field.append("\"")
                            endedWithRowTerminator = false
                            index = csv.index(after: nextIndex)
                            continue
                        }
                        insideQuotes = false
                        afterClosingQuote = true
                    } else {
                        field.append(character)
                    }
                    endedWithRowTerminator = false
                    index = nextIndex
                    continue
                }

                if afterClosingQuote,
                   character != ",",
                   character != "\r",
                   character != "\n",
                   character != "\r\n"
                {
                    throw MACVendorDatabaseError.malformedCSV(file: file)
                }

                switch character {
                case "\"":
                    guard field.isEmpty else {
                        throw MACVendorDatabaseError.malformedCSV(file: file)
                    }
                    insideQuotes = true
                    endedWithRowTerminator = false
                case ",":
                    try appendField()
                    afterClosingQuote = false
                    endedWithRowTerminator = false
                case "\r", "\n", "\r\n":
                    try appendField()
                    try appendRow()
                    if rows.count.isMultiple(of: 1_000) {
                        try cancellationCheck(.records(rows.count))
                    }
                    afterClosingQuote = false
                    endedWithRowTerminator = true
                    if character == "\r", nextIndex < csv.endIndex, csv[nextIndex] == "\n" {
                        index = csv.index(after: nextIndex)
                        continue
                    }
                default:
                    field.append(character)
                    endedWithRowTerminator = false
                }
                index = nextIndex
            }

            guard !insideQuotes else {
                throw MACVendorDatabaseError.malformedCSV(file: file)
            }
            if !endedWithRowTerminator {
                try appendField()
                try appendRow()
            }
            return rows
        }
    }
}
