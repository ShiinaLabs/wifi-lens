import Foundation
import Testing
@testable import WiFiLensCore

@Suite struct DeviceCompatibilityFilterTests {

    private func makeChannels(_ pairs: [(Int, Int)]) -> Set<String> {
        Set(pairs.map { "\($0.0)-\($0.1)" })
    }

    // MARK: - Basic compatibility

    @Test("Channel in supported set is compatible")
    func supportedChannelPasses() {
        let supported = makeChannels([(2, 36), (2, 40), (2, 44)])
        let result = DeviceCompatibilityFilter.check(
            channel: 36,
            band: "5",
            capabilities: .default,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == true)
        #expect(result.reason == nil)
    }

    @Test("Channel not in supported set is incompatible")
    func unsupportedChannelFails() {
        let supported = makeChannels([(2, 36), (2, 40)])
        let result = DeviceCompatibilityFilter.check(
            channel: 149,
            band: "5",
            capabilities: .default,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == false)
        #expect(result.reason != nil)
    }

    @Test("Empty supported channels is treated as unknown (passes)")
    func emptySupportedChannelsPasses() {
        let result = DeviceCompatibilityFilter.check(
            channel: 36,
            band: "5",
            capabilities: .default,
            supportedChannels: [],
            channelMeta: nil
        )
        // Empty set means we don't have data → assume compatible (don't block incorrectly)
        #expect(result.isCompatible == true)
    }

    // MARK: - DFS

    @Test("DFS channel without DFS-capable device is incompatible")
    func dfsChannelWithoutDFSSupport() {
        let supported = makeChannels([(2, 52)]) // channel IS in supported set
        let caps = DevicePHYCapabilities(
            supportsAX: false,
            supportsAC: true,
            supportsN: true,
            supportsBE: false,
            supports6GHz: false,
            supportsDFS: false,  // explicitly disable DFS
            supports160MHz: false
        )

        let dfsMeta = RegulatoryChannelMeta(
            isDFS: true,
            isRadarSensitive: true,
            requiresCAC: true,
            forcedSwitchRisk: true,
            isIndoorOnly: false,
            maxEIRPDbm: nil,
            requiresAFC: false,
            wiFi6EAvailable: true,
            wiFi7Available: true,
            notes: nil
        )

        let result = DeviceCompatibilityFilter.check(
            channel: 52,
            band: "5",
            capabilities: caps,
            supportedChannels: supported,
            channelMeta: dfsMeta
        )
        #expect(result.isCompatible == false)
        #expect(result.reason?.contains("DFS") == true)
    }

    @Test("DFS channel with DFS-capable device is compatible")
    func dfsChannelWithDFSSupport() {
        let supported = makeChannels([(2, 52)])
        var caps = DevicePHYCapabilities.default
        caps = DevicePHYCapabilities(
            supportsAX: caps.supportsAX,
            supportsAC: caps.supportsAC,
            supportsN: caps.supportsN,
            supportsBE: caps.supportsBE,
            supports6GHz: caps.supports6GHz,
            supportsDFS: true,
            supports160MHz: caps.supports160MHz
        )

        let dfsMeta = RegulatoryChannelMeta(
            isDFS: true,
            isRadarSensitive: false,
            requiresCAC: true,
            forcedSwitchRisk: false,
            isIndoorOnly: false,
            maxEIRPDbm: nil,
            requiresAFC: false,
            wiFi6EAvailable: true,
            wiFi7Available: true,
            notes: nil
        )

        let result = DeviceCompatibilityFilter.check(
            channel: 52,
            band: "5",
            capabilities: caps,
            supportedChannels: supported,
            channelMeta: dfsMeta
        )
        #expect(result.isCompatible == true)
    }

    // MARK: - 6 GHz

    @Test("6 GHz channel without 6 GHz-capable device is incompatible")
    func sixGHzChannelWithout6GHzSupport() {
        let supported = makeChannels([(3, 5)])
        let caps = DevicePHYCapabilities.default
        // default has supports6GHz = false

        let result = DeviceCompatibilityFilter.check(
            channel: 5,
            band: "6",
            capabilities: caps,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == false)
        #expect(result.reason?.contains("6 GHz") == true)
    }

    @Test("6 GHz channel with 6 GHz-capable device is compatible")
    func sixGHzChannelWith6GHzSupport() {
        let supported = makeChannels([(3, 5)])
        var caps = DevicePHYCapabilities.default
        caps = DevicePHYCapabilities(
            supportsAX: true,
            supportsAC: caps.supportsAC,
            supportsN: caps.supportsN,
            supportsBE: caps.supportsBE,
            supports6GHz: true,
            supportsDFS: caps.supportsDFS,
            supports160MHz: caps.supports160MHz
        )

        let result = DeviceCompatibilityFilter.check(
            channel: 5,
            band: "6",
            capabilities: caps,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == true)
    }

    // MARK: - AFC

    @Test("AFC-required channel is incompatible (not yet supported)")
    func afcRequiredChannelIncompatible() {
        let supported = makeChannels([(3, 185)])
        let afcMeta = RegulatoryChannelMeta(
            isDFS: false,
            isRadarSensitive: false,
            requiresCAC: false,
            forcedSwitchRisk: false,
            isIndoorOnly: false,
            maxEIRPDbm: nil,
            requiresAFC: true,
            wiFi6EAvailable: true,
            wiFi7Available: true,
            notes: nil
        )

        var caps = DevicePHYCapabilities.default
        caps = DevicePHYCapabilities(
            supportsAX: true,
            supportsAC: caps.supportsAC,
            supportsN: caps.supportsN,
            supportsBE: caps.supportsBE,
            supports6GHz: true,
            supportsDFS: caps.supportsDFS,
            supports160MHz: caps.supports160MHz
        )

        let result = DeviceCompatibilityFilter.check(
            channel: 185,
            band: "6",
            capabilities: caps,
            supportedChannels: supported,
            channelMeta: afcMeta
        )
        #expect(result.isCompatible == false)
        #expect(result.reason?.contains("AFC") == true)
    }

    // MARK: - Band handling

    @Test("2.4 GHz channel with nil metadata is always compatible if in supported set")
    func band24GHzAlwaysCompatible() {
        let supported = makeChannels([(1, 6)])
        let result = DeviceCompatibilityFilter.check(
            channel: 6,
            band: "24",
            capabilities: .default,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == true)
    }

    @Test("Unknown band defaults to compatible if in supported set")
    func unknownBandCompatible() {
        let supported = makeChannels([(0, 1)])
        let result = DeviceCompatibilityFilter.check(
            channel: 1,
            band: "unknown",
            capabilities: .default,
            supportedChannels: supported,
            channelMeta: nil
        )
        #expect(result.isCompatible == true)
    }
}
