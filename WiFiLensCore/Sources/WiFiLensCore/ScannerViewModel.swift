import SwiftUI
import Foundation
import Logging

public enum ScanAccessState: Equatable {
    case waitingForAuthorization
    case denied
    case scanning
    case grantedButSSIDUnavailable
    case scanFailed(String)
}

public struct NetworkTableRow: Identifiable, Hashable {
    public let id: String
    public let bandID: String           // "24"/"5"/"6" — raw identifier, never localized
    public let bandLabel: String
    public let channel: Int
    public let rssi: Int
    public let ssid: String
    public var vendor: String = "—"
    public let bssid: String
    public let color: Color
    public let isFilteredOut: Bool
    public let phyMode: String
    public let channelWidth: String
    public let supportsK: Bool
    public let supportsR: Bool
    public let supportsV: Bool
    public let isHiddenSSID: Bool
    public let security: String
    public let mcs: String
    public let nss: String
    public let country: String
    public let trendArrow: String
    public let trendDelta: Int
    public let isVisible: Bool
    public let visibilityLocked: Bool
    public let qualityScore: Int
    public let lastSeen: String

    public init(
        id: String, bandID: String, bandLabel: String, channel: Int, rssi: Int,
        ssid: String, vendor: String = "—", bssid: String, color: Color,
        isFilteredOut: Bool, phyMode: String, channelWidth: String,
        supportsK: Bool, supportsR: Bool, supportsV: Bool, isHiddenSSID: Bool,
        security: String, mcs: String, nss: String, country: String,
        trendArrow: String, trendDelta: Int, isVisible: Bool,
        visibilityLocked: Bool, qualityScore: Int, lastSeen: String
    ) {
        self.id = id
        self.bandID = bandID
        self.bandLabel = bandLabel
        self.channel = channel
        self.rssi = rssi
        self.ssid = ssid
        self.vendor = vendor
        self.bssid = bssid
        self.color = color
        self.isFilteredOut = isFilteredOut
        self.phyMode = phyMode
        self.channelWidth = channelWidth
        self.supportsK = supportsK
        self.supportsR = supportsR
        self.supportsV = supportsV
        self.isHiddenSSID = isHiddenSSID
        self.security = security
        self.mcs = mcs
        self.nss = nss
        self.country = country
        self.trendArrow = trendArrow
        self.trendDelta = trendDelta
        self.isVisible = isVisible
        self.visibilityLocked = visibilityLocked
        self.qualityScore = qualityScore
        self.lastSeen = lastSeen
    }
}

@MainActor
@Observable
public final class ScannerViewModel {
    private static let logger = Logger(label: "scanner")
    private static let unknownWiFiSampleLimit = 3
    private static let unknownWiFiProbeDelay = Duration.seconds(30)
    public var locationManager: LocationPermissionManager
    let colorHasher = SSIDColorHasher()
    public let signalHistory = SignalHistoryStore()
    let mcpServer = MCPServer()
    public let throughputMonitor = ThroughputMonitor()
    public var hiddenBSSIDs: Set<String> = []
    public var hiddenBands: Set<String> = []       // band IDs ("24"/"5"/"6") to hide
    var hideHiddenSSIDs: Bool = false       // hide networks with empty SSID
    public private(set) var lastNetworks: [WiFiNetwork] = []  // cached for toggle rebuild + MCP
    private(set) var lastObservationTimestamp = Date.distantPast
    private(set) var vendorDatabaseRevision = 0
    private(set) var deduplicatedNetworks: [WiFiNetwork] = []
    private(set) var displayStatesByID: [String: APDisplayState] = [:]
    private(set) var panelFilterQueries: [SpectrumPanelID: String] = [:]
    // Cached derived values for stable reads (Overview hero + network table).
    // Rebuilt only at stable-change boundaries — scan arrival, vendor database
    // refresh, visibility toggles, and global filter/hidden-network changes —
    // never on the 60fps animation tick, which only mutates `displayRSSI`.
    private(set) var cachedTotalNetworks: Int = 0
    private(set) var cachedBandSummary: String = ""
    private(set) var cachedCombinedTableRows: [NetworkTableRow] = []
    let wifiPowerMonitor = WiFiPowerMonitor()
    public internal(set) var wifiPowerState: WiFiPowerState = .unknown

    var band24 = BandChartViewModel(band: .band24GHz)
    var band5 = BandChartViewModel(band: .band5GHz)
    var band6 = BandChartViewModel(band: .band6GHz)
    /// Panel band ViewModels are created lazily when a panel actually requests
    /// a band view. Panels that never open a band (for example a Table-only
    /// panel) do not allocate or refresh these stateful objects.
    private var panelBandViewModelsByID: [SpectrumPanelID: [ChannelBand: BandChartViewModel]] = [:]

    public private(set) var supportedBands: Set<ChannelBand> = []
    public internal(set) var isScanning = false
    public internal(set) var interfaceName: String = ""
    public internal(set) var accessState: ScanAccessState = .waitingForAuthorization
    public var isWiFiAvailable: Bool { wifiPowerState == .poweredOn || wifiPowerState == .unknown }
    public var hasWiFiDataAuthorization: Bool {
        !requiresLiveWiFiAuthorization || locationManager.isAuthorizedForSSID
    }

    private var hasStarted = false
    private var isStartingScan = false
    private var startupTask: Task<Void, Never>?
    private var wifiMonitoringTask: Task<Void, Never>?
    private var unknownWiFiProbeTask: Task<Void, Never>?
    private var consecutiveUnknownWiFiSamples = 0
    private var runtimeLifecycleTail: Task<Void, Never>?
    private var terminationStopTask: Task<Void, Never>?
    private var isTerminating = false
    private var activeProjectionGeneration: UUID?

    public let store: WiFiObservationStore
    public let observationRuntime: WiFiObservationRuntime
    private let authorizationRefresh: @MainActor (LocationPermissionManager) -> Void
    private let requiresLiveWiFiAuthorization: Bool
    private let userDefaults: UserDefaults
    private let vendorResolver: any MACVendorResolving
    private var userDefaultsRegionOverride: RegulatoryDomain?

    public init(
        store: WiFiObservationStore = .shared,
        userDefaults: UserDefaults = .standard,
        vendorResolver: any MACVendorResolving = MACVendorResolver(),
        requiresLiveWiFiAuthorization: Bool = true,
        authorizationRefresh: @escaping @MainActor (LocationPermissionManager) -> Void = { $0.refreshStatus() }
    ) {
        self.store = store
        self.observationRuntime = WiFiObservationRuntime(store: store)
        self.authorizationRefresh = authorizationRefresh
        self.requiresLiveWiFiAuthorization = requiresLiveWiFiAuthorization
        self.locationManager = LocationPermissionManager(liveAuthorizationEnabled: requiresLiveWiFiAuthorization)
        self.userDefaults = userDefaults
        self.vendorResolver = vendorResolver
        self.userDefaultsRegionOverride = Self.regionOverride(
            from: userDefaults.string(forKey: "regulatoryRegionOverride") ?? "auto"
        )
        wifiPowerState = wifiPowerMonitor.currentState
        updateMCPDataProvider()
    }

    public init(
        observationRuntime: WiFiObservationRuntime,
        userDefaults: UserDefaults = .standard,
        vendorResolver: any MACVendorResolving = MACVendorResolver(),
        requiresLiveWiFiAuthorization: Bool = true,
        authorizationRefresh: @escaping @MainActor (LocationPermissionManager) -> Void = { $0.refreshStatus() }
    ) {
        self.store = observationRuntime.store
        self.observationRuntime = observationRuntime
        self.authorizationRefresh = authorizationRefresh
        self.requiresLiveWiFiAuthorization = requiresLiveWiFiAuthorization
        self.locationManager = LocationPermissionManager(liveAuthorizationEnabled: requiresLiveWiFiAuthorization)
        self.userDefaults = userDefaults
        self.vendorResolver = vendorResolver
        self.userDefaultsRegionOverride = Self.regionOverride(
            from: userDefaults.string(forKey: "regulatoryRegionOverride") ?? "auto"
        )
        wifiPowerState = wifiPowerMonitor.currentState
        updateMCPDataProvider()
    }

    /// Trigger the Location Services authorization flow:
    /// - `.notDetermined` → system dialog
    /// - `.denied` → alert offering to open System Settings
    func requestAuthorization() {
        guard requiresLiveWiFiAuthorization else { return }
        locationManager.refreshStatus()
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermissionIfNeeded()
        } else {
            locationManager.showDeniedAlert = true
        }
    }

    var globalFilterQuery: String = "" {
        didSet { applyGlobalFilterToBands() }
    }
    public var selectedNetworkID: String?
    public internal(set) var networkInfo: [NetworkInterfaceInfo] = []
    private(set) var channelQualities: [ChannelQuality] = []

    // Regulatory-aware recommendations (Phase 2: computed alongside channelQualities)
    let regulatoryPipeline = RegulatoryPipeline()
    public internal(set) var channelRecommendations: [ChannelRecommendation] = []
    var inferredRegion: RegionInferenceResult? { regulatoryPipeline.inferredRegion }
    var userRegionOverride: RegulatoryDomain? {
        get { regulatoryPipeline.userRegionOverride }
        set { regulatoryPipeline.userRegionOverride = newValue }
    }

    public var bandViewModels: [BandChartViewModel] {
        [band24, band5, band6].filter { supportedBands.contains($0.band) }
    }

    public var allBandViewModels: [BandChartViewModel] {
        var result = bandViewModels
        result.append(contentsOf: panelBandViewModelsByID.values.flatMap { $0.values })
        return result
    }

    func bandViewModel(for panelID: SpectrumPanelID, band: ChannelBand) -> BandChartViewModel {

        var byBand = panelBandViewModelsByID[panelID] ?? [:]
        if let existing = byBand[band] {
            return existing
        }
        let created = BandChartViewModel(band: band)
        if !interfaceName.isEmpty {
            created.updateInterfaceName(interfaceName)
        }
        byBand[band] = created
        panelBandViewModelsByID[panelID] = byBand
        if !deduplicatedNetworks.isEmpty {
            syncBandViewModel(
                created,
                for: panelID,
                band: band,
                networks: deduplicatedNetworks,
                trends: makeTrends(for: deduplicatedNetworks),
                snapshots: makeSnapshots(for: deduplicatedNetworks)
            )
        }
        return created
    }

    func filterQuery(for panelID: SpectrumPanelID) -> String {
        panelFilterQueries[panelID, default: ""]
    }

    func setFilterQuery(_ query: String, for panelID: SpectrumPanelID) {
        panelFilterQueries[panelID] = query
        refreshPanelBandViewModels(panelID)
    }

    func releasePanelState(for panelID: SpectrumPanelID) {
        panelFilterQueries.removeValue(forKey: panelID)
        panelBandViewModelsByID.removeValue(forKey: panelID)
    }

    func panelBandViewModels(for panelID: SpectrumPanelID) -> [BandChartViewModel] {
        guard let byBand = panelBandViewModelsByID[panelID] else { return [] }
        return Array(byBand.values)
            .filter { supportedBands.contains($0.band) }
    }

    /// Shared history for a selected network, independent of any panel's band
    /// ViewModels. Maps the stable network ID to its BSSID and reads the
    /// shared SignalHistoryStore.
    public func snapshots(for networkID: String) -> [NetworkSnapshot]? {
        guard let bssid = deduplicatedNetworks.first(where: { $0.id == networkID })?.bssid else { return nil }
        return signalHistory.snapshotHistory(for: bssid)
    }

    /// Current-scan heatmap for a single band. It deliberately reads the full
    /// deduplicated scan result and ignores presentation state.
    func heatmapModel(for band: ChannelBand) -> SpectrumHeatmapModel {
        let channels = heatmapChannels(for: band)
        let envelopes = deduplicatedNetworks.compactMap {
            SpectrumHeatmapActivity.envelope(for: $0, band: band)
        }
        return SpectrumHeatmapModel(band: band, channels: channels, envelopes: envelopes)
    }

    /// The heatmap's X-axis channels for a band: the legal channel set from the
    /// regulatory database for the current region (user override first, else the
    /// inferred region), falling back to the US standard plan when the region is
    /// unknown or has no entry. Reuses RegulatoryDatabase so the heatmap and the
    /// rest of the app agree on which channels exist (5 GHz is 36/40/44/…, not
    /// 1...170; 6 GHz is the 1/5/9/… PSC grid).
    private func heatmapChannels(for band: ChannelBand) -> [Int] {
        let region = userRegionOverride ?? inferredRegion?.domain ?? .US
        let allowed = region.allowedChannels(forBand: band.id)
            ?? RegulatoryDomain.US.allowedChannels(forBand: band.id)
            ?? Set(band == .band24GHz ? Array(1...14) : Array(1...band.maxChannel))
        return allowed.sorted()
    }

    /// Cached table rows. Every `NetworkTableRow` field derives from stable
    /// state (true `rssi`, series metadata, display state, vendor database, and
    /// signal history); the animation tick only mutates `displayRSSI`, which
    /// the table never reads. The whole array is therefore cached between
    /// stable-change boundaries and rebuilt only by `rebuildCachedDerivedData`.
    public var combinedTableRows: [NetworkTableRow] {
        cachedCombinedTableRows
    }

    /// Rebuilds all cached derived values from current stable state. Call only
    /// at stable-change boundaries (scan arrival, vendor database refresh,
    /// visibility toggles, global filter/hidden-network changes) — never from
    /// the 60fps animation tick.
    private func rebuildCachedDerivedData() {
        let qualityScores = Dictionary(uniqueKeysWithValues: bandViewModels.flatMap { vm in
            vm.allSeriesData.map { ($0.id, $0.qualityScore) }
        })

        cachedTotalNetworks = bandViewModels.reduce(0) { $0 + $1.allSeriesData.count }
        cachedBandSummary = bandViewModels.map { vm in
            "\(vm.band.displayName): \(vm.allSeriesData.count)"
        }.joined(separator: "  ·  ")

        cachedCombinedTableRows = deduplicatedNetworks.map { network in
            let seriesID = network.id
            let ie = network.ieData.map { IEParser.parse(data: $0) }
            let trend = signalHistory.trend(for: network.bssid)
            let isHiddenSSID = (ie?.isHiddenSSID ?? false) || (network.ssid ?? "").isEmpty
            let displayState = displayStatesByID[seriesID] ?? APDisplayState(
                visibility: automaticVisibility(for: network),
                visibilityLocked: false
            )

            return NetworkTableRow(
                id: seriesID,
                bandID: network.channel.band.id,
                bandLabel: network.channel.band.displayName,
                channel: network.channel.channelNumber,
                rssi: network.rssi,
                ssid: (network.ssid?.isEmpty == false ? network.ssid! : "n/a"),
                vendor: vendorDisplayName(for: network.bssid),
                bssid: network.bssid,
                color: colorHasher.color(for: network.ssid, bssid: network.bssid),
                isFilteredOut: false,
                phyMode: ie.map { phyLabel($0) } ?? "",
                channelWidth: ie.map { chanWidthLabel($0) } ?? "",
                supportsK: ie?.supports80211k ?? false,
                supportsR: ie?.supports80211r ?? false,
                supportsV: ie?.supports80211v ?? false,
                isHiddenSSID: isHiddenSSID,
                security: ie?.securitySummary ?? "",
                mcs: ie?.mcsSummary ?? "",
                nss: ie?.nssSummary ?? "",
                country: ie?.countryCode ?? "",
                trendArrow: trendArrow(for: trend?.direction),
                trendDelta: trend?.delta ?? 0,
                isVisible: displayState.visibility,
                visibilityLocked: displayState.visibilityLocked,
                qualityScore: qualityScores[seriesID] ?? 0,
                lastSeen: ""
            )
        }
    }

    private func vendorDisplayName(for bssid: String) -> String {
        if case let .registered(organization) = vendorResolver.resolve(bssid) {
            return organization
        }
        return ""
    }

    func vendorDatabaseDidChange() {
        vendorDatabaseRevision &+= 1
        rebuildCachedDerivedData()
    }

    /// Effective scan interval in seconds. Writes update the user's requested
    /// interval, while active leases may keep the effective value lower.
    public var scanIntervalSeconds: Int {
        get { effectiveScanIntervalSeconds }
        set {
            requestedScanIntervalSeconds = max(1, newValue)
            applyEffectiveScanInterval()
        }
    }

    private var requestedScanIntervalSeconds = 3
    private var effectiveScanIntervalSeconds = 3
    private var scanIntervalLeases: [UUID: Int] = [:]

    var activeScanIntervalLeaseCount: Int { scanIntervalLeases.count }

    public func acquireScanIntervalLease(seconds: Int) -> UUID {
        let token = UUID()
        if scanIntervalLeases.isEmpty {
            let configuredInterval = userDefaults.integer(forKey: "scanIntervalSeconds")
            if configuredInterval > 0 {
                requestedScanIntervalSeconds = configuredInterval
            }
        }
        scanIntervalLeases[token] = max(1, seconds)
        applyEffectiveScanInterval()
        return token
    }

    public func releaseScanIntervalLease(_ token: UUID) {
        guard scanIntervalLeases.removeValue(forKey: token) != nil else { return }
        applyEffectiveScanInterval()
    }

    private func applyEffectiveScanInterval() {
        let leasedInterval = scanIntervalLeases.values.min()
        let nextInterval = leasedInterval.map {
            min(requestedScanIntervalSeconds, $0)
        } ?? requestedScanIntervalSeconds
        guard effectiveScanIntervalSeconds != nextInterval else { return }

        let previousInterval = effectiveScanIntervalSeconds
        effectiveScanIntervalSeconds = nextInterval
        guard isScanning else { return }
        Self.logger.info("scanIntervalSeconds changed \(previousInterval) → \(nextInterval), restarting scan loop")
        restartScanLoop()
    }

    public func start() async {
        guard !isTerminating else { return }
        if let startupTask {
            await startupTask.value
            return
        }
        guard !hasStarted else { return }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !isTerminating else { return }
            Self.logger.info("start() — begin")

            guard requiresLiveWiFiAuthorization else {
                wifiPowerState = .poweredOn
                await startScanLoop()
                hasStarted = true
                return
            }

            wifiPowerMonitor.startMonitoring()
            locationManager.onAuthorizationGranted = { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.startScanningAfterAuth()
                }
            }

            locationManager.requestPermissionIfNeeded()
            locationManager.refreshStatus()

            // Observe WiFi power state changes — drives scan start/stop
            startWiFiMonitoring()
            reconcileWiFiState(wifiPowerState)
        }

        startupTask = task
        await task.value
        startupTask = nil
    }

    private func startScanningAfterAuth() async {
        guard !isTerminating else { return }
        guard !isStartingScan else { return }
        guard !isScanning else { return }
        // Unknown at process startup is not a radio-off fact. Start one
        // controlled scan loop; WiFiScanner reports interface failures and
        // bounds subsequent probes with backoff.
        guard wifiPowerState != .poweredOff else { return }
        isStartingScan = true
        defer { isStartingScan = false }
        let stored = userDefaults.integer(forKey: "scanIntervalSeconds")
        scanIntervalSeconds = stored > 0 ? stored : 3
        await startScanLoop()
        hasStarted = true
    }

    public func handleSceneDidBecomeActive() async {
        guard !isTerminating else { return }
        guard requiresLiveWiFiAuthorization else { return }
        // This callback may be delivered by more than one window. App focus is
        // not a link-continuity boundary; the center only refreshes evidence.
        await WiFiLinkStateCenter.shared.applicationBecameActive()
        locationManager.refreshStatus()
        wifiPowerMonitor.refreshState()
        reconcileWiFiState(wifiPowerMonitor.currentState)
    }

    private func startWiFiMonitoring() {
        guard !isTerminating else { return }
        guard wifiMonitoringTask == nil else { return }

        wifiMonitoringTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.wifiPowerMonitor.events
            for await state in stream {
                self.reconcileWiFiState(state)
            }
        }
    }

    private func reconcileWiFiState(_ state: WiFiPowerState) {
        guard requiresLiveWiFiAuthorization else {
            wifiPowerState = .poweredOn
            updateMCPDataProvider()
            return
        }
        wifiPowerState = state
        updateMCPDataProvider()
        guard !isTerminating else { return }

        switch state {
        case .poweredOn:
            consecutiveUnknownWiFiSamples = 0
            cancelUnknownWiFiProbe()
            if locationManager.isAuthorizedForSSID {
                Task { await startScanningAfterAuth() }
            } else if locationManager.authorizationStatus == .notDetermined {
                accessState = .waitingForAuthorization
                Self.logger.info("reconcileWiFiState() — waiting for authorization callback")
            } else {
                Self.logger.warning("reconcileWiFiState() — authorization denied/restricted")
                accessState = .denied
                stop()
            }

        case .poweredOff:
            consecutiveUnknownWiFiSamples = 0
            cancelUnknownWiFiProbe()
            stop()

        case .interfaceUnavailable:
            consecutiveUnknownWiFiSamples = 0
            cancelUnknownWiFiProbe()
            // Keep one scanner loop alive as a bounded recovery probe. The
            // scan source reports the missing interface and backs off; it is
            // not converted into link-state evidence.
            guard locationManager.isAuthorizedForSSID else {
                if locationManager.authorizationStatus == .notDetermined {
                    accessState = .waitingForAuthorization
                } else {
                    accessState = .denied
                    stop()
                }
                return
            }
            if !isScanning {
                Task { await startScanningAfterAuth() }
            }

        case .unknown:
            // One or two samples can be transient CoreWLAN read failures.
            // Persistent ambiguity pauses frequent scans and leaves a bounded
            // retry scheduled so later evidence can recover automatically.
            guard locationManager.isAuthorizedForSSID else {
                if locationManager.authorizationStatus == .notDetermined {
                    accessState = .waitingForAuthorization
                } else {
                    accessState = .denied
                    stop()
                }
                return
            }
            consecutiveUnknownWiFiSamples += 1
            if isScanning, consecutiveUnknownWiFiSamples >= Self.unknownWiFiSampleLimit {
                stop()
                accessState = .scanFailed("Wi-Fi status is unknown; scanning is paused temporarily.")
                scheduleUnknownWiFiProbe()
            } else if !isScanning, !hasStarted, unknownWiFiProbeTask == nil {
                Task { await startScanningAfterAuth() }
            }
        }
    }

    private func scheduleUnknownWiFiProbe() {
        guard unknownWiFiProbeTask == nil, !isTerminating else { return }
        unknownWiFiProbeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.unknownWiFiProbeDelay)
            } catch {
                return
            }
            guard let self else { return }
            unknownWiFiProbeTask = nil
            guard !isTerminating, wifiPowerState == .unknown,
                  locationManager.isAuthorizedForSSID else { return }
            consecutiveUnknownWiFiSamples = 0
            await startScanningAfterAuth()
        }
    }

    private func cancelUnknownWiFiProbe() {
        unknownWiFiProbeTask?.cancel()
        unknownWiFiProbeTask = nil
    }

    private func updateMCPDataProvider() {
        mcpServer.snapshotProvider = { [weak self] in
            self?.makeMCPSnapshot() ?? .empty
        }
    }

    public func stopMCPServer() {
        mcpServer.stop()
    }

    public func startMCPServer(port: UInt16) async throws {
        mcpServer.port = port
        try await mcpServer.start()
    }

    func makeMCPSnapshot() -> MCPSnapshot {
        let scanContextIsCurrent = isWiFiAvailable
        let capturedAt = lastObservationTimestamp == .distantPast ? nil : lastObservationTimestamp
        let powerState: MCPSnapshot.PowerState
        switch wifiPowerState {
        case .poweredOn: powerState = .poweredOn
        case .poweredOff: powerState = .poweredOff
        case .interfaceUnavailable: powerState = .interfaceUnavailable
        case .unknown: powerState = .unknown
        }

        let accessState: MCPSnapshot.AccessState
        switch self.accessState {
        case .waitingForAuthorization: accessState = .waitingForAuthorization
        case .denied: accessState = .denied
        case .scanning: accessState = .scanning
        case .grantedButSSIDUnavailable: accessState = .grantedButSSIDUnavailable
        case .scanFailed: accessState = .scanFailed
        }

        return MCPSnapshot(
            networks: scanContextIsCurrent ? lastNetworks : [],
            capturedAt: scanContextIsCurrent ? capturedAt : nil,
            interfaceName: scanContextIsCurrent && !interfaceName.isEmpty ? interfaceName : nil,
            isScanning: isScanning,
            powerState: powerState,
            accessState: accessState,
            supportedBands: scanContextIsCurrent
                ? ChannelBand.allCases.filter { supportedBands.contains($0) }.map(\.id)
                : [],
            scanIntervalSeconds: effectiveScanIntervalSeconds
        )
    }

    private func restartScanLoop() {
        guard !isTerminating else { return }
        let configuration = runtimeConfiguration
        enqueueRuntimeLifecycle { [weak self] in
            await self?.observationRuntime.restartScanning(configuration: configuration)
        }
    }

    private func startScanLoop() async {
        guard !isTerminating else { return }
        Self.logger.info("startScanLoop() — starting with interval \(scanIntervalSeconds)s")
        isScanning = true
        accessState = .scanning
        throughputMonitor.start()
        let configuration = runtimeConfiguration
        let generation = UUID()
        activeProjectionGeneration = generation
        let command = enqueueRuntimeLifecycle { [weak self] in
            guard let self else { return }
            await self.observationRuntime.startScanning(
                configuration: configuration,
                isPublicationEligible: { [weak self] in
                    self?.isRuntimePublicationEligible(for: generation) ?? false
                }
            ) { [weak self] output in
                self?.handleRuntimeOutput(output, generation: generation)
            }
        }
        await command.value
    }

    private var runtimeConfiguration: WiFiObservationRuntimeConfiguration {
        return WiFiObservationRuntimeConfiguration(
            scanInterval: .seconds(effectiveScanInterval(configured: scanIntervalSeconds)),
            userRegionOverride: userRegionOverride,
            userDefaultsRegionOverride: userDefaultsRegionOverride
        )
    }

    private func effectiveScanInterval(configured: Int) -> Int {
        let configured = max(1, configured)
        guard let leasedInterval = scanIntervalLeases.values.min() else { return configured }
        return min(configured, leasedInterval)
    }

    public func handleRegulatoryRegionOverrideChange(_ rawValue: String) {
        let newOverride = Self.regionOverride(from: rawValue)
        guard newOverride != userDefaultsRegionOverride else { return }
        userDefaultsRegionOverride = newOverride
        if isScanning {
            restartScanLoop()
        }
    }

    /// Requests an immediate restart of the shared scan loop. Used by pages
    /// that offer a manual rescan action; never starts a second scan loop.
    public func requestImmediateRescan() {
        guard isScanning, !isTerminating else { return }
        restartScanLoop()
    }

    private static func regionOverride(from rawValue: String) -> RegulatoryDomain? {
        rawValue == "auto" ? nil : RegulatoryDomain(rawValue: rawValue)
    }

    private func handleRuntimeOutput(_ output: WiFiObservationScanOutput, generation: UUID) {
        guard activeProjectionGeneration == generation, isScanning else { return }
        supportedBands = output.supportedBands
        interfaceName = output.interfaceName ?? output.cycle.observation.currentStatus?.interfaceName ?? ""
        for viewModel in allBandViewModels {
            viewModel.updateInterfaceName(interfaceName)
        }
        networkInfo = output.interfaceSnapshot.interfaces

        if let error = output.cycle.observation.environmentSnapshot?.error {
            Self.logger.error("scan failure: \(String(describing: error))")
            accessState = .scanFailed(String(describing: error))
            // supportedBands may have changed even though no networks were
            // applied; refresh the caches so band/count reads stay consistent.
            rebuildCachedDerivedData()
            return
        }

        accessState = .scanning

        channelQualities = output.cycle.observation.channelAnalysis ?? []
        channelRecommendations = output.cycle.observation.channelRecommendation ?? []
        regulatoryPipeline.inferredRegion = output.cycle.inferredRegion

        lastObservationTimestamp = output.cycle.observation.timestamp
        ingestNetworks(output.rawNetworks, timestamp: lastObservationTimestamp)
    }

    private func deduplicateNetworks(_ networks: [WiFiNetwork]) -> [WiFiNetwork] {
        var seen: [String: Int] = [:]
        var deduplicated: [WiFiNetwork] = []
        for nw in networks {
            let key = "\(nw.bssid)-\(nw.channel.channelNumber)-\(nw.channel.band.rawValue)"
            if let index = seen[key] {
                if nw.rssi > deduplicated[index].rssi {
                    deduplicated[index] = nw
                }
            } else {
                seen[key] = deduplicated.count
                deduplicated.append(nw)
            }
        }
        return deduplicated
    }

    private func makeSnapshot(for network: WiFiNetwork, timestamp: Date) -> NetworkSnapshot {
        let ie = network.ieData.map { IEParser.parse(data: $0) }
        let phyMode = ie.map { phyLabel($0) } ?? ""
        let channelWidth = ie.map { chanWidthLabel($0) } ?? ""
        let ssid = network.ssid ?? ""
        let mcs = ie?.mcsSummary ?? ""
        let nss = ie?.nssSummary ?? ""
        let security = ie?.securitySummary ?? ""
        let country = ie?.countryCode ?? ""
        let supportsK = ie?.supports80211k ?? false
        let supportsR = ie?.supports80211r ?? false
        let supportsV = ie?.supports80211v ?? false
        let supportsWPA3 = ie?.supportsWPA3 ?? false
        let isHiddenSSID = ie?.isHiddenSSID ?? false

        return NetworkSnapshot(
            timestamp: timestamp,
            bssid: network.bssid,
            ssid: ssid,
            rssi: network.rssi,
            channel: network.channel.channelNumber,
            band: network.channel.band.id,
            phyMode: phyMode,
            channelWidth: channelWidth,
            channelWidthMHz: network.channel.channelWidthMHz,
            mcs: mcs,
            nss: nss,
            security: security,
            country: country,
            supportsK: supportsK,
            supportsR: supportsR,
            supportsV: supportsV,
            supportsWPA3: supportsWPA3,
            isHiddenSSID: isHiddenSSID
        )
    }

    private func makeTrends(for networks: [WiFiNetwork]) -> [String: (direction: TrendDirection, delta: Int)] {
        var trends: [String: (direction: TrendDirection, delta: Int)] = [:]
        for network in networks {
            if let trend = signalHistory.trend(for: network.bssid) {
                trends[network.bssid] = trend
            }
        }
        return trends
    }

    private func makeSnapshots(for networks: [WiFiNetwork]) -> [String: [NetworkSnapshot]] {
        var snapshots: [String: [NetworkSnapshot]] = [:]
        for network in networks {
            if let history = signalHistory.snapshotHistory(for: network.bssid) {
                snapshots[network.bssid] = history
            }
        }
        return snapshots
    }

    private func recomputeDisplayStates(for networks: [WiFiNetwork]) -> [String: APDisplayState] {
        var nextStates: [String: APDisplayState] = [:]
        for network in networks {
            let seriesID = network.id
            let previous = displayStatesByID[seriesID] ?? APDisplayState(
                visibility: automaticVisibility(for: network),
                visibilityLocked: false
            )

            if previous.visibilityLocked {
                nextStates[seriesID] = previous
            } else {
                nextStates[seriesID] = APDisplayState(
                    visibility: automaticVisibility(for: network),
                    visibilityLocked: false
                )
            }
        }
        return nextStates
    }

    private func recomputePanelDisplayStates(
        for networks: [WiFiNetwork],
        panelID: SpectrumPanelID
    ) -> [String: APDisplayState] {
        let needle = filterQuery(for: panelID).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return displayStatesByID
        }

        var nextStates: [String: APDisplayState] = [:]
        for network in networks {
            let seriesID = network.id
            let baseState = displayStatesByID[seriesID] ?? APDisplayState(
                visibility: automaticVisibility(for: network),
                visibilityLocked: false
            )

            if baseState.visibilityLocked {
                nextStates[seriesID] = baseState
                continue
            }

            let ssid = (network.ssid ?? "").lowercased()
            let bssid = network.bssid.lowercased()
            let queryMatches = ssid.contains(needle) || bssid.contains(needle)
            nextStates[seriesID] = APDisplayState(
                visibility: baseState.visibility && queryMatches,
                visibilityLocked: false
            )
        }
        return nextStates
    }

    private func refreshBandViewModels(
        for panelID: SpectrumPanelID,
        with networks: [WiFiNetwork],
        trends: [String: (direction: TrendDirection, delta: Int)],
        snapshots: [String: [NetworkSnapshot]]
    ) {
        if supportedBands.contains(.band24GHz),
           let vm = panelBandViewModelsByID[panelID]?[.band24GHz] {
            syncBandViewModel(
                vm,
                for: panelID,
                band: .band24GHz,
                networks: networks,
                trends: trends,
                snapshots: snapshots
            )
        }

        if supportedBands.contains(.band5GHz),
           let vm = panelBandViewModelsByID[panelID]?[.band5GHz] {
            syncBandViewModel(
                vm,
                for: panelID,
                band: .band5GHz,
                networks: networks,
                trends: trends,
                snapshots: snapshots
            )
        }

        if supportedBands.contains(.band6GHz),
           let vm = panelBandViewModelsByID[panelID]?[.band6GHz] {
            syncBandViewModel(
                vm,
                for: panelID,
                band: .band6GHz,
                networks: networks,
                trends: trends,
                snapshots: snapshots
            )
        }
    }

    private func syncBandViewModel(
        _ vm: BandChartViewModel,
        for panelID: SpectrumPanelID,
        band: ChannelBand,
        networks: [WiFiNetwork],
        trends: [String: (direction: TrendDirection, delta: Int)],
        snapshots: [String: [NetworkSnapshot]]
    ) {
        let panelDisplayStates = recomputePanelDisplayStates(for: networks, panelID: panelID)
        let sorted = networks
            .filter { $0.channel.band == band }
            .sorted { $0.channel.channelNumber < $1.channel.channelNumber }
        vm.updateNetworks(
            sorted,
            colorHasher: colorHasher,
            displayStatesByID: panelDisplayStates,
            trends: trends,
            snapshots: snapshots
        )
    }

    private func refreshPanelBandViewModels(_ panelID: SpectrumPanelID) {
        refreshBandViewModels(
            for: panelID,
            with: deduplicatedNetworks,
            trends: makeTrends(for: deduplicatedNetworks),
            snapshots: makeSnapshots(for: deduplicatedNetworks)
        )
    }

    private func refreshAllPanelBandViewModels() {
        let networks = deduplicatedNetworks
        refreshAllPanelBandViewModels(
            with: networks,
            trends: makeTrends(for: networks),
            snapshots: makeSnapshots(for: networks)
        )
    }

    private func refreshAllPanelBandViewModels(
        with networks: [WiFiNetwork],
        trends: [String: (direction: TrendDirection, delta: Int)],
        snapshots: [String: [NetworkSnapshot]]
    ) {
        for panelID in panelBandViewModelsByID.keys {
            refreshBandViewModels(
                for: panelID,
                with: networks,
                trends: trends,
                snapshots: snapshots
            )
        }
    }

    private func automaticVisibility(for network: WiFiNetwork) -> Bool {
        if hiddenBSSIDs.contains(network.bssid) {
            return false
        }

        if hiddenBands.contains(network.channel.band.id) {
            return false
        }

        let ie = network.ieData.map { IEParser.parse(data: $0) }
        let isHiddenSSID = (ie?.isHiddenSSID ?? false) || (network.ssid ?? "").isEmpty
        if hideHiddenSSIDs && isHiddenSSID {
            return false
        }

        return true
    }

    private func trendArrow(for direction: TrendDirection?) -> String {
        switch direction {
        case .up: "▲"
        case .down: "▼"
        case .stable: "●"
        case .none: ""
        }
    }


    private func ingestNetworks(_ networks: [WiFiNetwork], timestamp: Date) {
        lastNetworks = networks
        let deduped = deduplicateNetworks(networks)
        deduplicatedNetworks = deduped

        // Record RSSI history and snapshots using the observation cycle
        // timestamp so pending-cycle replays carry the actual capture time,
        // not the wall-clock moment they reached MainActor.
        for nw in deduped {
            let snap = makeSnapshot(for: nw, timestamp: timestamp)
            signalHistory.record(bssid: nw.bssid, rssi: nw.rssi, snapshot: snap)
        }
        rebuildProjection()
    }

    private func rebuildProjection() {
        let deduped = deduplicatedNetworks
        var trends: [String: (direction: TrendDirection, delta: Int)] = [:]
        for nw in deduped {
            if let t = signalHistory.trend(for: nw.bssid) {
                trends[nw.bssid] = t
            }
        }
        var snapshotDict: [String: [NetworkSnapshot]] = [:]
        for nw in deduped {
            if let snaps = signalHistory.snapshotHistory(for: nw.bssid) { snapshotDict[nw.bssid] = snaps }
        }
        displayStatesByID = recomputeDisplayStates(for: deduped)

        let sorted24 = deduped
            .filter { $0.channel.band == .band24GHz }
            .sorted { $0.channel.channelNumber < $1.channel.channelNumber }
        if supportedBands.contains(.band24GHz) {
            band24.updateNetworks(sorted24, colorHasher: colorHasher, filterQuery: globalFilterQuery, trends: trends, snapshots: snapshotDict, hiddenBSSIDs: hiddenBSSIDs, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        }

        let sorted5 = deduped
            .filter { $0.channel.band == .band5GHz }
            .sorted { $0.channel.channelNumber < $1.channel.channelNumber }
        if supportedBands.contains(.band5GHz) {
            band5.updateNetworks(sorted5, colorHasher: colorHasher, filterQuery: globalFilterQuery, trends: trends, snapshots: snapshotDict, hiddenBSSIDs: hiddenBSSIDs, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        }

        let sorted6 = deduped
            .filter { $0.channel.band == .band6GHz }
            .sorted { $0.channel.channelNumber < $1.channel.channelNumber }
        if supportedBands.contains(.band6GHz) {
            band6.updateNetworks(sorted6, colorHasher: colorHasher, filterQuery: globalFilterQuery, trends: trends, snapshots: snapshotDict, hiddenBSSIDs: hiddenBSSIDs, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        }
        refreshAllPanelBandViewModels(with: deduped, trends: trends, snapshots: snapshotDict)

        // Validate selected network still exists in the new scan
        if let selectedID = selectedNetworkID {
            let allIDs = bandViewModels.flatMap { $0.allSeriesData.map(\.id) }
            if !allIDs.contains(selectedID) {
                selectedNetworkID = nil
            }
        }

        let ssidCount = bandViewModels.reduce(0) { count, vm in
            count + vm.allSeriesData.filter { $0.ssid != "n/a" }.count
        }
        accessState = ssidCount > 0 ? .scanning : .grantedButSSIDUnavailable

        rebuildCachedDerivedData()
    }

    func applyGlobalFilterToBands() {
        band24.applyFilter(globalFilterQuery, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        band5.applyFilter(globalFilterQuery, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        band6.applyFilter(globalFilterQuery, hiddenBands: hiddenBands, hideHiddenSSIDs: hideHiddenSSIDs)
        displayStatesByID = recomputeDisplayStates(for: deduplicatedNetworks)
        refreshAllPanelBandViewModels()
        rebuildCachedDerivedData()
    }

    public func toggleVisibility(seriesID: String) {
        let current = displayStatesByID[seriesID] ?? APDisplayState(visibility: true, visibilityLocked: false)
        displayStatesByID[seriesID] = APDisplayState(
            visibility: !current.visibility,
            visibilityLocked: current.visibilityLocked
        )
        refreshAllPanelBandViewModels()
        rebuildCachedDerivedData()
    }

    func toggleVisibilityLocked(seriesID: String) {
        let current = displayStatesByID[seriesID] ?? APDisplayState(visibility: true, visibilityLocked: false)
        displayStatesByID[seriesID] = APDisplayState(
            visibility: current.visibility,
            visibilityLocked: !current.visibilityLocked
        )
        refreshAllPanelBandViewModels()
        rebuildCachedDerivedData()
    }

    public func toggleVisibility(bssid: String) {
        if hiddenBSSIDs.contains(bssid) {
            hiddenBSSIDs.remove(bssid)
        } else {
            hiddenBSSIDs.insert(bssid)
        }
        rebuildProjection()
    }

    public func stop() {
        cancelUnknownWiFiProbe()
        activeProjectionGeneration = nil
        transitionToStoppedState()
        guard !isTerminating else { return }
        enqueueRuntimeLifecycle { [weak self] in
            await self?.observationRuntime.stopScanning()
        }
    }

    public func stopForTermination() async {
        if let terminationStopTask {
            await terminationStopTask.value
            return
        }

        isTerminating = true
        startupTask?.cancel()
        startupTask = nil
        wifiMonitoringTask?.cancel()
        wifiMonitoringTask = nil
        cancelUnknownWiFiProbe()
        wifiPowerMonitor.stopMonitoring()
        await WiFiLinkStateCenter.shared.stop()
        runtimeLifecycleTail?.cancel()
        activeProjectionGeneration = nil
        transitionToStoppedState()

        let runtime = observationRuntime
        let stopTask = Task { @MainActor in
            await runtime.stopScanning()
        }
        terminationStopTask = stopTask
        runtimeLifecycleTail = stopTask
        await stopTask.value
    }

    private func isRuntimePublicationEligible(for generation: UUID) -> Bool {
        guard activeProjectionGeneration == generation, isScanning else { return false }

        guard requiresLiveWiFiAuthorization else { return true }

        wifiPowerMonitor.refreshState()
        let currentPowerState = wifiPowerMonitor.currentState
        if currentPowerState == .poweredOff {
            wifiPowerState = currentPowerState
            updateMCPDataProvider()
            transitionToStoppedState()
            return false
        }

        authorizationRefresh(locationManager)
        guard locationManager.isAuthorizedForSSID else {
            transitionToStoppedState()
            accessState = locationManager.authorizationStatus == .notDetermined
                ? .waitingForAuthorization
                : .denied
            return false
        }
        return true
    }

    private func transitionToStoppedState() {
        isScanning = false
        throughputMonitor.stop()
    }

    @discardableResult
    private func enqueueRuntimeLifecycle(
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        guard !isTerminating else { return Task {} }
        let previous = runtimeLifecycleTail
        let command = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, !self.isTerminating else { return }
            await operation()
        }
        runtimeLifecycleTail = command
        return command
    }

    private func phyLabel(_ ie: IEData) -> String {
        if ie.heSupported { return "ax" }
        if ie.vhtSupported { return "ac" }
        if ie.htSupported { return "n" }
        return ""
    }

    private func chanWidthLabel(_ ie: IEData) -> String {
        ie.operatingChannelWidth?.label ?? ""
    }
}

#if DEBUG
extension ScannerViewModel {
    func debugApplyNetworksForTesting(
        _ networks: [WiFiNetwork],
        supportedBands: Set<ChannelBand>,
        timestamp: Date = Date()
    ) {
        self.supportedBands = supportedBands
        self.lastObservationTimestamp = timestamp
        ingestNetworks(networks, timestamp: timestamp)
    }

    func debugStartScanLoopForTesting() async {
        await startScanLoop()
    }

    func debugStartAfterAuthorizationForTesting() async {
        await startScanningAfterAuth()
    }

    func debugReconcileWiFiStateForTesting(_ state: WiFiPowerState) {
        reconcileWiFiState(state)
    }

    func debugDrainRuntimeLifecycleForTesting() async {
        await runtimeLifecycleTail?.value
    }

    func debugStartWiFiMonitoringForTesting() {
        wifiPowerMonitor.startMonitoring()
        startWiFiMonitoring()
    }

    var debugHasActiveWiFiMonitoringForTesting: Bool {
        wifiMonitoringTask != nil && wifiPowerMonitor.debugIsMonitoringForTesting
    }
}
#endif
