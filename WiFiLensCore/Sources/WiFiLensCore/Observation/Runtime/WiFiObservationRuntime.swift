import Foundation
import OSLog

public enum WiFiObservationLifecycleEvent: Sendable {
    case started(at: Date, expectedInterval: Duration)
    case stopped(at: Date)
}

@MainActor
public protocol WiFiObservationConsuming: AnyObject {
    func consume(_ observation: WiFiObservation) async throws
    func consumeLifecycle(_ event: WiFiObservationLifecycleEvent) async throws
}

extension WiFiObservationConsuming {
    func consumeLifecycle(_ event: WiFiObservationLifecycleEvent) async throws { _ = event }
}

struct ObservationConsumerDiagnostics: Equatable, Sendable {
    public let pendingCount: Int
    let oldestObservationTimestamp: Date?
    let failureCount: Int
}

struct RawCycleDeliveryDiagnostics: Equatable, Sendable {
    let replacementCount: UInt64
    let hasInFlight: Bool
    let hasPending: Bool
}

struct WiFiObservationRuntimeConfiguration: Sendable {
    public init(scanInterval: Duration, userRegionOverride: RegulatoryDomain? = nil, userDefaultsRegionOverride: RegulatoryDomain? = nil) {
        self.scanInterval = scanInterval; self.userRegionOverride = userRegionOverride; self.userDefaultsRegionOverride = userDefaultsRegionOverride
    }
    var scanInterval: Duration
    var userRegionOverride: RegulatoryDomain?
    var userDefaultsRegionOverride: RegulatoryDomain?
}

struct WiFiObservationScanOutput: Sendable {
    let rawNetworks: [WiFiNetwork]
    public let cycle: WiFiObservationCycleResult
    let interfaceSnapshot: NetworkInterfaceSnapshot
    public let interfaceName: String?
    public let supportedBands: Set<ChannelBand>
}

@MainActor
public final class WiFiObservationRuntime {
    public let store: WiFiObservationStore

    private struct CapabilityCache: Sendable {
        let interfaceName: String?
        let supportedBands: Set<ChannelBand>
        let supportedChannelsRaw: [(Int, Int)]
        let deviceSupportedChannels: Set<String>
        let deviceCapabilities: DevicePHYCapabilities
    }

    private struct RawCycleAdmission: Sendable {
        let event: WiFiScanEvent
        let configuration: WiFiObservationRuntimeConfiguration
        let cache: CapabilityCache
        let generation: UUID
    }

    private let pipeline: any WiFiObservationPipelining
    private let scanSource: any WiFiScanStreaming
    private let interfaceSource: any NetworkInterfaceSnapshotSourcing
    private var workers: [ObjectIdentifier: ObservationConsumerWorker] = [:]
    private var rawCycleTask: Task<Void, Never>?
    private var pendingRawCycle: RawCycleAdmission?
    private var rawCycleReplacementCount: UInt64 = 0
    private var activeScanGeneration: UUID?
    private var activeLifecycleGeneration: UUID?
    /// Active lifecycle facts kept after the start broadcast so consumers that
    /// register later (e.g. AP Radar joining an already-running scan) can be
    /// replayed the current expected scan interval instead of guessing.
    private var activeLifecycleStartedAt: Date?
    private var activeScanInterval: Duration?
    /// Chains lifecycle replays so tests can drain them deterministically.
    private var lifecycleReplayTail: Task<Void, Never>?
    private var outputProjection: (@MainActor (WiFiObservationScanOutput) -> Void)?
    private var requestedOutputProjection: (@MainActor (WiFiObservationScanOutput) -> Void)?
    private var publicationEligibility: (@MainActor () -> Bool)?
    private var requestedPublicationEligibility: (@MainActor () -> Bool)?
    private var latestLifecycleRequestID: UInt64 = 0
    private var lifecycleCommandTail: Task<Void, Never>?
    private let now: @Sendable () -> Date
#if DEBUG
    var onActiveScanStoppedForTesting: (@MainActor () -> Void)?
    var onConsumerDrainStartedForTesting: (@MainActor () -> Void)?

    func drainRawCyclesForTesting() async {
        while let task = rawCycleTask {
            await task.value
        }
    }

    /// Waits for every pending lifecycle replay scheduled by `addConsumer`.
    ///
    /// The tail is cleared before awaiting so a completed replay does not make
    /// this loop re-await the same finished task forever; a replay added while
    /// draining is picked up by the next iteration.
    func drainLifecycleReplaysForTesting() async {
        while let task = lifecycleReplayTail {
            lifecycleReplayTail = nil
            await task.value
        }
    }
#endif

    public convenience init(store: WiFiObservationStore = .shared) {
        self.init(
            store: store,
            pipeline: WiFiObservationPipeline(),
            scanSource: WiFiScanner(),
            interfaceSource: SystemNetworkInterfaceSnapshotSource(),
            now: { Date() }
        )
    }

    public convenience init(
        store: WiFiObservationStore,
        scanSource: any WiFiScanStreaming,
        interfaceSource: any NetworkInterfaceSnapshotSourcing
    ) {
        self.init(
            store: store,
            pipeline: WiFiObservationPipeline(),
            scanSource: scanSource,
            interfaceSource: interfaceSource,
            now: { Date() }
        )
    }

    init(
        store: WiFiObservationStore,
        pipeline: any WiFiObservationPipelining = WiFiObservationPipeline(),
        scanSource: any WiFiScanStreaming = WiFiScanner(),
        interfaceSource: any NetworkInterfaceSnapshotSourcing = SystemNetworkInterfaceSnapshotSource(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.pipeline = pipeline
        self.scanSource = scanSource
        self.interfaceSource = interfaceSource
        self.now = now
    }

    public func addConsumer(_ consumer: any WiFiObservationConsuming) {
        let identifier = ObjectIdentifier(consumer)
        guard workers[identifier] == nil else { return }
        let worker = ObservationConsumerWorker(consumer: consumer)
        workers[identifier] = worker
        // Replay the active lifecycle to consumers that join after the scan
        // already started so they observe the real expected scan interval
        // (and therefore the correct signal-loss timeout) without waiting for
        // the next restart. The generation guard drops the replay if the scan
        // stops or restarts before it runs.
        guard let startedAt = activeLifecycleStartedAt,
              let interval = activeScanInterval,
              let generation = activeLifecycleGeneration else { return }
        let previous = lifecycleReplayTail
        lifecycleReplayTail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self,
                  self.activeLifecycleGeneration == generation,
                  self.workers[identifier] === worker else { return }
            await worker.sessionStarted(at: startedAt, expectedInterval: interval)
        }
    }

    /// Stops delivering observations and lifecycle events to a consumer.
    /// Safe to call for consumers that were never added.
    func removeConsumer(_ consumer: any WiFiObservationConsuming) {
        let identifier = ObjectIdentifier(consumer)
        workers.removeValue(forKey: identifier)
    }

    func accept(_ observation: WiFiObservation) async {
        store.apply(observation)
        for worker in workers.values {
            await worker.consume(observation)
        }
    }

    func drainConsumers() async {
#if DEBUG
        onConsumerDrainStartedForTesting?()
#endif
        for worker in workers.values {
            await worker.drain()
        }
    }

    func diagnostics() -> [ObjectIdentifier: ObservationConsumerDiagnostics] {
        workers.mapValues(\.diagnostics)
    }

    func rawCycleDiagnostics() -> RawCycleDeliveryDiagnostics {
        RawCycleDeliveryDiagnostics(
            replacementCount: rawCycleReplacementCount,
            hasInFlight: rawCycleTask != nil,
            hasPending: pendingRawCycle != nil
        )
    }

    func scanCadenceDiagnostics() async -> WiFiScanCadenceDiagnostics {
        await scanSource.cadenceDiagnostics()
    }

    func startScanning(
        configuration: WiFiObservationRuntimeConfiguration,
        isPublicationEligible: @escaping @MainActor () -> Bool = { true },
        onOutput: @escaping @MainActor (WiFiObservationScanOutput) -> Void
    ) async {
        let replacesRequestedScan = requestedOutputProjection != nil
        requestedOutputProjection = onOutput
        requestedPublicationEligibility = isPublicationEligible
        let command = enqueueLifecycleCommand { [weak self] requestID in
            guard let self else { return }
            await self.executeStartCommand(
                configuration: configuration,
                onOutput: onOutput,
                isPublicationEligible: isPublicationEligible,
                requestID: requestID,
                stopSourceBeforeStart: replacesRequestedScan
            )
        }
        await command.value
    }

    func restartScanning(configuration: WiFiObservationRuntimeConfiguration) async {
        guard let requestedOutputProjection, let requestedPublicationEligibility else { return }
        let command = enqueueLifecycleCommand { [weak self] requestID in
            guard let self else { return }
            await self.executeStartCommand(
                configuration: configuration,
                onOutput: requestedOutputProjection,
                isPublicationEligible: requestedPublicationEligibility,
                requestID: requestID,
                stopSourceBeforeStart: true
            )
        }
        await command.value
    }

    public func stopScanning() async {
        let hadRequestedScan = requestedOutputProjection != nil
        requestedOutputProjection = nil
        requestedPublicationEligibility = nil
        let command = enqueueLifecycleCommand { [weak self] _ in
            guard let self else { return }
            await self.stopActiveScan(
                stopSource: hadRequestedScan,
                notifyScanStoppedForTesting: true
            )
            self.outputProjection = nil
            self.publicationEligibility = nil
        }
        await command.value
    }

    private func executeStartCommand(
        configuration: WiFiObservationRuntimeConfiguration,
        onOutput: @escaping @MainActor (WiFiObservationScanOutput) -> Void,
        isPublicationEligible: @escaping @MainActor () -> Bool,
        requestID: UInt64,
        stopSourceBeforeStart: Bool
    ) async {
        await stopActiveScan(stopSource: stopSourceBeforeStart)
        guard isLatestLifecycleRequest(requestID) else { return }

        let interfaceName = await scanSource.interfaceName()
        guard isLatestLifecycleRequest(requestID) else { return }
        let supportedBands = await scanSource.supportedBands()
        guard isLatestLifecycleRequest(requestID) else { return }
        let supportedChannels = await scanSource.supportedChannels()
        guard isLatestLifecycleRequest(requestID) else { return }
        let supportedChannelsRaw = await scanSource.supportedWLANChannelsRaw()
        guard isLatestLifecycleRequest(requestID) else { return }
        let deviceCapabilities = await scanSource.devicePHYCapabilities()
        guard isLatestLifecycleRequest(requestID) else { return }
        let cache = CapabilityCache(
            interfaceName: interfaceName,
            supportedBands: supportedBands,
            supportedChannelsRaw: supportedChannelsRaw,
            deviceSupportedChannels: Set(supportedChannels.map { "\($0.0.rawValue)-\($0.1)" }),
            deviceCapabilities: deviceCapabilities
        )
        let generation = UUID()
        activeScanGeneration = generation
        activeLifecycleGeneration = generation
        outputProjection = onOutput
        publicationEligibility = isPublicationEligible
        let startedAt = now()
        activeLifecycleStartedAt = startedAt
        activeScanInterval = configuration.scanInterval
        for worker in workers.values {
            await worker.sessionStarted(at: startedAt, expectedInterval: configuration.scanInterval)
        }
        await scanSource.startScanning(interval: configuration.scanInterval) { [weak self] event in
            await self?.admitRawCycle(RawCycleAdmission(
                event: event,
                configuration: configuration,
                cache: cache,
                generation: generation
            ))
        }
        guard isLatestLifecycleRequest(requestID) else {
            await scanSource.stopScanning()
            await drainConsumers()
            await finishLifecycleIfOwned(generation, at: now())
            return
        }
    }

    private func admitRawCycle(_ admission: RawCycleAdmission) {
        guard ownsScanLifecycle(admission.generation) else { return }
        guard rawCycleTask == nil else {
            if pendingRawCycle != nil {
                rawCycleReplacementCount &+= 1
            }
            pendingRawCycle = admission
            return
        }

        rawCycleTask = Task { @MainActor [weak self] in
            await self?.processAdmittedRawCycles(startingWith: admission)
        }
    }

    private func processAdmittedRawCycles(startingWith first: RawCycleAdmission) async {
        var current: RawCycleAdmission? = first
        while let admission = current, ownsScanLifecycle(admission.generation) {
            let shouldContinue = await processScanEvent(
                admission.event,
                configuration: admission.configuration,
                cache: admission.cache,
                generation: admission.generation
            )
            guard shouldContinue, ownsScanLifecycle(admission.generation) else { break }
            current = pendingRawCycle
            pendingRawCycle = nil
        }
        pendingRawCycle = nil
        rawCycleTask = nil
    }

    private func processScanEvent(
        _ event: WiFiScanEvent,
        configuration: WiFiObservationRuntimeConfiguration,
        cache: CapabilityCache,
        generation: UUID
    ) async -> Bool {
        let networks: [WiFiNetwork]
        let environmentError: WiFiObservationError?
        switch event {
        case .networks(let scannedNetworks):
            networks = scannedNetworks
            environmentError = nil
        case .failure(let message):
            networks = []
            environmentError = .environmentScanFailed(message)
        }

        let interfaceSnapshot = await interfaceSource.capture(cycleID: UUID())
        let cycle = await pipeline.produceCycle(
            networks: networks,
            context: WiFiObservationCycleContext(
                timestamp: interfaceSnapshot.capturedAt,
                interfaceSnapshot: interfaceSnapshot,
                interfaceName: cache.interfaceName,
                supportedBands: cache.supportedBands,
                supportedChannelsRaw: cache.supportedChannelsRaw,
                deviceSupportedChannels: cache.deviceSupportedChannels,
                deviceCapabilities: cache.deviceCapabilities,
                userRegionOverride: configuration.userRegionOverride,
                userDefaultsRegionOverride: configuration.userDefaultsRegionOverride,
                environmentError: environmentError
            )
        )
        guard activeScanGeneration == generation, !Task.isCancelled else { return false }
        guard publicationEligibility?() != false else {
            clearPublicationRequestAfterRejection()
            activeScanGeneration = nil
            await scanSource.stopScanning()
            await drainConsumers()
            await finishLifecycleIfOwned(generation, at: now())
            return false
        }
        store.apply(cycle.observation)
        outputProjection?(WiFiObservationScanOutput(
            rawNetworks: networks,
            cycle: cycle,
            interfaceSnapshot: interfaceSnapshot,
            interfaceName: cache.interfaceName,
            supportedBands: cache.supportedBands
        ))
        for worker in workers.values {
            await worker.consume(cycle.observation)
        }
        return true
    }

    private func clearPublicationRequestAfterRejection() {
        requestedOutputProjection = nil
        requestedPublicationEligibility = nil
        outputProjection = nil
        publicationEligibility = nil
    }

    private func stopActiveScan(
        stopSource: Bool,
        notifyScanStoppedForTesting: Bool = false
    ) async {
        let lifecycleGeneration = activeLifecycleGeneration
        let task = rawCycleTask
        rawCycleTask = nil
        pendingRawCycle = nil
        activeScanGeneration = nil
        publicationEligibility = nil
        task?.cancel()
        if stopSource || task != nil {
            await scanSource.stopScanning()
        }
        await task?.value
#if DEBUG
        if notifyScanStoppedForTesting {
            onActiveScanStoppedForTesting?()
        }
#endif
        await drainConsumers()
        if let lifecycleGeneration {
            await finishLifecycleIfOwned(lifecycleGeneration, at: now())
        }
    }

    private func finishLifecycleIfOwned(_ generation: UUID, at date: Date) async {
        guard activeLifecycleGeneration == generation else { return }
        activeLifecycleGeneration = nil
        activeLifecycleStartedAt = nil
        activeScanInterval = nil
        lifecycleReplayTail = nil
        for worker in workers.values { await worker.sessionStopped(at: date) }
    }

    private func ownsScanLifecycle(_ generation: UUID) -> Bool {
        activeScanGeneration == generation && !Task.isCancelled
    }

    private func enqueueLifecycleCommand(
        _ operation: @escaping @MainActor (UInt64) async -> Void
    ) -> Task<Void, Never> {
        latestLifecycleRequestID &+= 1
        let requestID = latestLifecycleRequestID
        let previousCommand = lifecycleCommandTail
        let command = Task { @MainActor [weak self] in
            await previousCommand?.value
            guard let self, self.isLatestLifecycleRequest(requestID) else { return }
            await operation(requestID)
        }
        lifecycleCommandTail = command
        return command
    }

    private func isLatestLifecycleRequest(_ requestID: UInt64) -> Bool {
        latestLifecycleRequestID == requestID
    }
}

@MainActor
private final class ObservationConsumerWorker {
    private let logger = Logger(subsystem: AppEnvironment.current.loggingSubsystem, category: "observation")
    let consumer: any WiFiObservationConsuming

    private var pendingTimestamps: [Date] = []
    private var failureCount = 0
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(consumer: any WiFiObservationConsuming) {
        self.consumer = consumer
    }

    var diagnostics: ObservationConsumerDiagnostics {
        ObservationConsumerDiagnostics(
            pendingCount: pendingTimestamps.count,
            oldestObservationTimestamp: pendingTimestamps.first,
            failureCount: failureCount
        )
    }

    func consume(_ observation: WiFiObservation) async {
        pendingTimestamps.append(observation.timestamp)
        do {
            try await consumer.consume(observation)
        } catch {
            failureCount += 1
            logger.error(
                "Observation consumer failed: \(String(describing: error))"
            )
        }
        if let index = pendingTimestamps.firstIndex(of: observation.timestamp) {
            pendingTimestamps.remove(at: index)
        }
        if pendingTimestamps.isEmpty {
            let waiters = drainWaiters
            drainWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func sessionStarted(at date: Date, expectedInterval: Duration) async {
        do {
            try await consumer.consumeLifecycle(.started(at: date, expectedInterval: expectedInterval))
        } catch {
            failureCount += 1
            logger.error("Observation consumer lifecycle start failed: \(String(describing: error))")
        }
    }

    func sessionStopped(at date: Date) async {
        do {
            try await consumer.consumeLifecycle(.stopped(at: date))
        } catch {
            failureCount += 1
            logger.error("Observation consumer lifecycle stop failed: \(String(describing: error))")
        }
    }

    func drain() async {
        guard !pendingTimestamps.isEmpty else { return }
        await withCheckedContinuation { drainWaiters.append($0) }
    }
}
