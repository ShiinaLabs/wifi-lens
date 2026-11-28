import Foundation
import Logging
import WiFiLensCoreRust

public enum MACVendorLookupResult: Equatable, Sendable {
    case registered(String)
    case locallyAdministered
    case unknown
    case invalid
}

@MainActor
public protocol MACVendorResolving: AnyObject {
    func resolve(_ macAddress: String) -> MACVendorLookupResult
}

/// Serializes lookup and destruction around the opaque Rust allocation. Resolver
/// calls are MainActor isolated; the lock also makes a final release safe if ARC
/// performs this owner's deinitialization on another thread.
private final class OwnedMACVendorIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: OpaquePointer?

    init?(entries: [MACVendorEntry]) {
        var strings: [UInt8] = []
        var rawEntries: [WiFiLensMacVendorLookupEntry] = []
        for entry in entries {
            let prefix = Array(entry.prefix.utf8)
            let prefixOffset = strings.count
            strings.append(contentsOf: prefix)
            let organization = Array(entry.organization.utf8)
            let organizationOffset = strings.count
            strings.append(contentsOf: organization)
            rawEntries.append(
                WiFiLensMacVendorLookupEntry(
                    prefix_offset: prefixOffset,
                    prefix_length: prefix.count,
                    prefix_length_bits: UInt32(entry.prefixLength),
                    organization_offset: organizationOffset,
                    organization_length: organization.count
                ))
        }

        var built: OpaquePointer?
        let status = rawEntries.withUnsafeBufferPointer { entryBuffer in
            strings.withUnsafeBufferPointer { stringBuffer in
                wifi_lens_mac_vendor_index_build(
                    entryBuffer.baseAddress,
                    entryBuffer.count,
                    stringBuffer.baseAddress,
                    stringBuffer.count,
                    &built
                )
            }
        }
        guard status == WIFI_LENS_STATUS_OK, let built else { return nil }
        handle = built
    }

    func lookup(_ bytes: [UInt8], organization: inout [UInt8], length: inout Int, result: inout Int32) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return WIFI_LENS_STATUS_INVALID_POINTER }
        return bytes.withUnsafeBufferPointer { macBuffer in
            organization.withUnsafeMutableBufferPointer { organizationBuffer in
                withUnsafeMutablePointer(to: &length) { lengthPointer in
                    withUnsafeMutablePointer(to: &result) { resultPointer in
                        wifi_lens_mac_vendor_index_lookup(
                            handle,
                            macBuffer.baseAddress,
                            macBuffer.count,
                            organizationBuffer.baseAddress,
                            organizationBuffer.count,
                            lengthPointer,
                            resultPointer
                        )
                    }
                }
            }
        }
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        if let handle { wifi_lens_mac_vendor_index_free(handle) }
    }
}

@MainActor
public final class MACVendorResolver: MACVendorResolving {
    private static let logger = Logger(label: "scanner")
    private static let supportedSchemaVersion = 1

    private var index: OwnedMACVendorIndex?
    private var cache: [String: MACVendorLookupResult] = [:]
    private(set) var indexBuildCount = 0

    public convenience init() {
        self.init(database: MACVendorBundledDatabase.load())
    }

    public convenience init(database: MACVendorBundledDatabase?) {
        self.init(entries: database?.entries ?? [])
    }

    init(databaseData: Data?) {
        guard let databaseData else {
            Self.logger.warning("MAC vendor database resource is unavailable")
            install([])
            return
        }

        do {
            let database = try JSONDecoder().decode(MACVendorDatabase.self, from: databaseData)
            guard database.schemaVersion == Self.supportedSchemaVersion else {
                Self.logger.warning("Unsupported MAC vendor database schema: \(database.schemaVersion)")
                install([])
                return
            }
            install(database.entries)
        } catch {
            Self.logger.error("Failed to load MAC vendor database: \(error)")
            install([])
        }
    }

    init(entries: [MACVendorEntry]) {
        install(entries)
    }

    public func replaceEntries(_ entries: [MACVendorEntry]) {
        install(entries)
        cache.removeAll(keepingCapacity: true)
    }

    public func resolve(_ macAddress: String) -> MACVendorLookupResult {
        if let cached = cache[macAddress] { return cached }
        var output = [UInt8](repeating: 0, count: 256 * 4)
        var outputLength = 0
        var resultCode: Int32 = 0
        let bytes = Array(macAddress.utf8)
        guard let index else { return .invalid }
        var status = index.lookup(bytes, organization: &output, length: &outputLength, result: &resultCode)
        if status == WIFI_LENS_STATUS_OUTPUT_TOO_SMALL {
            output = [UInt8](repeating: 0, count: outputLength)
            status = index.lookup(bytes, organization: &output, length: &outputLength, result: &resultCode)
        }
        guard status == WIFI_LENS_STATUS_OK else { return .invalid }

        let result: MACVendorLookupResult
        switch resultCode {
        case 0: result = .invalid
        case 1: result = .unknown
        case 2: result = .locallyAdministered
        case 3:
            result = .registered(String(decoding: output.prefix(outputLength), as: UTF8.self))
        default: result = .invalid
        }
        cache[macAddress] = result
        return result
    }

    private func install(_ entries: [MACVendorEntry]) {
        let replacement = OwnedMACVendorIndex(entries: entries)
        guard let replacement else {
            Self.logger.error("Failed to build MAC vendor lookup index")
            index = nil
            return
        }
        index = replacement
        indexBuildCount += 1
    }
}
