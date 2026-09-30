import Foundation
import WiFiLensCore

struct WiFiObservationCycleContext: Sendable {
    let timestamp: Date
    let interfaceSnapshot: NetworkInterfaceSnapshot
    let interfaceName: String?
    let supportedBands: Set<ChannelBand>
    let supportedChannelsRaw: [(Int, Int)]
    let deviceSupportedChannels: Set<String>
    let deviceCapabilities: DevicePHYCapabilities
    let userRegionOverride: RegulatoryDomain?
    let userDefaultsRegionOverride: RegulatoryDomain?
    let environmentError: WiFiObservationError?
}

struct WiFiObservationCycleResult: Sendable {
    let observation: WiFiObservation
    let inferredRegion: RegionInferenceResult
}

protocol WiFiObservationPipelining: Sendable {
    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult
}

struct WiFiObservationPipeline: WiFiObservationPipelining {
    let currentConnectionProvider: WiFiCurrentConnectionProviding
    let gatewayLatencyProvider: GatewayLatencyProviding

    init(
        currentConnectionProvider: WiFiCurrentConnectionProviding = WiFiCurrentConnectionProvider(),
        gatewayLatencyProvider: GatewayLatencyProviding = GatewayLatencyProvider()
    ) {
        self.currentConnectionProvider = currentConnectionProvider
        self.gatewayLatencyProvider = gatewayLatencyProvider
    }

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        let status = await currentConnectionProvider.fetchCurrentStatus(from: context.interfaceSnapshot)
        let latency = await gatewayLatencyProvider.measure(routerIP: status.routerIP)
        let adaptedNetworks = NetworkObservationAdapter.adaptAll(
            networks,
            currentBSSID: status.bssid
        )
        let snapshot = WiFiEnvironmentSnapshot(
            timestamp: context.timestamp,
            interfaceName: context.interfaceName,
            networks: adaptedNetworks,
            error: context.environmentError
        )
        let targetAP = ChannelQualityCalculator.TargetAP(
            bssid: status.bssid,
            ssid: status.ssid,
            channel: status.channel
        )
        let channelAnalysis: [ChannelQuality]? = if context.environmentError == nil {
            ChannelOccupancyAnalyzer.analyze(
                snapshot: snapshot,
                currentChannel: status.channel,
                currentBand: status.band,
                supportedBands: Set(context.supportedBands.map(\.id)),
                targetAP: targetAP
            )
        } else {
            nil
        }
        let inferredRegion = RegulatoryDomainResolver.resolve(
            userOverride: context.userRegionOverride,
            userDefaultsOverride: context.userDefaultsRegionOverride,
            supportedChannelsRaw: context.supportedChannelsRaw,
            apCountryCodes: adaptedNetworks.compactMap { $0.capabilities.countryCode }
        )
        let channelRecommendation: [ChannelRecommendation]? = channelAnalysis.map {
            ChannelRecommendationEngine.recommend(
                channelAnalysis: $0,
                inferredRegion: inferredRegion,
                deviceSupportedChannels: context.deviceSupportedChannels,
                deviceCapabilities: context.deviceCapabilities
            )
        }
        let quality = WiFiQualityEvaluator.evaluate(
            currentStatus: status,
            gatewayLatency: latency
        )
        let diagnosis = DiagnosticEvaluator.evaluate(
            currentStatus: status,
            quality: quality,
            channelAnalysis: channelAnalysis,
            channelRecommendations: channelRecommendation
        )
        let observation = WiFiObservation(
            timestamp: context.timestamp,
            currentStatus: status,
            environmentSnapshot: snapshot,
            gatewayLatency: latency,
            quality: quality,
            channelAnalysis: channelAnalysis,
            channelRecommendation: channelRecommendation,
            diagnosis: diagnosis,
            errors: collectErrors(
                currentStatusError: status.error,
                gatewayLatencyError: latency.error,
                environmentSnapshotError: snapshot.error
            )
        )
        return WiFiObservationCycleResult(
            observation: observation,
            inferredRegion: inferredRegion
        )
    }

    private func collectErrors(
        currentStatusError: WiFiObservationError? = nil,
        gatewayLatencyError: WiFiObservationError? = nil,
        environmentSnapshotError: WiFiObservationError? = nil
    ) -> [WiFiObservationError] {
        [
            currentStatusError,
            gatewayLatencyError,
            environmentSnapshotError,
        ].compactMap { $0 }
    }
}
