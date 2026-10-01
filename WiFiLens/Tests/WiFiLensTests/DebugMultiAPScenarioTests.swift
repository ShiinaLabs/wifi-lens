import Foundation
import Testing
import WiFiLensCore
@testable import WiFi_Lens

@Suite struct DebugMultiAPScenarioTests {

    @Test func debugNavigationSeparatesSpectrumChartDebugPage() {
        #expect(SidebarPage.allCases.contains(.spectrumDebugChart))
        #expect(SidebarPage.allCases.contains(.debugChart))
        #expect(SidebarPage.spectrumDebugChart.icon == "antenna.radiowaves.left.and.right")
        #expect(SidebarPage.debugChart.icon == "ladybug")
        #expect(SidebarPage.spectrumDebugChart.requiresLocationAuthorization)
        #expect(SidebarPage.spectrumDebugChart.requiresWiFi)
    }

    @Test func spectrumDebugPagesContainSingleAndMultiAPEntries() {
        #expect(SpectrumDebugPage.allCases.map(\.rawValue) == [
            "singleAP",
            "multiAP",
        ])
        #expect(SpectrumDebugPage.singleAP.label == "Single AP")
        #expect(SpectrumDebugPage.multiAP.label == "Multi AP")
    }

    @Test func debugPagesKeepOnlyNonSpectrumChartEntries() {
        #expect(DebugPage.allCases.map(\.rawValue) == [
            "throughput",
            "roaming",
        ])
        #expect(DebugPage.throughput.label == "Throughput")
        #expect(DebugPage.roaming.label == "Roaming")
    }

    @Test func scenarioRoundTripsThroughJSON() throws {
        let scenario = DebugScenario(
            version: 1,
            bandID: ChannelBand.band5GHz.id,
            presetID: DebugScenarioPreset.labelCollision.id,
            aps: [
                DebugAPConfig(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    enabled: true,
                    ssid: "Debug-1",
                    bssidSuffix: "01",
                    channel: 52,
                    widthMHz: 80,
                    rssi: -48,
                    colorHex: "#3B82F6",
                    hiddenSSID: false,
                    visible: true,
                    filtered: false,
                    supportsK: true,
                    supportsR: true,
                    supportsV: false,
                    supportsWPA3: true,
                    country: "US",
                    trend: .up,
                    trendDelta: 4
                )
            ]
        )

        let data = try JSONEncoder().encode(scenario)
        let decoded = try JSONDecoder().decode(DebugScenario.self, from: data)

        #expect(decoded == scenario)
    }

    @Test func builderDropsDisabledAPsAndUsesProductionChannelBlocks() {
        let enabled = DebugAPConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            enabled: true,
            ssid: "Wide",
            bssidSuffix: "11",
            channel: 52,
            widthMHz: 80,
            rssi: -44,
            colorHex: "#10B981",
            hiddenSSID: false,
            visible: true,
            filtered: false,
            supportsK: false,
            supportsR: false,
            supportsV: false,
            supportsWPA3: false,
            country: "",
            trend: .none,
            trendDelta: 0
        )
        var disabled = enabled
        disabled.id = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        disabled.enabled = false
        disabled.ssid = "Disabled"

        let scenario = DebugScenario(
            version: 1,
            bandID: ChannelBand.band5GHz.id,
            presetID: nil,
            aps: [enabled, disabled]
        )

        let series = DebugChartSeriesAdapter.seriesData(from: scenario, band: .band5GHz)
        let block = ChannelSpanCalculator.channelBlock(
            primaryChannel: 52,
            widthMHz: 80,
            band: .band5GHz
        )

        #expect(series.count == 1)
        #expect(series[0].ssid == "Wide")
        #expect(series[0].left == block.left)
        #expect(series[0].apex == Double(block.left + block.right) / 2.0)
        #expect(series[0].right == block.right)
    }

    @Test func builderMapsDebugMetadataToChartSeriesData() {
        let ap = DebugAPConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            enabled: true,
            ssid: "",
            bssidSuffix: "21",
            channel: 6,
            widthMHz: 40,
            rssi: -61,
            colorHex: "#F59E0B",
            hiddenSSID: true,
            visible: false,
            filtered: true,
            supportsK: true,
            supportsR: false,
            supportsV: true,
            supportsWPA3: true,
            country: "JP",
            trend: .down,
            trendDelta: -7
        )
        let scenario = DebugScenario(version: 1, bandID: ChannelBand.band24GHz.id, presetID: nil, aps: [ap])

        let series = DebugChartSeriesAdapter.seriesData(from: scenario, band: .band24GHz)

        #expect(series.count == 1)
        #expect(series[0].ssid == "")
        #expect(series[0].displaySSID == "n/a")
        #expect(series[0].bssid == "02:00:00:00:00:21")
        #expect(series[0].channel == 6)
        #expect(series[0].rssi == -61)
        #expect(series[0].displayRSSI == -61)
        #expect(series[0].channelWidth == "40")
        #expect(series[0].supportsK)
        #expect(!series[0].supportsR)
        #expect(series[0].supportsV)
        #expect(series[0].supportsWPA3)
        #expect(series[0].isHiddenSSID)
        #expect(!series[0].isVisible)
        #expect(series[0].isFilteredOut)
        #expect(series[0].country == "JP")
        #expect(series[0].trendArrow == "▼")
        #expect(series[0].trendDelta == -7)
    }

    @Test func presetsProduceValidRowsForTheirBands() throws {
        for preset in DebugScenarioPreset.allCases {
            let scenario = DebugScenarioBuilder.scenario(for: preset)
            let band = try #require(ChannelBand(id: scenario.bandID))

            #expect(!scenario.aps.isEmpty)
            #expect(scenario.aps.allSatisfy { $0.channel >= 1 && $0.channel <= band.maxChannel })
            #expect(DebugChartSeriesAdapter.seriesData(from: scenario, band: band).count > 0)
        }
    }

    @Test func normalizationClampsWideRowsWhenSwitchingTo24GHz() {
        let ap = DebugAPConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            enabled: true,
            ssid: "Wide",
            bssidSuffix: "31",
            channel: 149,
            widthMHz: 80,
            rssi: -52,
            colorHex: "#3B82F6",
            hiddenSSID: false,
            visible: true,
            filtered: false,
            supportsK: false,
            supportsR: false,
            supportsV: false,
            supportsWPA3: false,
            country: "",
            trend: .none,
            trendDelta: 0
        )
        let scenario = DebugScenario(version: 1, bandID: ChannelBand.band24GHz.id, presetID: nil, aps: [ap])

        let normalized = DebugScenarioBuilder.normalized(scenario)
        let series = DebugChartSeriesAdapter.seriesData(from: normalized, band: .band24GHz)

        #expect(normalized.aps[0].channel == ChannelBand.band24GHz.maxChannel)
        #expect(normalized.aps[0].widthMHz == 20)
        #expect(series[0].channel == ChannelBand.band24GHz.maxChannel)
        #expect(series[0].channelWidth == "20")
    }

    @Test func storeFallsBackToDefaultPresetWhenPayloadIsInvalid() {
        let defaults = UserDefaults(suiteName: "DebugMultiAPScenarioTests")!
        defaults.removePersistentDomain(forName: "DebugMultiAPScenarioTests")
        defaults.set(Data("not json".utf8), forKey: DebugScenarioStore.storageKey)
        let store = DebugScenarioStore(defaults: defaults)

        let loaded = store.load()

        #expect(loaded.presetID == DebugScenarioPreset.labelCollision.id)
        #expect(!loaded.aps.isEmpty)
    }
}
