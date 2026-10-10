import Foundation
import CoreLocation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite("WiFiObservationRuntime")
@MainActor
struct RuntimeTests {
    @Test("scanner and runtime share the injected store")
    func scannerRuntimeUsesInjectedStore() {
        let store = WiFiObservationStore()
        let scanner = ScannerViewModel(store: store)
        #expect(scanner.observationRuntime.store === store)
    }

    @Test("runtime injection makes its store the scanner store")
    func injectedRuntimeOwnsScannerStore() {
        let runtime = WiFiObservationRuntime(store: WiFiObservationStore())
        let scanner = ScannerViewModel(observationRuntime: runtime)
        #expect(scanner.store === runtime.store)
    }

    @Test("accepted observations update the store and preserve consumer order")
    func orderedDelivery() async {
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(store: store)
        runtime.addConsumer(consumer)

        let first = WiFiObservation(timestamp: Date(timeIntervalSince1970: 1))
        let second = WiFiObservation(timestamp: Date(timeIntervalSince1970: 2))
        await runtime.accept(first)
        await runtime.accept(second)

        #expect(store.lastUpdated != nil)
        await runtime.drainConsumers()
        #expect(consumer.observations == [first, second])
    }

    @Test("runtime fan-out preserves one identity and suppresses exact replay")
    func fanOutPreservesSourceIdentity() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_300)
        let store = WiFiObservationStore()
        let firstConsumer = CapturingObservationConsumer()
        let secondConsumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(store: store)
        runtime.addConsumer(firstConsumer)
        runtime.addConsumer(secondConsumer)
        let first = WiFiObservation(timestamp: timestamp)
        let distinctSameTime = WiFiObservation(timestamp: timestamp)

        #expect(first.sourceObservationID != distinctSameTime.sourceObservationID)
        #expect(await runtime.accept(first))
        #expect(!(await runtime.accept(first)))
        #expect(await runtime.accept(distinctSameTime))
        await runtime.drainConsumers()

        #expect(firstConsumer.observations.map(\.sourceObservationID) == [
            first.sourceObservationID, distinctSameTime.sourceObservationID,
        ])
        #expect(secondConsumer.observations.map(\.sourceObservationID) == firstConsumer.observations.map(\.sourceObservationID))
        #expect(store.history.map(\.sourceObservationID) == firstConsumer.observations.map(\.sourceObservationID))
    }

    @Test("runtime rejects changed content that reuses an accepted source identity")
    func conflictingSourceIdentityIsRejected() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_310)
        let identity = UUID()
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(store: store)
        runtime.addConsumer(consumer)
        let original = WiFiObservation(
            sourceObservationID: identity,
            timestamp: timestamp,
            currentStatus: WiFiCurrentStatus(timestamp: timestamp, ssid: "Home", isConnected: false, isWiFiPowerOn: true)
        )
        let changed = WiFiObservation(
            sourceObservationID: identity,
            timestamp: timestamp,
            currentStatus: WiFiCurrentStatus(timestamp: timestamp, ssid: "Office", isConnected: false, isWiFiPowerOn: true)
        )

        #expect(await runtime.accept(original))
        #expect(!(await runtime.accept(changed)))
        await runtime.drainConsumers()

        #expect(store.history == [original])
        #expect(consumer.observations == [original])
        #expect(runtime.sourceIdentityConflictCount == 1)
    }

    @Test("a suspended consumer does not delay store publication")
    func storeIsImmediate() async {
        let store = WiFiObservationStore()
        let consumer = SuspendedObservationConsumer()
        let runtime = WiFiObservationRuntime(store: store)
        runtime.addConsumer(consumer)

        let status = WiFiCurrentStatus(
            timestamp: Date(), ssid: "Office", bssid: "AA:BB",
            isConnected: true, isWiFiPowerOn: true
        )
        let acceptance = Task { @MainActor in
            await runtime.accept(WiFiObservation(currentStatus: status))
        }

        await consumer.waitUntilEntered()
        #expect(store.currentStatus == status)
        consumer.resume()
        await acceptance.value
        await runtime.drainConsumers()
    }

    @Test("normal stop drains accepted consumer work after stopping the scan source")
    func stopDrainsAcceptedConsumerWork() async {
        let source = ScriptedScanSource()
        let consumer = SuspendedObservationConsumer()
        let activeScanStopped = MainActorMilestone()
        let consumerDrainStarted = MainActorMilestone()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            scanSource: source
        )
        runtime.onActiveScanStoppedForTesting = {
            activeScanStopped.reach()
        }
        runtime.onConsumerDrainStartedForTesting = {
            consumerDrainStarted.reach()
        }
        runtime.addConsumer(consumer)

        await runtime.startScanning(configuration: WiFiObservationRuntimeConfiguration(
            scanInterval: .seconds(4)
        )) { _ in }
        let observation = WiFiObservation(timestamp: Date(timeIntervalSince1970: 42))
        let acceptance = Task { @MainActor in await runtime.accept(observation) }
        await consumer.waitUntilEntered()

        let stopCompletion = AsyncCompletionProbe()
        let stopTask = Task { @MainActor in
            await runtime.stopScanning()
            await stopCompletion.markCompleted()
        }

        await source.waitUntilStopCompleted()
        await activeScanStopped.waitUntilReached()
        await consumerDrainStarted.waitUntilReached()

        #expect(await source.snapshot().activeStreamCount == 0)
        #expect(consumer.isSuspended)
        #expect(await stopCompletion.isCompleted == false)
        consumer.resume()
        await acceptance.value
        await stopTask.value

        #expect(await stopCompletion.isCompleted)
        #expect(consumer.observations == [observation])
    }

    @Test("a failing consumer does not stop later observations")
    func failureIsolation() async {
        let consumer = FailOnceObservationConsumer()
        let runtime = WiFiObservationRuntime(store: WiFiObservationStore())
        runtime.addConsumer(consumer)
        await runtime.accept(WiFiObservation(timestamp: Date(timeIntervalSince1970: 1)))
        await runtime.accept(WiFiObservation(timestamp: Date(timeIntervalSince1970: 2)))

        await runtime.drainConsumers()
        #expect(consumer.attemptedTimestamps == [
            Date(timeIntervalSince1970: 1), Date(timeIntervalSince1970: 2),
        ])
    }

    @Test("OSS composition needs no consumer")
    func noConsumerComposition() async {
        let store = WiFiObservationStore()
        let runtime = WiFiObservationRuntime(store: store)
        let status = WiFiCurrentStatus(timestamp: Date(), isConnected: false, isWiFiPowerOn: true)
        await runtime.accept(WiFiObservation(currentStatus: status))
        await runtime.drainConsumers()
        #expect(store.currentStatus == status)
    }

    @Test("scan generation delivers lifecycle start before work and stop exactly once")
    func observationLifecycleOrder() async {
        let source = ScriptedScanSource()
        let consumer = LifecycleRecordingConsumer()
        let dates = LockedDateSequence([10, 20, 30])
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            now: { dates.next() }
        )
        runtime.addConsumer(consumer)

        await runtime.startScanning(configuration: .init(scanInterval: .seconds(4))) { _ in }
        #expect(consumer.events == [.started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4))])
        await runtime.stopScanning()
        await runtime.stopScanning()

        #expect(consumer.events == [
            .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4)),
            .stopped(date: Date(timeIntervalSince1970: 20)),
        ])
    }

    @Test("restart closes the old generation before starting the new interval")
    func observationLifecycleRestartOrdering() async {
        let source = ScriptedScanSource()
        let consumer = LifecycleRecordingConsumer()
        let dates = LockedDateSequence([10, 20, 30, 40])
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            now: { dates.next() }
        )
        runtime.addConsumer(consumer)

        await runtime.startScanning(configuration: .init(scanInterval: .seconds(4))) { _ in }
        await runtime.restartScanning(configuration: .init(scanInterval: .seconds(9)))
        await runtime.stopScanning()

        #expect(consumer.events == [
            .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4)),
            .stopped(date: Date(timeIntervalSince1970: 20)),
            .started(date: Date(timeIntervalSince1970: 30), interval: .seconds(9)),
            .stopped(date: Date(timeIntervalSince1970: 40)),
        ])
    }

    @Test("publication rejection closes the active observation generation")
    func publicationRejectionStopsObservationLifecycle() async {
        let source = ScriptedScanSource()
        let consumer = LifecycleRecordingConsumer()
        let dates = LockedDateSequence([10, 20])
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource(),
            now: { dates.next() }
        )
        runtime.addConsumer(consumer)
        await runtime.startScanning(configuration: .testDefault, isPublicationEligible: { false }) { _ in }
        await source.yield(.networks([]))
        await runtime.drainRawCyclesForTesting()

        #expect(consumer.events == [
            .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(3)),
            .stopped(date: Date(timeIntervalSince1970: 20)),
        ])
        #expect(runtime.store.history.isEmpty)
        #expect(runtime.store.currentObservation == nil)
    }

    @Test("all consumers receive one shared lifecycle timestamp")
    func observationLifecycleTimestampIsShared() async {
        let source = ScriptedScanSource()
        let first = LifecycleRecordingConsumer()
        let second = LifecycleRecordingConsumer()
        let dates = LockedDateSequence([10, 11, 20])
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            now: { dates.next() }
        )
        runtime.addConsumer(first)
        runtime.addConsumer(second)
        await runtime.startScanning(configuration: .testDefault) { _ in }

        #expect(first.events.first == second.events.first)
        #expect(first.events.first == .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(3)))
        await runtime.stopScanning()
    }

    @Test("a consumer added after scanning starts receives the active lifecycle")
    func lateConsumerReceivesActiveLifecycle() async {
        let source = ScriptedScanSource()
        let early = LifecycleRecordingConsumer()
        let late = LifecycleRecordingConsumer()
        let dates = LockedDateSequence([10, 20])
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            now: { dates.next() }
        )
        runtime.addConsumer(early)
        await runtime.startScanning(configuration: .init(scanInterval: .seconds(4))) { _ in }
        #expect(early.events == [.started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4))])

        // AP Radar registers after the scan is already active; it must still
        // learn the current expected scan interval instead of guessing.
        runtime.addConsumer(late)
        await runtime.drainLifecycleReplaysForTesting()
        #expect(late.events == [.started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4))])

        await runtime.stopScanning()
        #expect(late.events == [
            .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(4)),
            .stopped(date: Date(timeIntervalSince1970: 20)),
        ])
    }

    @Test("synchronous scan emission cannot overtake lifecycle start")
    func synchronousEmissionFollowsLifecycleStart() async {
        let source = ScriptedScanSource()
        await source.setSynchronousStartEvent(.networks([]))
        let consumer = LifecycleRecordingConsumer()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(), scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource(),
            now: { Date(timeIntervalSince1970: 10) }
        )
        runtime.addConsumer(consumer)
        await runtime.startScanning(configuration: .testDefault) { _ in }
        await runtime.drainRawCyclesForTesting()

        #expect(consumer.events.prefix(2) == [
            .started(date: Date(timeIntervalSince1970: 10), interval: .seconds(3)),
            .observation,
        ])
        await runtime.stopScanning()
    }

    @Test("start superseded during capability lookup emits no lifecycle")
    func supersededCapabilityLookupHasNoLifecycle() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let consumer = LifecycleRecordingConsumer()
        let runtime = WiFiObservationRuntime(store: WiFiObservationStore(), scanSource: source)
        runtime.addConsumer(consumer)
        let start = Task { @MainActor in await runtime.startScanning(configuration: .testDefault) { _ in } }
        await source.waitUntilCapabilityLookupEntered()
        let stop = Task { @MainActor in await runtime.stopScanning() }
        await source.releaseCapabilityLookup()
        await start.value
        await stop.value

        #expect(consumer.events.isEmpty)
    }

    @Test("runtime exposes scan cadence energy diagnostics")
    func scanCadenceDiagnosticsAreQueryable() async {
        let source = ScriptedScanSource()
        await source.setCadenceSkippedSlotCount(3)
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            scanSource: source
        )

        let diagnostics = await runtime.scanCadenceDiagnostics()

        #expect(diagnostics.skippedSlotCount == 3)
    }

    @Test("start caches scanner capabilities once and publishes every network cycle")
    func scanStartCachesCapabilitiesAndPublishesCycles() async {
        let source = ScriptedScanSource()
        let pipeline = RecordingCyclePipeline()
        let store = WiFiObservationStore()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: pipeline,
            scanSource: source
        )
        var outputs: [WiFiObservationScanOutput] = []
        var publicationWasVisible: [Bool] = []
        let outputCounter = EventCounter()
        let configuration = WiFiObservationRuntimeConfiguration(
            scanInterval: .seconds(4),
            userRegionOverride: .JP,
            userDefaultsRegionOverride: .US
        )

        await runtime.startScanning(configuration: configuration) { output in
            outputs.append(output)
            publicationWasVisible.append(store.currentStatus == output.cycle.observation.currentStatus)
            outputCounter.increment()
        }
        let first = [runtimeNetwork(bssid: "AA:01", channel: 1)]
        let second = [runtimeNetwork(bssid: "AA:02", channel: 36)]
        await source.yield(.networks(first))
        await source.yield(.networks(second))
        await outputCounter.waitForCount(2)

        let snapshot = await source.snapshot()
        let calls = await pipeline.calls
        #expect(snapshot.requestedIntervals == [.seconds(4)])
        #expect(snapshot.interfaceNameCalls == 1)
        #expect(snapshot.supportedBandsCalls == 1)
        #expect(snapshot.supportedChannelsCalls == 1)
        #expect(snapshot.rawChannelsCalls == 1)
        #expect(snapshot.deviceCapabilitiesCalls == 1)
        #expect(calls.map(\.networks.count) == [1, 1])
        #expect(calls.allSatisfy { $0.context.interfaceName == "en7" })
        #expect(calls.allSatisfy { $0.context.supportedBands == [.band24GHz, .band5GHz] })
        #expect(calls.allSatisfy { $0.context.supportedChannelsRaw.count == 2 })
        #expect(calls.allSatisfy { $0.context.deviceSupportedChannels == ["1-1", "2-36"] })
        #expect(calls.allSatisfy { $0.context.userRegionOverride == .JP })
        #expect(calls.allSatisfy { $0.context.userDefaultsRegionOverride == .US })
        #expect(outputs.map(\.rawNetworks.count) == [1, 1])
        #expect(publicationWasVisible == [true, true])

        await runtime.stopScanning()
    }

    @Test("raw-cycle admission keeps one in-flight and only the latest pending cycle")
    func rawCycleAdmissionReplacesStalePendingCycle() async {
        let source = ScriptedScanSource()
        let pipeline = SuspendingFirstCyclePipeline()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let first = runtimeNetwork(bssid: "AA:A0", channel: 36)
        let stale = runtimeNetwork(bssid: "AA:B0", channel: 40)
        let latest = runtimeNetwork(bssid: "AA:C0", channel: 44)

        await runtime.startScanning(configuration: .testDefault) { _ in }
        await source.yield(.networks([first]))
        await pipeline.waitUntilFirstCycleEntered()
        await source.yield(.networks([stale]))
        await source.yield(.networks([latest]))

        let overloaded = runtime.rawCycleDiagnostics()
        #expect(overloaded.hasInFlight)
        #expect(overloaded.hasPending)
        #expect(overloaded.replacementCount == 1)

        await pipeline.releaseFirstCycle()
        await pipeline.waitUntilCompletedBSSIDCount(2)

        #expect(await pipeline.completedBSSIDs == [first.bssid, latest.bssid])
        #expect(runtime.rawCycleDiagnostics().replacementCount == 1)
        await runtime.stopScanning()
        #expect(runtime.rawCycleDiagnostics().hasInFlight == false)
        #expect(runtime.rawCycleDiagnostics().hasPending == false)
    }

    @Test("runtime stop cancels in-flight work and discards its pending raw cycle")
    func stopCancelsInFlightAndPendingRawCycles() async {
        let source = ScriptedScanSource()
        let pipeline = CancellationAwareFirstCyclePipeline()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source
        )
        let first = runtimeNetwork(bssid: "AA:D0", channel: 36)
        let pending = runtimeNetwork(bssid: "AA:E0", channel: 40)

        await runtime.startScanning(configuration: .testDefault) { _ in }
        await source.yield(.networks([first]))
        await pipeline.waitUntilFirstCycleEntered()
        await source.yield(.networks([pending]))
        #expect(runtime.rawCycleDiagnostics().hasPending)

        await runtime.stopScanning()

        #expect(await pipeline.wasCancelled)
        #expect(await pipeline.receivedBSSIDs == [first.bssid])
        #expect(runtime.rawCycleDiagnostics().hasInFlight == false)
        #expect(runtime.rawCycleDiagnostics().hasPending == false)
    }

    @Test("one interface snapshot supplies status and Interfaces projection per cycle")
    func oneInterfaceSnapshotSuppliesCycleProjections() async {
        let source = ScriptedScanSource()
        let capturedAt = Date(timeIntervalSince1970: 1_752_000_123)
        let interface = runtimeInterfaceInfo(ssid: "Same snapshot")
        let interfaceSource = CountingInterfaceSnapshotSource(
            interfaces: [interface],
            capturedAt: capturedAt
        )
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: WiFiObservationPipeline(
                gatewayLatencyProvider: MockGatewayLatencyProvider(
                    result: GatewayLatencyResult(timestamp: capturedAt)
                )
            ),
            scanSource: source,
            interfaceSource: interfaceSource
        )
        var output: WiFiObservationScanOutput?
        let outputCounter = EventCounter()

        await runtime.startScanning(configuration: .testDefault) {
            output = $0
            outputCounter.increment()
        }
        await source.yield(.networks([runtimeNetwork(bssid: "AA:02", channel: 36)]))
        await outputCounter.waitForCount(1)

        let snapshot = output?.interfaceSnapshot
        #expect(interfaceSource.captureCount == 1)
        #expect(snapshot?.interfaces.map(\.interfaceName) == [interface.interfaceName])
        #expect(output?.cycle.observation.currentStatus?.interfaceSnapshotCycleID == snapshot?.cycleID)
        #expect(output?.cycle.observation.currentStatus?.timestamp == snapshot?.capturedAt)

        await runtime.stopScanning()
    }

    @Test("scan failure produces a partial cycle that preserves current status")
    func scanFailureProducesPartialCycle() async {
        let source = ScriptedScanSource()
        let capturedAt = Date(timeIntervalSince1970: 1_752_000_789)
        let interfaceSource = CountingInterfaceSnapshotSource(
            interfaces: [runtimeInterfaceInfo(ssid: "Still connected")],
            capturedAt: capturedAt
        )
        let pipeline = WiFiObservationPipeline(
            gatewayLatencyProvider: MockGatewayLatencyProvider(
                result: GatewayLatencyResult(timestamp: capturedAt)
            )
        )
        let store = WiFiObservationStore()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: interfaceSource
        )
        var output: WiFiObservationScanOutput?
        let outputCounter = EventCounter()

        await runtime.startScanning(configuration: .testDefault) {
            output = $0
            outputCounter.increment()
        }
        await source.yield(.failure("permission changed"))
        await outputCounter.waitForCount(1)

        let expectedError = WiFiObservationError.environmentScanFailed("permission changed")
        let snapshot = output?.interfaceSnapshot
        let status = output?.cycle.observation.currentStatus
        #expect(interfaceSource.captureCount == 1)
        #expect(output?.rawNetworks.isEmpty == true)
        #expect(status?.ssid == "Still connected")
        #expect(status?.interfaceSnapshotCycleID == snapshot?.cycleID)
        #expect(status?.timestamp == snapshot?.capturedAt)
        #expect(output?.cycle.observation.environmentSnapshot?.error == expectedError)
        #expect(output?.cycle.observation.channelAnalysis == nil)
        #expect(output?.cycle.observation.channelRecommendation == nil)
        #expect(output?.cycle.observation.errors.contains(expectedError) == true)
        #expect(store.currentStatus == status)

        await runtime.stopScanning()
    }

    @Test("publication gate rejects a cycle before store consumers and output")
    func publicationGateRejectsCycleAtomically() async {
        let source = ScriptedScanSource()
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: RecordingCyclePipeline(),
            scanSource: source
        )
        runtime.addConsumer(consumer)
        var outputCount = 0

        await runtime.startScanning(
            configuration: .testDefault,
            isPublicationEligible: { false }
        ) { _ in
            outputCount += 1
        }
        await source.yield(.networks([runtimeNetwork(bssid: "AA:0F", channel: 36)]))
        await source.waitUntilStopCallCount(1)
        await runtime.drainConsumers()

        #expect(store.lastUpdated == nil)
        #expect(consumer.observations.isEmpty)
        #expect(outputCount == 0)
        #expect(await source.snapshot().activeStreamCount == 0)
    }

    @Test("publication rejection clears the restart request")
    func publicationRejectionRequiresFreshStart() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )

        await runtime.startScanning(
            configuration: .testDefault,
            isPublicationEligible: { false }
        ) { _ in }
        await source.yield(.networks([runtimeNetwork(bssid: "AA:10", channel: 36)]))
        await source.waitUntilStopCallCount(1)

        await runtime.restartScanning(configuration: .init(
            scanInterval: .seconds(9),
            userRegionOverride: nil,
            userDefaultsRegionOverride: nil
        ))

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals == [.seconds(3)])
        #expect(snapshot.activeStreamCount == 0)
    }

    @Test("stop cancels the active stream and stops its source")
    func stopCancelsActiveStream() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )

        await runtime.startScanning(configuration: .testDefault) { _ in }
        await runtime.stopScanning()
        await source.waitUntilActiveStreamCount(0)

        let snapshot = await source.snapshot()
        #expect(snapshot.stopCalls == 1)
        #expect(snapshot.activeStreamCount == 0)
    }

    @Test("restart replaces the stream and uses the new interval")
    func restartReplacesStream() async {
        let source = ScriptedScanSource()
        let pipeline = RecordingCyclePipeline()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source
        )
        var outputCount = 0
        let outputCounter = EventCounter()

        await runtime.startScanning(configuration: .testDefault) {
            _ in
            outputCount += 1
            outputCounter.increment()
        }
        await runtime.restartScanning(configuration: WiFiObservationRuntimeConfiguration(
            scanInterval: .seconds(9),
            userRegionOverride: nil,
            userDefaultsRegionOverride: nil
        ))
        await source.waitUntilActiveStreamCount(1)
        await source.yield(.networks([runtimeNetwork(bssid: "AA:09", channel: 9)]))
        await outputCounter.waitForCount(1)

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals == [.seconds(3), .seconds(9)])
        #expect(snapshot.stopCalls == 1)
        #expect(snapshot.activeStreamCount == 1)
        #expect(await pipeline.calls.count == 1)

        await runtime.stopScanning()
    }

    @Test("stop during capability lookup prevents stream creation")
    func stopDuringCapabilityLookupPreventsStreamCreation() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let pipeline = RecordingCyclePipeline()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source
        )
        var outputCount = 0

        let startTask = Task { @MainActor in
            await runtime.startScanning(configuration: .testDefault) { _ in outputCount += 1 }
        }
        await source.waitUntilCapabilityLookupEntered()
        let stopEntered = MainActorMilestone()
        let stopTask = Task { @MainActor in
            stopEntered.reach()
            await runtime.stopScanning()
        }
        await stopEntered.waitUntilReached()
        await source.releaseCapabilityLookup()
        await stopTask.value
        await startTask.value
        await source.yield(.networks([runtimeNetwork(bssid: "AA:10", channel: 10)]))
        await runtime.drainRawCyclesForTesting()

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals.isEmpty)
        #expect(snapshot.activeStreamCount == 0)
        #expect(await pipeline.calls.isEmpty)
        #expect(outputCount == 0)
    }

    @Test("restart replaces a startup suspended in capability lookup")
    func restartReplacesSuspendedStartup() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )

        let firstStart = Task { @MainActor in
            await runtime.startScanning(configuration: .testDefault) { _ in }
        }
        await source.waitUntilCapabilityLookupEntered()
        let restartEntered = MainActorMilestone()
        let restart = Task { @MainActor in
            restartEntered.reach()
            await runtime.restartScanning(configuration: WiFiObservationRuntimeConfiguration(
                scanInterval: .seconds(9),
                userRegionOverride: nil,
                userDefaultsRegionOverride: nil
            ))
        }
        await restartEntered.waitUntilReached()
        await source.releaseCapabilityLookup()
        await firstStart.value
        await restart.value
        await source.waitUntilActiveStreamCount(1)

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals == [.seconds(9)])
        #expect(snapshot.stopCalls == 1)
        #expect(snapshot.activeStreamCount == 1)

        await runtime.stopScanning()
    }

    @Test("stop remains latest behind a queued restart during suspended startup")
    func stopWinsThreeCommandStartupRace() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source
        )
        var completed: Set<String> = []
        let restartEntered = MainActorMilestone()
        let stopEntered = MainActorMilestone()
        let completedCounter = EventCounter()

        Task { @MainActor in
            await runtime.startScanning(configuration: .testDefault) { _ in }
            completed.insert("A")
            completedCounter.increment()
        }
        await source.waitUntilCapabilityLookupEntered()
        Task { @MainActor in
            restartEntered.reach()
            await runtime.restartScanning(configuration: .init(
                scanInterval: .seconds(9),
                userRegionOverride: nil,
                userDefaultsRegionOverride: nil
            ))
            completed.insert("B")
            completedCounter.increment()
        }
        await restartEntered.waitUntilReached()
        Task { @MainActor in
            stopEntered.reach()
            await runtime.stopScanning()
            completed.insert("C")
            completedCounter.increment()
        }
        await stopEntered.waitUntilReached()

        await source.releaseCapabilityLookup()
        await completedCounter.waitForCount(3)

        let snapshot = await source.snapshot()
        #expect(completed == ["A", "B", "C"])
        #expect(snapshot.requestedIntervals.isEmpty)
        #expect(snapshot.activeStreamCount == 0)
    }

    @Test("latest start wins behind a queued restart during suspended startup")
    func latestStartWinsThreeCommandStartupRace() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source
        )
        var completed: Set<String> = []
        let restartEntered = MainActorMilestone()
        let latestStartEntered = MainActorMilestone()
        let completedCounter = EventCounter()

        Task { @MainActor in
            await runtime.startScanning(configuration: .testDefault) { _ in }
            completed.insert("A")
            completedCounter.increment()
        }
        await source.waitUntilCapabilityLookupEntered()
        Task { @MainActor in
            restartEntered.reach()
            await runtime.restartScanning(configuration: .init(
                scanInterval: .seconds(9),
                userRegionOverride: nil,
                userDefaultsRegionOverride: nil
            ))
            completed.insert("B")
            completedCounter.increment()
        }
        await restartEntered.waitUntilReached()
        Task { @MainActor in
            latestStartEntered.reach()
            await runtime.startScanning(configuration: .init(
                scanInterval: .seconds(11),
                userRegionOverride: nil,
                userDefaultsRegionOverride: nil
            )) { _ in }
            completed.insert("C")
            completedCounter.increment()
        }
        await latestStartEntered.waitUntilReached()

        await source.releaseCapabilityLookup()
        await completedCounter.waitForCount(3)
        await source.waitUntilActiveStreamCount(1)

        let snapshot = await source.snapshot()
        #expect(completed == ["A", "B", "C"])
        #expect(snapshot.requestedIntervals == [.seconds(11)])
        #expect(snapshot.activeStreamCount == 1)

        await runtime.stopScanning()
    }

}

@Suite("Scanner runtime migration", .serialized)
@MainActor
struct ScannerRuntimeMigrationTests {
    @Test("changing the settings region while scanning restarts with the new override")
    func settingsRegionChangeRestartsRuntime() async {
        let suiteName = "ScannerRuntimeMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("auto", forKey: "regulatoryRegionOverride")

        let source = ScriptedScanSource()
        let pipeline = RecordingCyclePipeline()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            userDefaults: defaults,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized
        scanner.userRegionOverride = .US
        let network = runtimeNetwork(bssid: "AA:13", channel: 36)

        await scanner.debugStartScanLoopForTesting()
        scanner.handleRegulatoryRegionOverrideChange("JP")
        await scanner.debugDrainRuntimeLifecycleForTesting()
        await source.yield(.networks([network]))
        await runtime.drainRawCyclesForTesting()

        #expect(await source.snapshot().requestedIntervals == [.seconds(3), .seconds(3)])
        #expect(await pipeline.calls.last?.context.userRegionOverride == .US)
        #expect(await pipeline.calls.last?.context.userDefaultsRegionOverride == .JP)
        #expect(scanner.inferredRegion?.domain == .US)
        #expect(scanner.scanIntervalSeconds == 3)
        #expect(scanner.lastNetworks.map(\.id) == [network.id])

        scanner.handleRegulatoryRegionOverrideChange("auto")
        await scanner.debugDrainRuntimeLifecycleForTesting()
        await source.yield(.networks([network]))
        await runtime.drainRawCyclesForTesting()

        #expect(await pipeline.calls.last?.context.userDefaultsRegionOverride == nil)
        #expect(scanner.scanIntervalSeconds == 3)
        #expect(scanner.lastNetworks.map(\.id) == [network.id])
        scanner.stop()
    }

    @Test("changing the interval while scanning restarts the runtime")
    func intervalChangeRestartsRuntime() async throws {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })

        await scanner.debugStartScanLoopForTesting()
        scanner.scanIntervalSeconds = 1
        await source.waitUntilRequestedIntervalCount(2)

        #expect(await source.snapshot().requestedIntervals == [.seconds(3), .seconds(1)])
        scanner.stop()
    }

    @Test("two interval leases keep runtime restarts at one second")
    func twoIntervalLeasesKeepRuntimeRestartsAtOneSecond() async {
        let suiteName = "ScannerRuntimeMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "scanIntervalSeconds")
        defaults.set("auto", forKey: "regulatoryRegionOverride")

        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            userDefaults: defaults,
            authorizationRefresh: { _ in }
        )
        let firstLease = scanner.acquireScanIntervalLease(seconds: 1)
        let secondLease = scanner.acquireScanIntervalLease(seconds: 1)

        await scanner.debugStartScanLoopForTesting()
        scanner.scanIntervalSeconds = 7
        scanner.handleRegulatoryRegionOverrideChange("JP")
        await scanner.debugDrainRuntimeLifecycleForTesting()

        #expect(scanner.activeScanIntervalLeaseCount == 2)
        #expect(scanner.scanIntervalSeconds == 1)
        #expect(await source.snapshot().requestedIntervals == [.seconds(1), .seconds(1)])

        scanner.releaseScanIntervalLease(firstLease)
        #expect(scanner.scanIntervalSeconds == 1)
        scanner.releaseScanIntervalLease(secondLease)
        #expect(scanner.scanIntervalSeconds == 7)
        scanner.stop()
    }

    @Test("an interval requested during recording becomes effective after the final lease")
    func intervalRequestedDuringRecordingWinsAfterFinalLease() {
        let suiteName = "ScannerRuntimeMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "scanIntervalSeconds")

        let scanner = ScannerViewModel(
            userDefaults: defaults,
            authorizationRefresh: { _ in }
        )
        let lease = scanner.acquireScanIntervalLease(seconds: 1)

        scanner.scanIntervalSeconds = 10
        #expect(scanner.scanIntervalSeconds == 1)

        scanner.releaseScanIntervalLease(lease)
        #expect(scanner.scanIntervalSeconds == 10)
    }

    @Test("two interval leases survive scanner stop and start")
    func twoIntervalLeasesSurviveScannerStopAndStart() async {
        let suiteName = "ScannerRuntimeMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "scanIntervalSeconds")

        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            userDefaults: defaults,
            authorizationRefresh: { _ in }
        )
        let firstLease = scanner.acquireScanIntervalLease(seconds: 1)
        let secondLease = scanner.acquireScanIntervalLease(seconds: 1)

        await scanner.debugStartScanLoopForTesting()
        scanner.stop()
        await scanner.debugStartScanLoopForTesting()
        await scanner.debugDrainRuntimeLifecycleForTesting()

        #expect(scanner.activeScanIntervalLeaseCount == 2)
        #expect(scanner.scanIntervalSeconds == 1)
        #expect(await source.snapshot().requestedIntervals == [.seconds(1), .seconds(1)])

        scanner.releaseScanIntervalLease(firstLease)
        scanner.releaseScanIntervalLease(secondLease)
        #expect(scanner.scanIntervalSeconds == 7)
        scanner.stop()
    }

    @Test("Wi-Fi power off stops runtime scanning")
    func powerOffStopsRuntime() async throws {
        let source = ScriptedScanSource()
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        runtime.addConsumer(consumer)
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })

        await scanner.debugStartScanLoopForTesting()
        scanner.debugReconcileWiFiStateForTesting(.poweredOff)
        await source.waitUntilStopCallCount(1)
        await source.yield(.networks([runtimeNetwork(bssid: "AA:0D", channel: 36)]))
        await runtime.drainConsumers()

        #expect(scanner.isScanning == false)
        #expect(await source.snapshot().activeStreamCount == 0)
        #expect(store.lastUpdated == nil)
        #expect(consumer.observations.isEmpty)
    }

    @Test("Unknown Wi-Fi state does not stop an active scan")
    func unknownWiFiStatePreservesRuntimeScan() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })

        await scanner.debugStartScanLoopForTesting()
        scanner.debugReconcileWiFiStateForTesting(.unknown)

        #expect(scanner.isScanning)
        #expect(scanner.isWiFiAvailable)
        scanner.stop()
        await source.waitUntilStopCallCount(1)
    }

    @Test("Persistent unknown evidence pauses scans and trusted radio evidence resumes one loop")
    func persistentUnknownUsesBoundedProbeAndRecovers() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartScanLoopForTesting()
        let firstSampleID = UUID()
        scanner.debugReconcileWiFiStateForTesting(.unknown, sampleID: firstSampleID)
        #expect(scanner.isScanning)
        scanner.debugReconcileWiFiStateForTesting(.unknown, sampleID: firstSampleID)
        #expect(scanner.debugConsecutiveUnknownSamplesForTesting == 1)
        scanner.debugReconcileWiFiStateForTesting(.unknown, sampleID: UUID())
        #expect(scanner.isScanning)
        scanner.debugReconcileWiFiStateForTesting(.unknown, sampleID: UUID())
        await source.waitUntilStopCallCount(1)
        #expect(!scanner.isScanning)
        if case .scanFailed(let message) = scanner.accessState {
            #expect(message.contains("unknown"))
        } else {
            #expect(Bool(false), "Persistent unknown evidence should be shown as temporarily unavailable")
        }

        scanner.debugReconcileWiFiStateForTesting(.poweredOn)
        await Task.yield()
        await scanner.debugDrainRuntimeLifecycleForTesting()
        #expect(scanner.isScanning)
        #expect(await source.snapshot().activeStreamCount == 1)
        #expect(await source.snapshot().requestedIntervals.count == 2)

        await scanner.stopForTermination()
        #expect(await source.snapshot().activeStreamCount == 0)
    }

    @Test("bounded recovery probe survives repeated scan failures and resumes one loop")
    func boundedProbeRecoversAfterRepeatedEnvironmentFailures() async {
        let source = ScriptedScanSource()
        let store = WiFiObservationStore()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: ErrorAwareProjectionCyclePipeline(
                channelQualities: [],
                recommendations: [],
                inferredRegion: RegionInferenceResult(domain: .US, confidence: .low, contributions: [], conflicts: [])
            ),
            scanSource: source,
            interfaceSource: IncrementingInterfaceSnapshotSource()
        )
        let recoveryClock = ControlledWiFiProbeClock()
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized },
            unknownWiFiProbeSleep: { duration in try await recoveryClock.sleep(for: duration) }
        )
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartScanLoopForTesting()
        for _ in 0..<3 { scanner.debugReconcileWiFiStateForTesting(.unknown) }
        await source.waitUntilStopCallCount(1)
        await recoveryClock.waitUntilScheduled()
        #expect(await recoveryClock.scheduledDurations == [.seconds(30)])
        #expect(!scanner.isScanning)

        await recoveryClock.advanceOneProbe()
        await source.waitUntilActiveStreamCount(1)
        await scanner.debugDrainRuntimeLifecycleForTesting()
        #expect(scanner.isScanning)
        #expect(await source.snapshot().activeStreamCount == 1)

        await source.yield(.interfaceUnavailable("radio interface unavailable"))
        await runtime.drainRawCyclesForTesting()
        #expect(store.latestEnvironmentSnapshot?.error == .environmentScanFailed("radio interface unavailable"))
        #expect(scanner.isScanning)

        await source.yield(.interfaceUnavailable("still unavailable"))
        await runtime.drainRawCyclesForTesting()
        #expect(store.latestEnvironmentSnapshot?.error == .environmentScanFailed("still unavailable"))
        #expect(await source.snapshot().activeStreamCount == 1)

        let recovered = runtimeNetwork(bssid: "AA:RECOVERED", channel: 44)
        await source.yield(.networks([recovered]))
        await runtime.drainRawCyclesForTesting()
        #expect(store.latestEnvironmentSnapshot?.error == nil)
        #expect(scanner.lastNetworks.map(\.id) == [recovered.id])
        #expect(scanner.isScanning)
        #expect(await source.snapshot().activeStreamCount == 1)

        await scanner.stopForTermination()
        #expect(await source.snapshot().activeStreamCount == 0)
    }

    @Test("Initial unknown evidence permits one authorized controlled scan probe")
    func initialUnknownStartsControlledProbe() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartAfterAuthorizationForTesting()
        await scanner.debugDrainRuntimeLifecycleForTesting()

        #expect(scanner.wifiPowerState == .unknown)
        #expect(scanner.isScanning)
        #expect(await source.snapshot().requestedIntervals == [.seconds(3)])
        #expect(await source.snapshot().activeStreamCount == 1)
        scanner.stop()
        await source.waitUntilStopCallCount(1)
    }

    @Test("An unavailable interface is a failed sample, not a successful empty scan")
    func unavailableInterfacePropagatesAsFailure() async {
        let source = ScriptedScanSource()
        let interfaceSource = CountingInterfaceSnapshotSource(
            interfaces: [],
            capturedAt: Date(timeIntervalSince1970: 1_752_000_790)
        )
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: WiFiObservationPipeline(),
            scanSource: source,
            interfaceSource: interfaceSource
        )
        var output: WiFiObservationScanOutput?
        let outputCounter = EventCounter()
        await runtime.startScanning(configuration: .testDefault) {
            output = $0
            outputCounter.increment()
        }

        await source.yield(.interfaceUnavailable("Wi-Fi interface unavailable"))
        await outputCounter.waitForCount(1)

        #expect(output?.rawNetworks.isEmpty == true)
        #expect(output?.cycle.observation.environmentSnapshot?.error
            == .environmentScanFailed("Wi-Fi interface unavailable"))
        #expect(interfaceSource.captureCount == 1)
        await runtime.stopScanning()
    }

    @Test("authorization loss on a runtime output stops scanning")
    func authorizationLossStopsRuntime() async {
        let source = ScriptedScanSource()
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        runtime.addConsumer(consumer)
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartScanLoopForTesting()
        scanner.locationManager.authorizationStatus = .denied
        await source.yield(.networks([runtimeNetwork(bssid: "AA:03", channel: 36)]))
        await runtime.drainRawCyclesForTesting()

        #expect(scanner.isScanning == false)
        #expect(scanner.accessState == .denied)
        #expect(store.lastUpdated == nil)
        #expect(consumer.observations.isEmpty)
    }

    @Test("runtime output projects networks, analysis, region, and interface context")
    func outputProjection() async {
        let source = ScriptedScanSource()
        let quality = runtimeQuality(channel: 36)
        var recommendation = ChannelRecommendation(from: quality)
        recommendation.scoreSelected = true
        let pipeline = ProjectionCyclePipeline(
            channelQualities: [quality],
            recommendations: [recommendation],
            inferredRegion: RegionInferenceResult(
                domain: .JP,
                confidence: .high,
                contributions: [],
                conflicts: []
            )
        )
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized
        let network = runtimeNetwork(bssid: "AA:04", channel: 36)

        await scanner.debugStartScanLoopForTesting()
        await source.yield(.networks([network]))
        await runtime.drainRawCyclesForTesting()

        #expect(scanner.signalHistory.allHistory[network.bssid] == [-50])
        #expect(scanner.channelQualities.map(\.qualityScore) == [quality.qualityScore])
        #expect(scanner.channelRecommendations.map(\.channel) == [recommendation.channel])
        #expect(scanner.inferredRegion?.domain == .JP)
        #expect(scanner.interfaceName == "en7")
        #expect(scanner.supportedBands == Set([ChannelBand.band24GHz, ChannelBand.band5GHz]))
        #expect(scanner.band5.allSeriesData.map { $0.id } == [network.id])
        scanner.stop()
    }

    @Test("runtime interface snapshot supplies ScannerViewModel Interfaces projection")
    func interfaceSnapshotProjectsIntoScannerViewModel() async {
        let source = ScriptedScanSource()
        let capturedAt = Date(timeIntervalSince1970: 1_752_001_000)
        let interfaces = [
            runtimeInterfaceInfo(ssid: "Snapshot Wi-Fi"),
            runtimeInterfaceInfo(interfaceName: "bridge0", ssid: nil),
        ]
        let interfaceSource = CountingInterfaceSnapshotSource(
            interfaces: interfaces,
            capturedAt: capturedAt
        )
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: WiFiObservationPipeline(
                gatewayLatencyProvider: MockGatewayLatencyProvider(
                    result: GatewayLatencyResult(timestamp: capturedAt)
                )
            ),
            scanSource: source,
            interfaceSource: interfaceSource
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartScanLoopForTesting()
        await source.yield(.networks([runtimeNetwork(bssid: "AA:14", channel: 36)]))
        await runtime.drainRawCyclesForTesting()

        #expect(interfaceSource.captureCount == 1)
        #expect(scanner.networkInfo.map(\.interfaceName) == interfaces.map(\.interfaceName))
        #expect(scanner.networkInfo.map(\.ssid) == interfaces.map(\.ssid))
        #expect(scanner.networkInfo.map(\.ipv4Addresses) == interfaces.map(\.ipv4Addresses))
        scanner.stop()
    }

    @Test("runtime outputs preserve filters and locked AP visibility")
    func outputPreservesPresentationState() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized
        let office = runtimeNetwork(ssid: "Office", bssid: "AA:05", channel: 36)
        let guest = runtimeNetwork(ssid: "Guest", bssid: "AA:06", channel: 40)

        await scanner.debugStartScanLoopForTesting()
        await source.yield(.networks([office, guest]))
        await runtime.drainRawCyclesForTesting()
        scanner.toggleVisibility(seriesID: office.id)
        scanner.toggleVisibilityLocked(seriesID: office.id)
        scanner.setFilterQuery("Guest", for: .primary)

        await source.yield(.networks([office, guest]))
        await runtime.drainRawCyclesForTesting()

        #expect(scanner.filterQuery(for: .primary) == "Guest")
        #expect(scanner.combinedTableRows.first(where: { $0.id == office.id })?.isVisible == false)
        #expect(scanner.combinedTableRows.first(where: { $0.id == office.id })?.visibilityLocked == true)
        #expect(scanner.bandViewModel(for: .primary, band: .band5GHz).visibleSeriesData().map { $0.id } == [guest.id])
        scanner.stop()
    }

    @Test("failed scan invalidates current environment projections but preserves history")
    func failedScanInvalidatesCurrentProjection() async {
        let source = ScriptedScanSource()
        let firstCapturedAt = Date(timeIntervalSince1970: 1_752_001_200)
        let secondCapturedAt = Date(timeIntervalSince1970: 1_752_001_205)
        let firstInterfaces = [runtimeInterfaceInfo(ssid: "Presentation")]
        let secondInterfaces = [
            runtimeInterfaceInfo(interfaceName: "en9", ssid: "Failure cycle"),
            runtimeInterfaceInfo(interfaceName: "bridge9", ssid: nil),
        ]
        let interfaceSource = SequentialInterfaceSnapshotSource(
            captures: [
                (capturedAt: firstCapturedAt, interfaces: firstInterfaces),
                (capturedAt: secondCapturedAt, interfaces: secondInterfaces),
            ]
        )
        let pipeline = WiFiObservationPipeline(
            gatewayLatencyProvider: MockGatewayLatencyProvider(
                result: GatewayLatencyResult(timestamp: firstCapturedAt)
            )
        )
        let store = WiFiObservationStore()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: interfaceSource
        )
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized
        let network = runtimeNetwork(bssid: "AA:0E", channel: 36)

        await scanner.debugStartScanLoopForTesting()
        await source.yield(.networks([network]))
        await runtime.drainRawCyclesForTesting()
        let expectedError = WiFiObservationError.environmentScanFailed("temporary scan failure")
        await source.yield(.failure("temporary scan failure"))
        await runtime.drainRawCyclesForTesting()

        #expect(interfaceSource.captureCount == 2)
        #expect(scanner.lastNetworks.isEmpty)
        #expect(scanner.channelQualities.isEmpty)
        #expect(scanner.channelRecommendations.isEmpty)
        #expect(scanner.inferredRegion == nil)
        #expect(store.latestEnvironmentSnapshot?.error == expectedError)
        #expect(store.channelAnalysis == nil)
        #expect(store.channelRecommendation == nil)
        #expect(store.quality == nil)
        #expect(store.diagnosis == nil)
        #expect(store.history.count == 2)
        #expect(scanner.networkInfo.map(\.interfaceName) == secondInterfaces.map(\.interfaceName))
        #expect(scanner.networkInfo.map(\.ssid) == secondInterfaces.map(\.ssid))
        let failedCycleSnapshot = interfaceSource.capturedSnapshots[1]
        #expect(store.currentStatus?.interfaceSnapshotCycleID == failedCycleSnapshot.cycleID)
        #expect(store.currentStatus?.timestamp == failedCycleSnapshot.capturedAt)
        scanner.stop()
    }

    @Test("scanner lifecycle forwarding is drained in call order")
    func lifecycleForwardingIsOrdered() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })

        await scanner.debugStartScanLoopForTesting()
        scanner.scanIntervalSeconds = 5
        scanner.scanIntervalSeconds = 7
        scanner.stop()
        await scanner.debugStartScanLoopForTesting()
        await scanner.debugDrainRuntimeLifecycleForTesting()

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals.last == .seconds(7))
        #expect(snapshot.activeStreamCount == 1)
        #expect(scanner.isScanning)
        scanner.stop()
    }

    @Test("termination gate rejects powered-on reconcile, restart, and later start")
    func terminationGatePreventsRuntimeRevival() async {
        let source = ScriptedScanSource()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })
        scanner.locationManager.authorizationStatus = .authorized

        await scanner.debugStartScanLoopForTesting()
        await scanner.stopForTermination()
        let stopped = await source.snapshot()

        scanner.debugReconcileWiFiStateForTesting(.poweredOn)
        scanner.scanIntervalSeconds = 1
        await scanner.debugStartScanLoopForTesting()
        await scanner.debugDrainRuntimeLifecycleForTesting()
        await scanner.stopForTermination()

        let final = await source.snapshot()
        #expect(stopped.requestedIntervals == [.seconds(3)])
        #expect(final.requestedIntervals == stopped.requestedIntervals)
        #expect(final.stopCalls == stopped.stopCalls)
        #expect(final.activeStreamCount == 0)
        #expect(scanner.isScanning == false)
    }

    @Test("termination supersedes a runtime start suspended in capability lookup")
    func terminationSupersedesSuspendedRuntimeStart() async {
        let source = ScriptedScanSource()
        await source.suspendNextCapabilityLookup()
        let runtime = WiFiObservationRuntime(
            store: WiFiObservationStore(),
            pipeline: RecordingCyclePipeline(),
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        let scanner = ScannerViewModel(observationRuntime: runtime, authorizationRefresh: { _ in })

        let start = Task { @MainActor in
            await scanner.debugStartScanLoopForTesting()
        }
        await source.waitUntilCapabilityLookupEntered()
        let terminationEntered = MainActorMilestone()
        let termination = Task { @MainActor in
            terminationEntered.reach()
            await scanner.stopForTermination()
        }
        await terminationEntered.waitUntilReached()
        await source.releaseCapabilityLookup()
        await start.value
        await termination.value

        let snapshot = await source.snapshot()
        #expect(snapshot.requestedIntervals.isEmpty)
        #expect(snapshot.activeStreamCount == 0)
        #expect(scanner.isScanning == false)
    }

    @Test("termination stops Wi-Fi power monitoring and its event task")
    func terminationStopsWiFiMonitoring() async {
        let scanner = ScannerViewModel(
            observationRuntime: WiFiObservationRuntime(
                store: WiFiObservationStore(),
                pipeline: RecordingCyclePipeline(),
                scanSource: ScriptedScanSource(),
                interfaceSource: ImmediateInterfaceSnapshotSource()
            ),
            authorizationRefresh: { _ in }
        )

        scanner.debugStartWiFiMonitoringForTesting()
        #expect(scanner.debugHasActiveWiFiMonitoringForTesting)

        await scanner.stopForTermination()

        #expect(scanner.debugHasActiveWiFiMonitoringForTesting == false)
    }

    @Test("a suspended old cycle cannot publish across scanner stop and start")
    func suspendedOldCycleIsRejectedAcrossStopStart() async throws {
        let source = ScriptedScanSource()
        let pipeline = SuspendingFirstCyclePipeline()
        let store = WiFiObservationStore()
        let consumer = CapturingObservationConsumer()
        let runtime = WiFiObservationRuntime(
            store: store,
            pipeline: pipeline,
            scanSource: source,
            interfaceSource: ImmediateInterfaceSnapshotSource()
        )
        runtime.addConsumer(consumer)
        let scanner = ScannerViewModel(
            observationRuntime: runtime,
            authorizationRefresh: { $0.authorizationStatus = .authorized }
        )
        scanner.locationManager.authorizationStatus = .authorized
        let oldNetwork = runtimeNetwork(bssid: "AA:11", channel: 36)
        let newNetwork = runtimeNetwork(bssid: "AA:12", channel: 40)

        await scanner.debugStartScanLoopForTesting()
        await source.yield(.networks([oldNetwork]))
        await pipeline.waitUntilFirstCycleEntered()

        scanner.stop()
        let freshStart = Task { @MainActor in
            await scanner.debugStartScanLoopForTesting()
        }
        await source.waitUntilStopCallCount(1)
        await pipeline.releaseFirstCycle()
        await freshStart.value
        await source.yield(.networks([newNetwork]))
        await runtime.drainRawCyclesForTesting()
        await runtime.drainConsumers()

        #expect(store.currentStatus?.bssid == newNetwork.bssid)
        #expect(consumer.observations.map { $0.currentStatus?.bssid } == [newNetwork.bssid])
        #expect(scanner.lastNetworks.map(\.id) == [newNetwork.id])
        #expect(scanner.signalHistory.allHistory[oldNetwork.bssid] == nil)
        #expect(scanner.signalHistory.allHistory[newNetwork.bssid] == [-50])
        #expect(await pipeline.completedBSSIDs == [oldNetwork.bssid, newNetwork.bssid])
        scanner.stop()
    }

}

@Suite("Wi-Fi scan cadence")
struct WiFiScanCadenceTests {
    @Test("normal scans retain wall-clock cadence")
    func normalCadence() async throws {
        let clock = ManualWiFiScanClock()
        var cadence = WiFiScanCadence(interval: .seconds(5), startedAt: .zero)

        await clock.advance(by: .seconds(1))
        let firstSkipped = try await cadence.waitForNextScan(using: clock)
        await clock.advance(by: .seconds(1))
        let secondSkipped = try await cadence.waitForNextScan(using: clock)

        #expect(firstSkipped == 0)
        #expect(secondSkipped == 0)
        #expect(await clock.recordedSleeps == [.seconds(4), .seconds(4)])
        #expect(await clock.now() == .seconds(10))
    }

    @Test("long scans skip missed slots and wait for the next future slot")
    func skipsMissedSlotsWithoutCatchUpBurst() async throws {
        let clock = ManualWiFiScanClock()
        var cadence = WiFiScanCadence(interval: .seconds(5), startedAt: .zero)

        await clock.advance(by: .seconds(12))
        let skippedAfterDelay = try await cadence.waitForNextScan(using: clock)
        await clock.advance(by: .seconds(1))
        let skippedAfterRecovery = try await cadence.waitForNextScan(using: clock)

        #expect(skippedAfterDelay == 2)
        #expect(skippedAfterRecovery == 0)
        #expect(await clock.recordedSleeps == [.seconds(3), .seconds(4)])
        #expect(await clock.now() == .seconds(20))
    }

    @Test("cancelling a pending cadence wait completes without another scan")
    func cancellationStopsPendingWait() async {
        let clock = ManualWiFiScanClock(suspendsSleeps: true)
        let task = Task {
            var cadence = WiFiScanCadence(interval: .seconds(5), startedAt: .zero)
            return try await cadence.waitForNextScan(using: clock)
        }

        await clock.waitUntilSleepEntered()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected the pending cadence wait to be cancelled")
        } catch is CancellationError {
            // Expected cancellation path.
        } catch {
            Issue.record("Unexpected cadence cancellation error: \(error)")
        }
        #expect(await clock.recordedSleeps == [.seconds(5)])
    }
}

private extension WiFiObservationRuntimeConfiguration {
    static let testDefault = WiFiObservationRuntimeConfiguration(
        scanInterval: .seconds(3),
        userRegionOverride: nil,
        userDefaultsRegionOverride: nil
    )
}

private func runtimeNetwork(
    ssid: String = "Runtime test",
    bssid: String,
    channel: Int
) -> WiFiNetwork {
    WiFiNetwork(
        ssid: ssid,
        bssid: bssid,
        rssi: -50,
        channel: WiFiChannel(
            band: channel <= 14 ? .band24GHz : .band5GHz,
            channelNumber: channel
        )
    )
}

private func runtimeQuality(channel: Int) -> ChannelQuality {
    ChannelQuality(
        channel: channel,
        band: "5",
        bandDisplay: "5 GHz",
        qualityScore: 88,
        qualityLevel: .excellent,
        apCount: 1,
        coChannelCount: 0,
        adjacentCount: 0,
        interferenceScore: 12,
        overlapLevel: .low,
        strongestNeighborRSSI: -90,
        isCurrentChannel: true
    )
}

private actor ScriptedScanSource: WiFiScanStreaming {
    struct Snapshot: Sendable {
        let requestedIntervals: [Duration]
        let stopCalls: Int
        let activeStreamCount: Int
        let interfaceNameCalls: Int
        let supportedBandsCalls: Int
        let supportedChannelsCalls: Int
        let rawChannelsCalls: Int
        let deviceCapabilitiesCalls: Int
    }

    private var requestedIntervals: [Duration] = []
    private var stopCalls = 0
    private var handlers: [UUID: @Sendable (WiFiScanEvent) async -> Void] = [:]
    private var interfaceNameCalls = 0
    private var supportedBandsCalls = 0
    private var supportedChannelsCalls = 0
    private var rawChannelsCalls = 0
    private var deviceCapabilitiesCalls = 0
    private var shouldSuspendCapabilityLookup = false
    private var capabilityLookupEntered = false
    private var capabilityLookupEnteredContinuation: CheckedContinuation<Void, Never>?
    private var capabilityLookupReleaseContinuation: CheckedContinuation<Void, Never>?
    private var hasCompletedStop = false
    private var stopCompletedContinuation: CheckedContinuation<Void, Never>?
    private var cadenceSkippedSlotCount: UInt64 = 0
    private var synchronousStartEvent: WiFiScanEvent?
    private var requestedIntervalsWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var stopCallWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var activeStreamWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func startScanning(
        interval: Duration,
        onEvent: @escaping @Sendable (WiFiScanEvent) async -> Void
    ) async {
        requestedIntervals.append(interval)
        resumeWaiters(targeting: &requestedIntervalsWaiters, count: requestedIntervals.count)
        handlers[UUID()] = onEvent
        resumeWaiters(targeting: &activeStreamWaiters, count: handlers.count)
        if let synchronousStartEvent {
            await onEvent(synchronousStartEvent)
        }
    }

    func stopScanning() async {
        stopCalls += 1
        resumeWaiters(targeting: &stopCallWaiters, count: stopCalls)
        handlers.removeAll()
        resumeWaiters(targeting: &activeStreamWaiters, count: handlers.count)
        hasCompletedStop = true
        stopCompletedContinuation?.resume()
        stopCompletedContinuation = nil
    }

    func waitUntilRequestedIntervalCount(_ target: Int) async {
        if requestedIntervals.count >= target { return }
        await withCheckedContinuation { requestedIntervalsWaiters.append((target, $0)) }
    }

    func waitUntilStopCallCount(_ target: Int) async {
        if stopCalls >= target { return }
        await withCheckedContinuation { stopCallWaiters.append((target, $0)) }
    }

    func waitUntilActiveStreamCount(_ target: Int) async {
        if handlers.count == target { return }
        await withCheckedContinuation { activeStreamWaiters.append((target, $0)) }
    }

    private func resumeWaiters(
        targeting waiters: inout [(Int, CheckedContinuation<Void, Never>)],
        count: Int
    ) {
        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        waiters = waiters.filter { waiter in
            if count == waiter.0 {
                pending.append(waiter)
                return false
            }
            return true
        }
        pending.forEach { $0.1.resume() }
    }

    func waitUntilStopCompleted() async {
        guard !hasCompletedStop else { return }
        await withCheckedContinuation { continuation in
            stopCompletedContinuation = continuation
        }
    }

    func interfaceName() async -> String? {
        interfaceNameCalls += 1
        if shouldSuspendCapabilityLookup {
            shouldSuspendCapabilityLookup = false
            capabilityLookupEntered = true
            capabilityLookupEnteredContinuation?.resume()
            capabilityLookupEnteredContinuation = nil
            await withCheckedContinuation { continuation in
                capabilityLookupReleaseContinuation = continuation
            }
        }
        return "en7"
    }

    func supportedBands() async -> Set<ChannelBand> {
        supportedBandsCalls += 1
        return [.band24GHz, .band5GHz]
    }

    func supportedChannels() async -> [(ChannelBand, Int)] {
        supportedChannelsCalls += 1
        return [(.band24GHz, 1), (.band5GHz, 36)]
    }

    func supportedWLANChannelsRaw() async -> [(Int, Int)] {
        rawChannelsCalls += 1
        return [(1, 1), (2, 36)]
    }

    func devicePHYCapabilities() async -> DevicePHYCapabilities {
        deviceCapabilitiesCalls += 1
        return .default
    }

    func cadenceDiagnostics() -> WiFiScanCadenceDiagnostics {
        WiFiScanCadenceDiagnostics(skippedSlotCount: cadenceSkippedSlotCount)
    }

    func setCadenceSkippedSlotCount(_ count: UInt64) {
        cadenceSkippedSlotCount = count
    }

    func setSynchronousStartEvent(_ event: WiFiScanEvent) {
        synchronousStartEvent = event
    }

    func yield(_ event: WiFiScanEvent) async {
        let active = handlers.values
        for handler in active {
            await handler(event)
        }
    }

    func suspendNextCapabilityLookup() {
        shouldSuspendCapabilityLookup = true
        capabilityLookupEntered = false
    }

    func waitUntilCapabilityLookupEntered() async {
        guard !capabilityLookupEntered else { return }
        await withCheckedContinuation { continuation in
            capabilityLookupEnteredContinuation = continuation
        }
    }

    func releaseCapabilityLookup() {
        capabilityLookupReleaseContinuation?.resume()
        capabilityLookupReleaseContinuation = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            requestedIntervals: requestedIntervals,
            stopCalls: stopCalls,
            activeStreamCount: handlers.count,
            interfaceNameCalls: interfaceNameCalls,
            supportedBandsCalls: supportedBandsCalls,
            supportedChannelsCalls: supportedChannelsCalls,
            rawChannelsCalls: rawChannelsCalls,
            deviceCapabilitiesCalls: deviceCapabilitiesCalls
        )
    }

}

private actor ManualWiFiScanClock: WiFiScanClock {
    private var instant: Duration = .zero
    private let suspendsSleeps: Bool
    private var sleepEntered = false
    private var sleepEnteredContinuation: CheckedContinuation<Void, Never>?
    private(set) var recordedSleeps: [Duration] = []

    init(suspendsSleeps: Bool = false) {
        self.suspendsSleeps = suspendsSleeps
    }

    func now() -> Duration { instant }

    func sleep(for duration: Duration) async throws {
        recordedSleeps.append(duration)
        sleepEntered = true
        sleepEnteredContinuation?.resume()
        sleepEnteredContinuation = nil
        if suspendsSleeps {
            try await Task.sleep(for: .seconds(60))
        } else {
            instant += duration
        }
    }

    func advance(by duration: Duration) {
        instant += duration
    }

    func waitUntilSleepEntered() async {
        guard !sleepEntered else { return }
        await withCheckedContinuation { continuation in
            sleepEnteredContinuation = continuation
        }
    }
}

private actor ControlledWiFiProbeClock {
    private(set) var scheduledDurations: [Duration] = []
    private var sleepers: [CheckedContinuation<Void, Error>] = []
    private var scheduledWaiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        scheduledDurations.append(duration)
        scheduledWaiters.forEach { $0.resume() }
        scheduledWaiters.removeAll()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(continuation)
            }
        } onCancel: {
            Task { await self.cancelOneProbe() }
        }
    }

    func waitUntilScheduled() async {
        guard sleepers.isEmpty else { return }
        await withCheckedContinuation { continuation in scheduledWaiters.append(continuation) }
    }

    func advanceOneProbe() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().resume()
    }

    private func cancelOneProbe() {
        guard !sleepers.isEmpty else { return }
        sleepers.removeFirst().resume(throwing: CancellationError())
    }
}

private actor RecordingCyclePipeline: WiFiObservationPipelining {
    struct Call: Sendable {
        let networks: [WiFiNetwork]
        let context: WiFiObservationCycleContext
    }

    private(set) var calls: [Call] = []
    private let currentStatus: WiFiCurrentStatus

    init(currentStatus: WiFiCurrentStatus = WiFiCurrentStatus(
        timestamp: Date(timeIntervalSince1970: 1),
        isConnected: false,
        isWiFiPowerOn: true
    )) {
        self.currentStatus = currentStatus
    }

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        calls.append(Call(networks: networks, context: context))
        let error = context.environmentError
        return WiFiObservationCycleResult(
            observation: WiFiObservation(
                timestamp: context.timestamp,
                currentStatus: currentStatus,
                environmentSnapshot: WiFiEnvironmentSnapshot(
                    timestamp: context.timestamp,
                    interfaceName: context.interfaceName,
                    networks: [],
                    error: error
                ),
                errors: [error].compactMap { $0 }
            ),
            inferredRegion: RegulatoryDomainResolver.resolve(
                userOverride: context.userRegionOverride,
                userDefaultsOverride: context.userDefaultsRegionOverride,
                supportedChannelsRaw: context.supportedChannelsRaw,
                apCountryCodes: []
            )
        )
    }

}

@MainActor
private final class CountingInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    private let interfaces: [NetworkInterfaceInfo]
    private let capturedAt: Date
    private(set) var captureCount = 0

    init(interfaces: [NetworkInterfaceInfo], capturedAt: Date) {
        self.interfaces = interfaces
        self.capturedAt = capturedAt
    }

    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        captureCount += 1
        return NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: interfaces
        )
    }
}

private struct ImmediateInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: Date(timeIntervalSince1970: 42),
            interfaces: []
        )
    }
}

@MainActor
private final class IncrementingInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    private var captureCount = 0
    private let origin = Date(timeIntervalSince1970: 1_752_003_000)

    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        defer { captureCount += 1 }
        return NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: origin.addingTimeInterval(Double(captureCount)),
            interfaces: []
        )
    }
}

@MainActor
private final class SequentialInterfaceSnapshotSource: NetworkInterfaceSnapshotSourcing {
    private let captures: [(capturedAt: Date, interfaces: [NetworkInterfaceInfo])]
    private(set) var capturedSnapshots: [NetworkInterfaceSnapshot] = []

    init(captures: [(capturedAt: Date, interfaces: [NetworkInterfaceInfo])]) {
        precondition(!captures.isEmpty)
        self.captures = captures
    }

    var captureCount: Int { capturedSnapshots.count }

    func capture(cycleID: UUID) async -> NetworkInterfaceSnapshot {
        let index = min(capturedSnapshots.count, captures.count - 1)
        let capture = captures[index]
        let snapshot = NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capture.capturedAt,
            interfaces: capture.interfaces.map { interface in
                guard interface.isWiFiInterface else { return interface }
                let evidence = WiFiLinkRawEvidence(
                    snapshotCycleID: cycleID,
                    capturedAt: capture.capturedAt,
                    interfaceName: interface.interfaceName,
                    mode: .station,
                    radio: .reportedOn,
                    linkActive: true,
                    ssid: interface.ssid,
                    bssid: interface.bssid
                )
                return NetworkInterfaceInfo(
                    interfaceName: interface.interfaceName,
                    interfaceIndex: interface.interfaceIndex ?? 4,
                    hardwareMAC: interface.hardwareMAC,
                    isWiFiInterface: true,
                    wifiLinkEvidence: evidence,
                    ipv4Addresses: interface.ipv4Addresses,
                    subnetMasks: interface.subnetMasks,
                    router: interface.router,
                    dnsServers: interface.dnsServers,
                    ssid: interface.ssid,
                    bssid: interface.bssid,
                    channel: interface.channel,
                    band: interface.band,
                    rssi: interface.rssi,
                    txRate: interface.txRate,
                    phyMode: interface.phyMode,
                    security: interface.security
                )
            }
        )
        capturedSnapshots.append(snapshot)
        return snapshot
    }
}

private func runtimeInterfaceInfo(
    interfaceName: String = "en0",
    ssid: String?
) -> NetworkInterfaceInfo {
    NetworkInterfaceInfo(
        interfaceName: interfaceName,
        hardwareMAC: "00:11:22:33:44:55",
        isWiFiInterface: interfaceName.hasPrefix("en"),
        ipv4Addresses: ["192.0.2.2"],
        subnetMasks: ["255.255.255.0"],
        router: "192.0.2.1",
        dnsServers: ["192.0.2.1"],
        ssid: ssid,
        bssid: "AA:BB:CC:DD:EE:FF",
        channel: 36,
        band: .band5GHz,
        rssi: -48,
        txRate: 1200,
        phyMode: "ax",
        security: "WPA3"
    )
}

private actor SuspendingSecondGatewayLatencyProvider: GatewayLatencyProviding, WiFiBoundGatewayMeasuring {
    private let result: GatewayLatencyResult
    private var measurementCount = 0
    private var secondMeasurementEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(result: GatewayLatencyResult) {
        self.result = result
    }

    func measure(routerIP: String?) async -> GatewayLatencyResult {
        measurementCount += 1
        if measurementCount == 2 {
            secondMeasurementEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return result
    }

    func measure(target: WiFiGatewayProbeTarget) async -> GatewayLatencyResult {
        measurementCount += 1
        if measurementCount == 2 {
            secondMeasurementEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        return GatewayLatencyResult(
            timestamp: result.timestamp,
            routerIP: target.address,
            probeOutcome: .notTested,
            attemptID: UUID(),
            cycleID: target.snapshotCycleID,
            interfaceName: target.interfaceName,
            interfaceBound: true
        )
    }

    func waitUntilSecondMeasurementEntered() async {
        guard !secondMeasurementEntered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func releaseSecondMeasurement() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ProjectionCyclePipeline: WiFiObservationPipelining {
    let channelQualities: [ChannelQuality]
    let recommendations: [ChannelRecommendation]
    let inferredRegion: RegionInferenceResult

    init(
        channelQualities: [ChannelQuality],
        recommendations: [ChannelRecommendation],
        inferredRegion: RegionInferenceResult
    ) {
        self.channelQualities = channelQualities
        self.recommendations = recommendations
        self.inferredRegion = inferredRegion
    }

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        WiFiObservationCycleResult(
            observation: WiFiObservation(
                timestamp: context.timestamp,
                channelAnalysis: channelQualities,
                channelRecommendation: recommendations
            ),
            inferredRegion: inferredRegion
        )
    }

}

private actor ErrorAwareProjectionCyclePipeline: WiFiObservationPipelining {
    let channelQualities: [ChannelQuality]
    let recommendations: [ChannelRecommendation]
    let inferredRegion: RegionInferenceResult
    private(set) var callCount = 0

    init(
        channelQualities: [ChannelQuality],
        recommendations: [ChannelRecommendation],
        inferredRegion: RegionInferenceResult
    ) {
        self.channelQualities = channelQualities
        self.recommendations = recommendations
        self.inferredRegion = inferredRegion
    }

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        callCount += 1
        let error = context.environmentError
        return WiFiObservationCycleResult(
            observation: WiFiObservation(
                timestamp: context.timestamp,
                environmentSnapshot: WiFiEnvironmentSnapshot(
                    timestamp: context.timestamp,
                    interfaceName: context.interfaceName,
                    networks: [],
                    error: error
                ),
                channelAnalysis: error == nil ? channelQualities : nil,
                channelRecommendation: error == nil ? recommendations : nil,
                errors: [error].compactMap { $0 }
            ),
            inferredRegion: inferredRegion
        )
    }

}

private actor SuspendingFirstCyclePipeline: WiFiObservationPipelining {
    private var callCount = 0
    private var firstCycleEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var completedBSSIDWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var completedBSSIDs: [String] = []

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        callCount += 1
        if callCount == 1 {
            firstCycleEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }

        let bssid = networks.first?.bssid
        if let bssid { completedBSSIDs.append(bssid) }
        var pendingCompletedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        completedBSSIDWaiters = completedBSSIDWaiters.filter { waiter in
            if completedBSSIDs.count >= waiter.0 {
                pendingCompletedWaiters.append(waiter)
                return false
            }
            return true
        }
        pendingCompletedWaiters.forEach { $0.1.resume() }
        return WiFiObservationCycleResult(
            observation: WiFiObservation(
                timestamp: context.timestamp,
                currentStatus: WiFiCurrentStatus(
                    timestamp: context.timestamp,
                    bssid: bssid,
                    isConnected: bssid != nil,
                    isWiFiPowerOn: true
                ),
                environmentSnapshot: WiFiEnvironmentSnapshot(
                    timestamp: context.timestamp,
                    interfaceName: context.interfaceName,
                    networks: []
                )
            ),
            inferredRegion: RegulatoryDomainResolver.resolve(
                userOverride: nil,
                userDefaultsOverride: nil,
                supportedChannelsRaw: context.supportedChannelsRaw,
                apCountryCodes: []
            )
        )
    }

    func waitUntilFirstCycleEntered() async {
        guard !firstCycleEntered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func releaseFirstCycle() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilCompletedBSSIDCount(_ target: Int) async {
        if completedBSSIDs.count >= target { return }
        await withCheckedContinuation { completedBSSIDWaiters.append((target, $0)) }
    }

}

private actor CancellationAwareFirstCyclePipeline: WiFiObservationPipelining {
    private var firstCycleEntered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private(set) var receivedBSSIDs: [String] = []
    private(set) var wasCancelled = false

    func produceCycle(
        networks: [WiFiNetwork],
        context: WiFiObservationCycleContext
    ) async -> WiFiObservationCycleResult {
        if let bssid = networks.first?.bssid {
            receivedBSSIDs.append(bssid)
        }
        if receivedBSSIDs.count == 1 {
            firstCycleEntered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                wasCancelled = true
            }
        }
        return WiFiObservationCycleResult(
            observation: WiFiObservation(timestamp: context.timestamp),
            inferredRegion: RegulatoryDomainResolver.resolve(
                userOverride: nil,
                userDefaultsOverride: nil,
                supportedChannelsRaw: context.supportedChannelsRaw,
                apCountryCodes: []
            )
        )
    }

    func waitUntilFirstCycleEntered() async {
        guard !firstCycleEntered else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }
}

@MainActor
private final class CapturingObservationConsumer: WiFiObservationConsuming {
    private(set) var observations: [WiFiObservation] = []

    func consume(_ observation: WiFiObservation) async throws {
        observations.append(observation)
    }
}

private enum RecordedObservationLifecycleEvent: Equatable {
    case started(date: Date, interval: Duration)
    case observation
    case stopped(date: Date)
}

@MainActor
private final class LifecycleRecordingConsumer: WiFiObservationConsuming {
    private(set) var events: [RecordedObservationLifecycleEvent] = []

    func consume(_ observation: WiFiObservation) async throws {
        _ = observation
        events.append(.observation)
    }

    func consumeLifecycle(_ event: WiFiObservationLifecycleEvent) async throws {
        switch event {
        case .started(let date, let expectedInterval):
            events.append(.started(date: date, interval: expectedInterval))
        case .stopped(let date):
            events.append(.stopped(date: date))
        }
    }
}

private final class LockedDateSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(_ seconds: [TimeInterval]) {
        values = seconds.map(Date.init(timeIntervalSince1970:))
    }

    func next() -> Date {
        lock.withLock { values.isEmpty ? Date(timeIntervalSince1970: -1) : values.removeFirst() }
    }
}

@MainActor
private final class SuspendedObservationConsumer: WiFiObservationConsuming, @unchecked Sendable {
    private let lock = NSLock()
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var suspensionContinuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var isSuspendedValue = false
    private var isResumed = false
    private(set) var observations: [WiFiObservation] = []

    var isSuspended: Bool { lock.withLock { isSuspendedValue } }

    func consume(_ observation: WiFiObservation) async throws {
        observations.append(observation)
        var enteredWaiter: CheckedContinuation<Void, Never>?
        lock.withLock {
            isSuspendedValue = true
            hasEntered = true
            enteredWaiter = enteredContinuation
            enteredContinuation = nil
        }
        enteredWaiter?.resume()
        await withCheckedContinuation { continuation in
            var resumeImmediately = false
            lock.withLock {
                if isResumed {
                    resumeImmediately = true
                } else {
                    suspensionContinuation = continuation
                }
            }
            if resumeImmediately { continuation.resume() }
        }
        lock.withLock { isSuspendedValue = false }
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            var resumeImmediately = false
            lock.withLock {
                if hasEntered {
                    resumeImmediately = true
                } else {
                    enteredContinuation = continuation
                }
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func resume() {
        var pending: CheckedContinuation<Void, Never>?
        lock.withLock {
            isResumed = true
            pending = suspensionContinuation
            suspensionContinuation = nil
        }
        pending?.resume()
    }
}

private actor AsyncCompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

@MainActor
private final class EventCounter {
    private(set) var count = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func increment() {
        count += 1
        var pending: [(Int, CheckedContinuation<Void, Never>)] = []
        waiters = waiters.filter { waiter in
            if count >= waiter.0 {
                pending.append(waiter)
                return false
            }
            return true
        }
        pending.forEach { $0.1.resume() }
    }

    func waitForCount(_ target: Int) async {
        if count >= target { return }
        await withCheckedContinuation { waiters.append((target, $0)) }
    }
}

@MainActor
private final class MainActorMilestone {
    private var isReached = false
    private var continuation: CheckedContinuation<Void, Never>?

    func reach() {
        isReached = true
        continuation?.resume()
        continuation = nil
    }

    func waitUntilReached() async {
        guard !isReached else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

@MainActor
private final class FailOnceObservationConsumer: WiFiObservationConsuming {
    private enum TestError: Error {
        case expectedFailure
    }

    private(set) var attemptedTimestamps: [Date] = []
    private var shouldFail = true

    func consume(_ observation: WiFiObservation) async throws {
        attemptedTimestamps.append(observation.timestamp)
        if shouldFail {
            shouldFail = false
            throw TestError.expectedFailure
        }
    }
}
