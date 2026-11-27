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

@MainActor
public final class MACVendorResolver: MACVendorResolving {
    private static let logger = Logger(label: "scanner")
    private static let supportedSchemaVersion = 1

    private var entries: [MACVendorEntry] = []
    private var cache: [String: MACVendorLookupResult] = [:]

    public convenience init() {
        self.init(database: MACVendorBundledDatabase.load())
    }

    public convenience init(database: MACVendorBundledDatabase?) {
        self.init(entries: database?.entries ?? [])
    }

    init(databaseData: Data?) {
        guard let databaseData else {
            Self.logger.warning("MAC vendor database resource is unavailable")
            return
        }

        do {
            let database = try JSONDecoder().decode(MACVendorDatabase.self, from: databaseData)
            guard database.schemaVersion == Self.supportedSchemaVersion else {
                Self.logger.warning("Unsupported MAC vendor database schema: \(database.schemaVersion)")
                return
            }
            install(database.entries)
        } catch {
            Self.logger.error("Failed to load MAC vendor database: \(error)")
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
        if let cached = cache[macAddress] {
            return cached
        }
        let bytes = Array(macAddress.utf8)
        var resultCode: Int32 = 0
        var organization = [UInt8](repeating: 0, count: 512)
        var organizationLength = 0
        var strings: [UInt8] = []
        var lookupEntries: [WiFiLensMacVendorLookupEntry] = []
        for entry in entries {
            let prefixBytes = Array(entry.prefix.utf8)
            let prefixOffset = strings.count
            strings.append(contentsOf: prefixBytes)
            let organizationBytes = Array(entry.organization.utf8)
            let organizationOffset = strings.count
            strings.append(contentsOf: organizationBytes)
            lookupEntries.append(
                WiFiLensMacVendorLookupEntry(
                    prefix_offset: prefixOffset,
                    prefix_length: prefixBytes.count,
                    prefix_length_bits: UInt32(entry.prefixLength),
                    organization_offset: organizationOffset,
                    organization_length: organizationBytes.count
                )
            )
        }

        let status = bytes.withUnsafeBufferPointer { macBuffer in
            lookupEntries.withUnsafeBufferPointer { entryBuffer in
                strings.withUnsafeBufferPointer { stringBuffer in
                    organization.withUnsafeMutableBufferPointer { organizationBuffer in
                        withUnsafeMutablePointer(to: &organizationLength) { lengthPointer in
                            withUnsafeMutablePointer(to: &resultCode) { codePointer in
                                wifi_lens_mac_vendor_lookup(
                                    macBuffer.baseAddress,
                                    macBuffer.count,
                                    entryBuffer.baseAddress,
                                    entryBuffer.count,
                                    stringBuffer.baseAddress,
                                    stringBuffer.count,
                                    organizationBuffer.baseAddress,
                                    organizationBuffer.count,
                                    lengthPointer,
                                    codePointer
                                )
                            }
                        }
                    }
                }
            }
        }
        guard status == WIFI_LENS_STATUS_OK else {
            let result = MACVendorLookupResult.invalid
            cache[macAddress] = result
            return result
        }

        let result: MACVendorLookupResult
        switch resultCode {
        case 0:
            result = .invalid
        case 1:
            result = .unknown
        case 2:
            result = .locallyAdministered
        case 3:
            let name = String(bytes: Array(organization.prefix(organizationLength)), encoding: .utf8) ?? ""
            result = .registered(name)
        default:
            result = .invalid
        }
        cache[macAddress] = result
        return result
    }

    private func install(_ entries: [MACVendorEntry]) {
        self.entries = entries
    }
}
