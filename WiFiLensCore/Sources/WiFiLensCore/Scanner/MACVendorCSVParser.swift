import Foundation
import WiFiLensCoreRust

enum MACVendorCSVParserCancellationPoint: Equatable, Sendable {
    case routine
    case records(Int)
    case beforeFinalSort
    case afterFinalSort

    init?(cancellationCode: Int32, count: Int) {
        switch cancellationCode {
        case 0: self = .routine
        case 1: self = .records(count)
        case 2: self = .beforeFinalSort
        case 3: self = .afterFinalSort
        default: return nil
        }
    }
}

struct MACVendorCSVParser: Sendable {
    typealias CancellationCheck =
        @Sendable (
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
        var strings: [UInt8] = []
        var rawInputs: [WiFiLensMacVendorRegistryInput] = []
        for input in inputs {
            let nameBytes = Array(input.displayName.utf8)
            let nameOffset = strings.count
            strings.append(contentsOf: nameBytes)
            let dataOffset = strings.count
            strings.append(contentsOf: input.data)
            rawInputs.append(
                WiFiLensMacVendorRegistryInput(
                    display_name_offset: nameOffset,
                    display_name_length: nameBytes.count,
                    data_offset: dataOffset,
                    data_length: input.data.count
                )
            )
        }

        let minimums = MACVendorRegistry.allCases.map { registry in
            WiFiLensMacVendorMinimum(
                registry: registry.rustCode,
                minimum_records: minimumRecordCounts[registry] ?? 0
            )
        }
        var failure = WiFiLensMacVendorFailure()
        var failureText = [UInt8](repeating: 0, count: 512)
        var failureTextLength = 0
        var registryResults = [WiFiLensMacVendorRegistryMetadata](
            repeating: WiFiLensMacVendorRegistryMetadata(),
            count: MACVendorRegistry.allCases.count
        )
        var entryResults = [WiFiLensMacVendorEntry](
            repeating: WiFiLensMacVendorEntry(),
            count: 1_000_000
        )
        var resultText = [UInt8](repeating: 0, count: 96_000_000)
        var registryCount = 0
        var entryCount = 0
        var resultTextLength = 0
        let cancellationError = MACVendorCancellationError()
        var context = MACVendorCancellationContext(parser: self, error: cancellationError)

        let status = withUnsafeMutablePointer(to: &failure) { failurePointer in
            strings.withUnsafeBufferPointer { stringBuffer in
                rawInputs.withUnsafeBufferPointer { inputBuffer in
                    minimums.withUnsafeBufferPointer { minimumBuffer in
                        failureText.withUnsafeMutableBufferPointer { failureTextBuffer in
                            registryResults.withUnsafeMutableBufferPointer { registryBuffer in
                                entryResults.withUnsafeMutableBufferPointer { entryBuffer in
                                    resultText.withUnsafeMutableBufferPointer { textBuffer in
                                        withUnsafeMutablePointer(to: &failureTextLength) { failureLengthPointer in
                                            withUnsafeMutablePointer(to: &registryCount) { registryCountPointer in
                                                withUnsafeMutablePointer(to: &entryCount) { entryCountPointer in
                                                    withUnsafeMutablePointer(to: &resultTextLength) { textLengthPointer in
                                                        withUnsafeMutablePointer(to: &context) { contextPointer in
                                                            wifi_lens_mac_vendor_parse_database(
                                                                inputBuffer.baseAddress,
                                                                inputBuffer.count,
                                                                stringBuffer.baseAddress,
                                                                stringBuffer.count,
                                                                source.rustCode,
                                                                minimumBuffer.baseAddress,
                                                                minimumBuffer.count,
                                                                maximumFileBytes,
                                                                maximumTotalBytes,
                                                                macVendorCancellationCallback,
                                                                contextPointer,
                                                                failurePointer,
                                                                failureTextBuffer.baseAddress,
                                                                failureTextBuffer.count,
                                                                failureLengthPointer,
                                                                registryBuffer.baseAddress,
                                                                registryBuffer.count,
                                                                entryBuffer.baseAddress,
                                                                entryBuffer.count,
                                                                textBuffer.baseAddress,
                                                                textBuffer.count,
                                                                registryCountPointer,
                                                                entryCountPointer,
                                                                textLengthPointer
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard status == WIFI_LENS_STATUS_OK else {
            if let error = cancellationError.value {
                throw error
            }
            let file = decodeSwiftUTF8(failureText, failure.detail_offset, failure.detail_length) ?? ""
            let detail = String(decoding: failureText.prefix(failureTextLength), as: UTF8.self)
            throw mapMacVendorError(
                code: failure.code,
                registry: MACVendorRegistry(rustCode: failure.registry),
                number1: failure.number1,
                number2: failure.number2,
                file: file,
                detail: detail
            )
        }

        let registries = registryResults.prefix(registryCount).compactMap { metadata -> MACVendorRegistryMetadata? in
            guard let registry = MACVendorRegistry(rustCode: metadata.registry),
                let sha256 = decodeSwiftUTF8(resultText, metadata.sha256_offset, metadata.sha256_length)
            else { return nil }
            return MACVendorRegistryMetadata(
                registry: registry,
                validRecordCount: metadata.valid_record_count,
                sha256: sha256,
                sourceURL: source == .ieeeDownload ? registry.downloadURL : nil
            )
        }
        let entries = entryResults.prefix(entryCount).compactMap { entry -> MACVendorEntry? in
            guard let prefix = decodeSwiftUTF8(resultText, entry.prefix_offset, entry.prefix_length),
                let organization = decodeSwiftUTF8(resultText, entry.organization_offset, entry.organization_length)
            else { return nil }
            return MACVendorEntry(
                prefix: prefix,
                prefixLength: Int(entry.prefix_length_bits),
                organization: organization
            )
        }
        guard registries.count == registryCount, entries.count == entryCount else {
            throw MACVendorDatabaseError.malformedCSV(file: inputs.first?.displayName ?? "")
        }
        return MACVendorDatabase(
            schemaVersion: MACVendorDatabase.schemaVersion,
            createdAt: createdAt,
            source: source,
            registries: registries,
            entries: entries
        )
    }

    private func decodeSwiftUTF8(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> String? {
        guard offset >= 0, length >= 0, offset <= bytes.count, length <= bytes.count - offset else { return nil }
        return String(bytes: Array(bytes[offset..<(offset + length)]), encoding: .utf8)
    }

    private func mapMacVendorError(
        code: Int32,
        registry: MACVendorRegistry?,
        number1: Int64,
        number2: Int64,
        file: String,
        detail: String
    ) -> MACVendorDatabaseError {
        switch code {
        case 1: return .wrongFileCount(expected: Int(number1), actual: Int(number2))
        case 2: return .fileTooLarge(file: file, maximumBytes: Int(number1))
        case 3: return .totalSizeExceeded(maximumBytes: Int(number1))
        case 4: return .invalidEncoding(file: file)
        case 5: return .malformedCSV(file: file)
        case 6:
            let columns = ["Registry", "Assignment", "Organization Name"]
                .enumerated()
                .compactMap { index, column in number1 & (1 << index) == 0 ? nil : column }
            return .missingColumns(file: file, columns: columns)
        case 7: return .mixedRegistries(file: file)
        case 8: return .duplicateRegistry(registry ?? .maL)
        case 9: return .missingRegistry(registry ?? .maL)
        case 10:
            let assignment = String(detail.suffix(Int(max(0, number2))))
            return .invalidAssignment(file: file, registry: registry ?? .maL, assignment: assignment)
        case 11: return .invalidOrganization(file: file)
        case 12: return .tooFewRecords(registry: registry ?? .maL, minimum: Int(number1), actual: Int(number2))
        case 13: return .persistenceFailure
        default: return .malformedCSV(file: file)
        }
    }
}

private final class MACVendorCancellationError {
    var value: Error?
}

private struct MACVendorCancellationContext {
    let parser: MACVendorCSVParser
    let error: MACVendorCancellationError
}

private let macVendorCancellationCallback: WiFiLensMacVendorCancellationCallback = { point, count, contextPointer in
    guard let contextPointer,
        let point = MACVendorCSVParserCancellationPoint(cancellationCode: point, count: count)
    else { return 0 }
    let context = contextPointer.assumingMemoryBound(to: MACVendorCancellationContext.self).pointee
    do {
        try context.parser.cancellationCheck(point)
        return 0
    } catch {
        context.error.value = error
        return 1
    }
}

private extension MACVendorRegistry {
    var rustCode: Int32 {
        switch self {
        case .maL: 1
        case .maM: 2
        case .maS: 3
        case .iab: 4
        }
    }

    init?(rustCode: Int32) {
        switch rustCode {
        case 1: self = .maL
        case 2: self = .maM
        case 3: self = .maS
        case 4: self = .iab
        default: return nil
        }
    }
}

private extension MACVendorDatabaseSource {
    var rustCode: Int32 {
        switch self {
        case .ieeeDownload: 1
        case .manualImport: 2
        }
    }
}
