import Foundation
import Testing
@testable import WiFiLensCore

@Suite("WiFiObservationPipeline")
struct PipelineTests {
    @Test("produceCycle uses the current connection for snapshot and channel analysis")
    func productionCycleUsesCurrentConnection() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let status = WiFiCurrentStatus(
            timestamp: timestamp,
            interfaceName: "en0",
            ssid: "Current",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36,
            band: .band5GHz,
            rssi: -48,
            routerIP: "192.0.2.1",
            isConnected: true,
            isWiFiPowerOn: true
        )
        let currentProvider = TestCountingCurrentConnectionProvider(result: status)
        let latencyProvider = TestRecordingGatewayLatencyProvider(result: GatewayLatencyResult(
            timestamp: timestamp,
            routerIP: "192.0.2.1",
            latencyMs: 12
        ))
        let pipeline = makeCyclePipeline(
            currentProvider: currentProvider,
            latencyProvider: latencyProvider
        )

        let result = await pipeline.produceCycle(
            networks: [
                network(ssid: "Current", bssid: "AA:BB:CC:DD:EE:FF", channel: 36, band: .band5GHz, rssi: -48),
                network(ssid: "Nearby", bssid: "11:22:33:44:55:66", channel: 40, band: .band5GHz, rssi: -62),
                network(ssid: "Other band", bssid: "77:88:99:AA:BB:CC", channel: 6, band: .band24GHz, rssi: -50),
            ],
            context: cycleContext(timestamp: timestamp, supportedBands: [.band5GHz])
        )

        #expect(result.observation.environmentSnapshot?.networks.first(where: {
            $0.bssid == "AA:BB:CC:DD:EE:FF"
        })?.isCurrentNetwork == true)
        #expect(result.observation.channelAnalysis?.allSatisfy { $0.band == "5" } == true)
        #expect(result.observation.channelAnalysis?.first(where: { $0.channel == 36 })?.isCurrentChannel == true)
        #expect(result.observation.channelAnalysis?.first(where: { $0.channel == 36 })?.recommendationConfidence == .exact)
        #expect(await currentProvider.fetchCount == 1)
        #expect(await latencyProvider.measuredRouterIPs.isEmpty)
    }

    @Test("produceCycle marks the current channel only in the connected band")
    func productionCycleScopesCurrentChannelToBand() async {
        let status = WiFiCurrentStatus(
            timestamp: Date(),
            interfaceName: "en0",
            ssid: "Current 6 GHz",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 5,
            band: .band6GHz,
            rssi: -48,
            routerIP: "192.0.2.1",
            isConnected: true,
            isWiFiPowerOn: true
        )
        let pipeline = makeCyclePipeline(
            currentProvider: TestCountingCurrentConnectionProvider(result: status)
        )

        let result = await pipeline.produceCycle(
            networks: [
                network(ssid: "Current 6 GHz", bssid: "AA:BB:CC:DD:EE:FF", channel: 5, band: .band6GHz, rssi: -48),
                network(ssid: "Nearby 2.4 GHz", bssid: "11:22:33:44:55:66", channel: 5, band: .band24GHz, rssi: -62),
            ],
            context: cycleContext(supportedBands: [.band24GHz, .band6GHz])
        )

        #expect(result.observation.channelAnalysis?.first(where: {
            $0.band == "6" && $0.channel == 5
        })?.isCurrentChannel == true)
        #expect(result.observation.channelAnalysis?.first(where: {
            $0.band == "6" && $0.channel == 5
        })?.recommendationState == .currentGoodEnough)
        #expect(result.observation.channelAnalysis?.first(where: {
            $0.band == "24" && $0.channel == 5
        })?.isCurrentChannel == false)
        #expect(result.observation.channelAnalysis?.first(where: {
            $0.band == "24" && $0.channel == 5
        })?.recommendationState == .notCandidate)
    }

    @Test("produceCycle gives the explicit region override precedence over defaults")
    func productionCycleOverridePrecedence() async {
        let pipeline = makeCyclePipeline()
        let result = await pipeline.produceCycle(
            networks: [],
            context: cycleContext(
                userRegionOverride: .JP,
                userDefaultsRegionOverride: .US
            )
        )

        #expect(result.inferredRegion.domain == .JP)
        #expect(result.inferredRegion.contributions.first?.kind == .userOverride)
    }

    @Test("produceCycle passes cached device channels and PHY capabilities to recommendations")
    func productionCycleUsesCachedDeviceCapabilities() async {
        let supported6GHz = DevicePHYCapabilities(
            supportsAX: true,
            supportsAC: true,
            supportsN: true,
            supportsBE: false,
            supports6GHz: true,
            supportsDFS: true,
            supports160MHz: false
        )
        let unsupported6GHz = DevicePHYCapabilities(
            supportsAX: true,
            supportsAC: true,
            supportsN: true,
            supportsBE: false,
            supports6GHz: false,
            supportsDFS: true,
            supports160MHz: false
        )
        let pipeline = makeCyclePipeline()
        let supported = await pipeline.produceCycle(
            networks: [],
            context: cycleContext(
                supportedBands: [.band6GHz],
                deviceSupportedChannels: ["3-5"],
                deviceCapabilities: supported6GHz,
                userRegionOverride: .US
            )
        )
        let unsupported = await pipeline.produceCycle(
            networks: [],
            context: cycleContext(
                supportedBands: [.band6GHz],
                deviceSupportedChannels: ["3-5"],
                deviceCapabilities: unsupported6GHz,
                userRegionOverride: .US
            )
        )

        #expect(supported.observation.channelRecommendation?.first(where: {
            $0.band == "6" && $0.channel == 5
        })?.deviceCompatible == true)
        #expect(supported.observation.channelRecommendation?.first(where: {
            $0.band == "6" && $0.channel == 9
        })?.deviceCompatible == false)
        #expect(unsupported.observation.channelRecommendation?.first(where: {
            $0.band == "6" && $0.channel == 5
        })?.deviceCompatible == false)
    }

    @Test("produceCycle returns one complete same-cycle observation")
    func productionCycleIsComplete() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_100)
        let cycleID = UUID()
        let linkEvidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: timestamp,
            interfaceName: "en0",
            mode: .station,
            radio: .reportedOn,
            linkActive: true,
            ssid: "Current",
            bssid: "AA:BB:CC:DD:EE:FF"
        )
        let status = WiFiCurrentStatus(
            timestamp: timestamp,
            interfaceSnapshotCycleID: cycleID,
            interfaceName: "en0",
            interfaceIndex: 4,
            ssid: "Current",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36,
            band: .band5GHz,
            rssi: -50,
            security: "WPA3",
            routerIP: "192.0.2.1",
            isConnected: true,
            isWiFiPowerOn: true,
            linkEvidence: linkEvidence,
            linkAssessment: WiFiLinkInterpreter.evaluate(
                linkEvidence,
                expectedCycleID: cycleID,
                expectedCapturedAt: timestamp
            )
        )
        let latency = GatewayLatencyResult(
            timestamp: timestamp,
            routerIP: "192.0.2.1",
            latencyMs: 18,
            probeOutcome: .replied(milliseconds: 18),
            attemptID: UUID(),
            cycleID: cycleID,
            interfaceName: "en0",
            interfaceBound: true
        )
        let latencyProvider = TestRecordingWiFiBoundGatewayMeasurer(result: latency)
        let pipeline = makeCyclePipeline(
            currentProvider: TestCountingCurrentConnectionProvider(result: status),
            latencyProvider: latencyProvider
        )

        let result = await pipeline.produceCycle(
            networks: [network(ssid: "Current", bssid: "AA:BB:CC:DD:EE:FF", channel: 36, band: .band5GHz, rssi: -50)],
            context: cycleContext(timestamp: timestamp, cycleID: cycleID, supportedBands: [.band5GHz])
        )
        let observation = result.observation

        #expect(observation.timestamp == timestamp)
        #expect(observation.currentStatus == status)
        #expect(observation.environmentSnapshot?.timestamp == timestamp)
        #expect(observation.gatewayLatency == latency)
        #expect(await latencyProvider.measuredTargets.count == 1)
        #expect(await latencyProvider.measuredTargets.first?.interfaceName == "en0")
        #expect(await latencyProvider.measuredTargets.first?.address == "192.0.2.1")
        #expect(await latencyProvider.measuredTargets.first?.snapshotCycleID == cycleID)
        #expect(observation.quality != nil)
        #expect(observation.diagnosis != nil)
        #expect(observation.channelAnalysis?.isEmpty == false)
        #expect(observation.channelRecommendation?.isEmpty == false)
    }

    @Test("produceCycle preserves current status when environment scan fails")
    func productionCyclePreservesCurrentStatusOnEnvironmentFailure() async {
        let status = WiFiCurrentStatus(
            timestamp: Date(),
            ssid: "Current",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36,
            rssi: -50,
            routerIP: "192.0.2.1",
            isConnected: true,
            isWiFiPowerOn: true
        )
        let environmentError = WiFiObservationError.environmentScanFailed("scan failed")
        let pipeline = makeCyclePipeline(
            currentProvider: TestCountingCurrentConnectionProvider(result: status),
            latencyProvider: TestRecordingGatewayLatencyProvider(result: GatewayLatencyResult(
                timestamp: Date(),
                routerIP: "192.0.2.1"
            ))
        )

        let result = await pipeline.produceCycle(
            networks: [],
            context: cycleContext(
                supportedBands: [.band5GHz],
                environmentError: environmentError
            )
        )

        #expect(result.observation.currentStatus == status)
        #expect(result.observation.environmentSnapshot?.error == environmentError)
        #expect(result.observation.errors.contains(environmentError))
        #expect(result.observation.errors.filter { $0 == environmentError }.count == 1)
        #expect(result.observation.gatewayLatency != nil)
        #expect(result.observation.gatewayLatency?.probeOutcome == .notTested)
        #expect(result.observation.quality == nil)
        #expect(result.observation.diagnosis == nil)
        #expect(result.observation.channelAnalysis == nil)
        #expect(result.observation.channelRecommendation == nil)
    }

    @Test("failed cycle replaces current values while retaining bounded history")
    @MainActor
    func storeInvalidatesMissingCurrentFieldsAndRejectsLateProjection() {
        let store = WiFiObservationStore()
        let t1 = Date(timeIntervalSince1970: 1_750_000_200)
        let t2 = t1.addingTimeInterval(5)
        let firstCycle = UUID()
        let secondCycle = UUID()
        let first = WiFiObservation(
            timestamp: t1,
            sourceCycleID: firstCycle,
            currentStatus: WiFiCurrentStatus(timestamp: t1, interfaceName: "en0", ssid: "Known", isConnected: true, isWiFiPowerOn: true),
            environmentSnapshot: WiFiEnvironmentSnapshot(timestamp: t1, networks: [], sourceCycleID: firstCycle),
            gatewayLatency: GatewayLatencyResult(timestamp: t1, routerIP: "192.0.2.1", latencyMs: 8, probeOutcome: .replied(milliseconds: 8), cycleID: firstCycle),
            quality: WiFiQualityResult(level: .good, signalLabel: "Good", latencyLabel: "Good", summary: "Current"),
            channelAnalysis: [],
            channelRecommendation: [],
            diagnosis: DiagnosticResult(icon: "checkmark", title: "Current", message: "Current", severity: .ok)
        )
        let failure = WiFiObservationError.environmentScanFailed("interface unavailable")
        let second = WiFiObservation(
            timestamp: t2,
            sourceCycleID: secondCycle,
            currentStatus: WiFiCurrentStatus(timestamp: t2, interfaceName: "en0", ssid: nil, isConnected: false, isWiFiPowerOn: true),
            environmentSnapshot: WiFiEnvironmentSnapshot(timestamp: t2, networks: [], error: failure, sourceCycleID: secondCycle),
            gatewayLatency: GatewayLatencyResult(timestamp: t2, routerIP: nil, probeOutcome: .notTested, cycleID: secondCycle),
            errors: [failure]
        )

        store.apply(first)
        store.apply(second)
        store.apply(first)

        #expect(store.currentObservation?.sourceCycleID == secondCycle)
        #expect(store.currentStatus?.timestamp == t2)
        #expect(store.latestEnvironmentSnapshot?.sourceCycleID == secondCycle)
        #expect(store.latestEnvironmentSnapshot?.error == failure)
        #expect(store.gatewayLatency?.probeOutcome == .notTested)
        #expect(store.quality == nil)
        #expect(store.channelAnalysis == nil)
        #expect(store.channelRecommendation == nil)
        #expect(store.diagnosis == nil)
        #expect(store.history.count == 2)
        #expect(store.history.map(\.sourceObservationID) == [first.sourceObservationID, second.sourceObservationID])
        #expect(store.validity?.environment == .failed)
        #expect(store.validity?.channelRecommendation == .failed)
        #expect(store.validity(at: t2.addingTimeInterval(20))?.currentStatus == .expired)
        store.expireCurrentValuesIfNeeded(at: t2.addingTimeInterval(20))
        #expect(store.validity?.currentStatus == .expired)
        #expect(store.history.count == 2)
    }

    @Test("source identity is stable for copies and unique for equal timestamps")
    func sourceObservationIdentity() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_250)
        let pipeline = makeCyclePipeline()
        let context = cycleContext(timestamp: timestamp)
        let first = await pipeline.produceCycle(networks: [], context: context).observation
        let copy = first
        let second = await pipeline.produceCycle(networks: [], context: context).observation

        #expect(copy.sourceObservationID == first.sourceObservationID)
        #expect(second.timestamp == first.timestamp)
        #expect(second.sourceCycleID == first.sourceCycleID)
        #expect(second.sourceObservationID != first.sourceObservationID)
        #expect(second != first)
        #expect(first.hasSameContent(as: second))
    }

    @Test("Store rejects changed payload under an existing source identity")
    @MainActor
    func storeRejectsSourceIdentityConflict() {
        let store = WiFiObservationStore()
        let identity = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_750_000_260)
        let original = WiFiObservation(
            sourceObservationID: identity,
            timestamp: timestamp,
            currentStatus: WiFiCurrentStatus(timestamp: timestamp, ssid: "Home", isConnected: false, isWiFiPowerOn: true)
        )
        let conflict = WiFiObservation(
            sourceObservationID: identity,
            timestamp: timestamp,
            currentStatus: WiFiCurrentStatus(timestamp: timestamp, ssid: "Office", isConnected: false, isWiFiPowerOn: true)
        )

        #expect(store.apply(original))
        #expect(!store.apply(conflict))
        #expect(store.history == [original])
        #expect(store.sourceIdentityConflictCount == 1)
    }

    private func makeCyclePipeline(
        currentProvider: some WiFiCurrentConnectionProviding = TestCountingCurrentConnectionProvider(
            result: WiFiCurrentStatus(
                timestamp: Date(),
                isConnected: false,
                isWiFiPowerOn: true
            )
        ),
        latencyProvider: some GatewayLatencyProviding = TestRecordingGatewayLatencyProvider(
            result: GatewayLatencyResult(timestamp: Date())
        )
    ) -> WiFiObservationPipeline {
        WiFiObservationPipeline(
            currentConnectionProvider: currentProvider,
            gatewayLatencyProvider: latencyProvider
        )
    }

    private func cycleContext(
        timestamp: Date = Date(timeIntervalSince1970: 1_750_000_000),
        cycleID: UUID = UUID(),
        supportedBands: Set<ChannelBand> = [.band24GHz, .band5GHz, .band6GHz],
        deviceSupportedChannels: Set<String> = ["2-36", "2-40"],
        deviceCapabilities: DevicePHYCapabilities = .default,
        userRegionOverride: RegulatoryDomain? = nil,
        userDefaultsRegionOverride: RegulatoryDomain? = nil,
        environmentError: WiFiObservationError? = nil
    ) -> WiFiObservationCycleContext {
        WiFiObservationCycleContext(
            timestamp: timestamp,
            interfaceSnapshot: NetworkInterfaceSnapshot(
                cycleID: cycleID,
                capturedAt: timestamp,
                interfaces: []
            ),
            interfaceName: "en0",
            supportedBands: supportedBands,
            supportedChannelsRaw: [(2, 36), (2, 40)],
            deviceSupportedChannels: deviceSupportedChannels,
            deviceCapabilities: deviceCapabilities,
            userRegionOverride: userRegionOverride,
            userDefaultsRegionOverride: userDefaultsRegionOverride,
            environmentError: environmentError
        )
    }

    private func network(
        ssid: String,
        bssid: String,
        channel: Int,
        band: ChannelBand,
        rssi: Int
    ) -> WiFiNetwork {
        WiFiNetwork(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            channel: WiFiChannel(band: band, channelNumber: channel)
        )
    }
}
