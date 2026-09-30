import Foundation

public struct WiFiObservationCycleContext: Sendable {
    public init(timestamp: Date, interfaceSnapshot: NetworkInterfaceSnapshot, interfaceName: String?, supportedBands: Set<ChannelBand>, supportedChannelsRaw: [(Int, Int)], deviceSupportedChannels: Set<String>, deviceCapabilities: DevicePHYCapabilities, userRegionOverride: RegulatoryDomain?, userDefaultsRegionOverride: RegulatoryDomain?, environmentError: WiFiObservationError?) {
        self.timestamp = timestamp; self.interfaceSnapshot = interfaceSnapshot; self.interfaceName = interfaceName; self.supportedBands = supportedBands
        self.supportedChannelsRaw = supportedChannelsRaw; self.deviceSupportedChannels = deviceSupportedChannels; self.deviceCapabilities = deviceCapabilities
        self.userRegionOverride = userRegionOverride; self.userDefaultsRegionOverride = userDefaultsRegionOverride; self.environmentError = environmentError
    }
    public let timestamp: Date
    public let interfaceSnapshot: NetworkInterfaceSnapshot
    public let interfaceName: String?
    public let supportedBands: Set<ChannelBand>
    public let supportedChannelsRaw: [(Int, Int)]
    public let deviceSupportedChannels: Set<String>
    public let deviceCapabilities: DevicePHYCapabilities
    public let userRegionOverride: RegulatoryDomain?
    public let userDefaultsRegionOverride: RegulatoryDomain?
    public let environmentError: WiFiObservationError?
}

public struct WiFiObservationCycleResult: Sendable {
    public init(observation: WiFiObservation, inferredRegion: RegionInferenceResult) { self.observation = observation; self.inferredRegion = inferredRegion }
    public let observation: WiFiObservation
    public let inferredRegion: RegionInferenceResult
}

public protocol WiFiObservationPipelining: Sendable {
    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult
}

public struct WiFiObservationPipeline: WiFiObservationPipelining {
    let currentConnectionProvider: WiFiCurrentConnectionProviding
    let gatewayLatencyProvider: GatewayLatencyProviding

    public init(
        currentConnectionProvider: WiFiCurrentConnectionProviding = WiFiCurrentConnectionProvider(),
        gatewayLatencyProvider: GatewayLatencyProviding = GatewayLatencyProvider()
    ) {
        self.currentConnectionProvider = currentConnectionProvider
        self.gatewayLatencyProvider = gatewayLatencyProvider
    }

    public func produceCycle(
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
