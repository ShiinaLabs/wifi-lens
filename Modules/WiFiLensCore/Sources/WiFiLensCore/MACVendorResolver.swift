import Foundation
import Logging

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
    private static let supportedPrefixLengths = [36, 28, 24]

    private var organizationsByPrefixLength: [Int: [UInt64: String]] = [:]
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
                Self.logger.warning(
                    "Unsupported MAC vendor database schema: \(database.schemaVersion)"
                )
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
        guard let normalized = Self.normalize(macAddress),
              let numericAddress = UInt64(normalized, radix: 16)
        else {
            return .invalid
        }

        let firstOctet = UInt8(normalized.prefix(2), radix: 16) ?? 0
        if numericAddress == 0 || firstOctet & 0x01 != 0 {
            return .invalid
        }

        if let cached = cache[normalized] {
            return cached
        }

        let result: MACVendorLookupResult
        if firstOctet & 0x02 != 0 {
            result = .locallyAdministered
        } else if let organization = longestPrefixMatch(for: numericAddress) {
            result = .registered(organization)
        } else {
            result = .unknown
        }

        cache[normalized] = result
        return result
    }

    private func install(_ entries: [MACVendorEntry]) {
        var mappings: [Int: [UInt64: String]] = [:]
        for entry in entries where Self.supportedPrefixLengths.contains(entry.prefixLength) {
            guard entry.prefix.count == entry.prefixLength / 4,
                  let numericPrefix = UInt64(entry.prefix, radix: 16),
                  !entry.organization.isEmpty
            else {
                continue
            }
            mappings[entry.prefixLength, default: [:]][numericPrefix] = entry.organization
        }
        organizationsByPrefixLength = mappings
    }

    private func longestPrefixMatch(for numericAddress: UInt64) -> String? {
        for prefixLength in Self.supportedPrefixLengths {
            let prefix = numericAddress >> UInt64(48 - prefixLength)
            if let organization = organizationsByPrefixLength[prefixLength]?[prefix] {
                return organization
            }
        }
        return nil
    }

    private static func normalize(_ macAddress: String) -> String? {
        if macAddress.count == 12, macAddress.allSatisfy(\.isHexDigit) {
            return macAddress.uppercased()
        }

        for separator: Character in [":", "-"] {
            let octets = macAddress.split(
                separator: separator,
                omittingEmptySubsequences: false
            )
            guard octets.count == 6,
                  octets.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) })
            else {
                continue
            }
            return octets.joined().uppercased()
        }

        return nil
    }
}
