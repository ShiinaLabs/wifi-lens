import AppKit
import Testing
@testable import WiFi_Lens

struct EditionCompositionTests {

    @MainActor
    @Test("OSS main windows begin on the edition-selected route")
    func mainWindowUsesEditionSelectedInitialRoute() {
        let defaultScene = MainWindowSceneState()
        let fallbackScene = MainWindowSceneState(selectedPage: nil)

        #expect(defaultScene.selectedPage == EditionComposition.initialMainWindowRoute)
        #expect(fallbackScene.selectedPage == EditionComposition.initialMainWindowRoute)
    }

    @MainActor
    @Test("edition composition creates the roaming presentation model")
    func editionCompositionCreatesRoamingViewModel() {
        let viewModel = EditionComposition.makeRoamingViewModel()

        #expect(viewModel.state == .idle)
    }

    @MainActor
    @Test("spectrum charts are inactive until a window leases the route")
    func spectrumChartsStartInactive() {
        let chart = BandChartViewModel(band: .band24GHz)

        #expect(chart.isViewVisible == false)
    }

    @MainActor
    @Test("shared route resources remain active until the final window releases them")
    func sharedRouteResourcesUsePerWindowLeases() async {
        var spectrumTransitions: [Bool] = []
        var bleTransitions: [Bool] = []
        let bleProbe = SignalProbe()
        let coordinator = MainWindowRouteResourceCoordinator(
            setSpectrumActive: { spectrumTransitions.append($0) },
            setBLEActive: { active in
                bleTransitions.append(active)
                bleProbe.signal()
            }
        )
        let windowA = UUID()
        let windowB = UUID()

        coordinator.register(windowID: windowA, route: .spectrum)
        coordinator.register(windowID: windowB, route: .overview)
        coordinator.update(windowID: windowB, route: .spectrum)
        coordinator.update(windowID: windowA, route: .overview)
        #expect(spectrumTransitions == [true])

        coordinator.release(windowID: windowB)
        #expect(spectrumTransitions == [true, false])

        coordinator.update(windowID: windowA, route: .bleScanner)
        await bleProbe.waitForSignal()
        coordinator.register(windowID: windowB, route: .overview)
        coordinator.update(windowID: windowB, route: .bleScanner)
        coordinator.release(windowID: windowA)
        #expect(bleTransitions == [true])

        coordinator.release(windowID: windowB)
        #expect(bleTransitions == [true, false])
    }

    @MainActor
    @Test("AppKit window close releases its final shared route resource lease")
    func appKitWindowCloseReleasesRouteResourceLease() {
        var spectrumTransitions: [Bool] = []
        let resources = MainWindowRouteResourceCoordinator(
            setSpectrumActive: { spectrumTransitions.append($0) }
        )
        let lifecycle = MainWindowLifecycleCoordinator(isActiveAtRegistration: { _ in false })
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scene = MainWindowSceneState(selectedPage: .spectrum)

        let result = lifecycle.register(
            window,
            sceneState: scene,
            registerEdition: {
                resources.register(windowID: scene.id, route: scene.selectedPage)
                return true
            },
            rollbackEdition: { resources.release(windowID: scene.id) },
            onClose: { resources.release(windowID: $0) }
        )
        #expect(result == .registered)
        #expect(spectrumTransitions == [true])

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        #expect(spectrumTransitions == [true, false])
        #expect(lifecycle.sceneState(for: window) == nil)
    }

    @MainActor
    @Test("closing the final main window preserves the app-owned scene opener and pending route")
    func closingFinalMainWindowPreservesSceneOpenerAndRoute() {
        let lifecycle = MainWindowLifecycleCoordinator(isActiveAtRegistration: { _ in false })
        var openRequests = 0
        lifecycle.installOpenSceneAction { openRequests += 1 }

        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let originalScene = MainWindowSceneState()
        #expect(lifecycle.register(
            window,
            sceneState: originalScene,
            registerEdition: { true },
            rollbackEdition: {}
        ) == .registered)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        lifecycle.requestMainWindow(route: .timeline)

        #expect(openRequests == 1)

        let replacementWindow = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let replacementScene = MainWindowSceneState()
        #expect(lifecycle.register(
            replacementWindow,
            sceneState: replacementScene,
            registerEdition: { true },
            rollbackEdition: {}
        ) == .registered)
        #expect(replacementScene.selectedPage == .timeline)
    }

    @MainActor
    @Test("duplicate registration and unchanged routes do not repeat resource transitions")
    func sharedRouteResourceTransitionsAreEdgeTriggered() {
        var spectrumTransitions: [Bool] = []
        var bleTransitions: [Bool] = []
        let coordinator = MainWindowRouteResourceCoordinator(
            setSpectrumActive: { spectrumTransitions.append($0) },
            setBLEActive: { bleTransitions.append($0) }
        )
        let windowID = UUID()

        coordinator.register(windowID: windowID, route: .overview)
        coordinator.register(windowID: windowID, route: .overview)
        coordinator.update(windowID: windowID, route: .overview)
        coordinator.update(windowID: windowID, route: .spectrum)
        coordinator.update(windowID: windowID, route: .spectrum)
        coordinator.release(windowID: windowID)
        coordinator.release(windowID: windowID)

        #expect(spectrumTransitions == [true, false])
        #expect(bleTransitions.isEmpty)
    }

    @MainActor
    @Test("a released BLE route cannot revive a suspended scan start")
    func releasedBLERouteCannotReviveSuspendedStart() async {
        let scanner = PausableBLEScanner()
        let viewModel = BLEViewModel(
            scanner: scanner,
            authorizationOverride: true,
            monitorsBluetoothPower: false
        )
        let coordinator = MainWindowRouteResourceCoordinator()
        let windowID = UUID()

        coordinator.bind(spectrumViewModels: [], bleViewModel: viewModel)
        coordinator.register(windowID: windowID, route: .bleScanner)
        await scanner.waitUntilStartIsSuspended()

        coordinator.release(windowID: windowID)
        await scanner.resumeNextStart()
        await scanner.waitUntilStoppedOnce()

        #expect(viewModel.isScanning == false)
        #expect(await scanner.activeSessionCount == 0)
    }

    @MainActor
    @Test("a stale BLE start cannot stop a newly bound view model")
    func staleBLEStartCannotStopNewBinding() async {
        let oldScanner = PausableBLEScanner()
        let newScanner = PausableBLEScanner(startsSuspended: false)
        let oldViewModel = BLEViewModel(
            scanner: oldScanner,
            authorizationOverride: true,
            monitorsBluetoothPower: false
        )
        let newViewModel = BLEViewModel(
            scanner: newScanner,
            authorizationOverride: true,
            monitorsBluetoothPower: false
        )
        let coordinator = MainWindowRouteResourceCoordinator()
        let windowID = UUID()

        coordinator.bind(spectrumViewModels: [], bleViewModel: oldViewModel)
        coordinator.register(windowID: windowID, route: .bleScanner)
        await oldScanner.waitUntilStartIsSuspended()

        coordinator.bind(spectrumViewModels: [], bleViewModel: newViewModel)
        await newScanner.waitUntilStartScanningCalled()
        await oldScanner.resumeNextStart()
        await oldScanner.waitUntilStoppedOnce()

        #expect(newViewModel.isScanning)
        #expect(await newScanner.activeSessionCount == 1)

        coordinator.release(windowID: windowID)
        await newScanner.waitUntilActiveSessionCountZero()
    }

    @MainActor
    @Test("BLE scan session stop is idempotent and finishes its stream")
    func BLEScanSessionStopIsIdempotentAndFinishesStream() async {
        let scanner = PausableBLEScanner(startsSuspended: false)
        let session = await scanner.startScanning()
        let consumer = Task {
            for await _ in session.events {}
            return true
        }

        await session.stop()
        await session.stop()

        #expect(await consumer.value)
        #expect(await scanner.activeSessionCount == 0)
        #expect(await scanner.stopCount == 1)
    }

    @Test("BLE event stream keeps only the two newest observations while a consumer is stalled")
    func BLEEventStreamUsesBoundedNewestBuffer() async {
        let channel = BLEScanEventStreamFactory.make()

        let first = channel.continuation.yield(.bluetoothStateChanged(.unknown))
        let second = channel.continuation.yield(.bluetoothStateChanged(.poweredOff))
        let third = channel.continuation.yield(.bluetoothStateChanged(.poweredOn))
        channel.continuation.finish()

        #expect(yieldWasEnqueued(first))
        #expect(yieldWasEnqueued(second))
        #expect(yieldDroppedBluetoothState(third, expected: .unknown))

        var retainedStates: [BLEBluetoothState] = []
        for await event in channel.events {
            if case .bluetoothStateChanged(let state) = event {
                retainedStates.append(state)
            }
        }
        #expect(retainedStates.count == 2)
        #expect(isBluetoothState(retainedStates[0], .poweredOff))
        #expect(isBluetoothState(retainedStates[1], .poweredOn))
    }

    @Test("shared Timeline route remains available to OSS")
    func sharedTimelineRouteRemainsAvailable() {
        #expect(SidebarPage.allCases.contains(.timeline))
    }

    @Test("OSS timeline contribution remains a locked preview")
    func ossTimelineContributionIsLockedPreview() {
        #expect(EditionComposition.timelineToolbarDescriptor == nil)
        #expect(EditionComposition.isTimelineLockedPreview)
    }

    @Test("OSS recording segment remains locked")
    func ossRecordingSegmentRemainsLocked() {
        let descriptor = EditionComposition.spectrumToolbarDescriptor
        #expect(descriptor.items.first { $0.id == .spectrumRecording }?.isLocked == true)
    }

    @MainActor
    @Test("OSS supplies the locked Markdown export preview through edition composition")
    func ossSuppliesLockedMarkdownExportPreview() {
        switch EditionComposition.markdownExportCommandContribution {
        case .lockedPreview:
            break
        case .available:
            Issue.record("OSS must not supply an executable Markdown export action")
        }
    }

    @MainActor
    @Test("repeated termination requests share one ordered operation and one AppKit reply")
    func repeatedTerminationRequestsShareOneOperation() async {
        let stopGate = TerminationTestGate()
        let replyProbe = TerminationBoolProbe()
        var steps: [String] = []
        let coordinator = ApplicationTerminationCoordinator(
            terminationDeadline: .seconds(60),
            waitForDeadline: { duration in
                try await Task.sleep(for: duration)
            },
            reply: { replyProbe.record($0) }
        )
        coordinator.configure(
            stopRuntime: {
                steps.append("runtime")
                await stopGate.wait()
            },
            terminateEdition: {
                steps.append("edition")
            }
        )

        #expect(coordinator.requestTermination() == .terminateLater)
        #expect(coordinator.requestTermination() == .terminateLater)
        await stopGate.waitUntilEntered()
        #expect(steps == ["runtime"])
        #expect(replyProbe.values.isEmpty)

        await stopGate.open()
        await replyProbe.waitForFirstValue()

        #expect(steps == ["runtime", "edition"])
        #expect(replyProbe.values == [true])
        #expect(coordinator.requestTermination() == .terminateLater)
        #expect(replyProbe.values == [true])
    }

    @MainActor
    @Test("termination deadline replies once when runtime stop ignores cancellation")
    func terminationDeadlineDoesNotAwaitNonCooperativeRuntimeStop() async {
        let stopGate = TerminationTestGate()
        let deadlineGate = TerminationTestGate()
        let replyProbe = TerminationBoolProbe()
        let cancellationProbe = TerminationBoolProbe()
        var editionCalls = 0
        let coordinator = ApplicationTerminationCoordinator(
            terminationDeadline: .seconds(3),
            waitForDeadline: { _ in await deadlineGate.wait() },
            reply: { replyProbe.record($0) }
        )
        coordinator.configure(
            stopRuntime: {
                await stopGate.wait()
                cancellationProbe.record(Task.isCancelled)
            },
            terminateEdition: {
                editionCalls += 1
            }
        )

        #expect(coordinator.requestTermination() == .terminateLater)
        await stopGate.waitUntilEntered()
        await deadlineGate.waitUntilEntered()
        #expect(replyProbe.values.isEmpty)

        await deadlineGate.open()
        await replyProbe.waitForFirstValue()

        #expect(replyProbe.values == [true])
        #expect(editionCalls == 0)

        await stopGate.open()
        await cancellationProbe.waitForFirstValue()

        #expect(cancellationProbe.values == [true])
        #expect(editionCalls == 0)
        #expect(replyProbe.values == [true])
    }

    @MainActor
    @Test("a cancelled termination operation skips edition cleanup")
    func cancelledTerminationOperationSkipsEditionCleanup() async {
        let stopGate = TerminationTestGate()
        var editionCalls = 0
        let operation = Task { @MainActor in
            await performApplicationTermination(
                stopRuntime: { await stopGate.wait() },
                terminateEdition: { editionCalls += 1 }
            )
        }

        await stopGate.waitUntilEntered()
        operation.cancel()
        await stopGate.open()

        #expect(await operation.value == false)
        #expect(editionCalls == 0)
    }

    @MainActor
    @Test("OSS termination hook completes without edition work")
    func ossTerminationHookIsNoOp() async {
        await EditionComposition.prepareForTermination()
    }
}

@MainActor
private final class SignalProbe {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForSignal() async {
        if isSignaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor PausableBLEScanner: BLEScanning {
    private var shouldSuspendStarts: Bool
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var startObservedWaiters: [CheckedContinuation<Void, Never>] = []
    private var startCalledWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var emptySessionWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuations: [UUID: AsyncStream<BLEScanEvent>.Continuation] = [:]
    private(set) var startCalled = false
    private(set) var stopCount = 0

    init(startsSuspended: Bool = true) {
        shouldSuspendStarts = startsSuspended
    }

    var activeSessionCount: Int { continuations.count }

    func startScanning() async -> BLEScanSession {
        startCalled = true
        let pendingStartCalledWaiters = startCalledWaiters
        startCalledWaiters.removeAll()
        pendingStartCalledWaiters.forEach { $0.resume() }
        if shouldSuspendStarts {
            let observed = startObservedWaiters
            startObservedWaiters.removeAll()
            observed.forEach { $0.resume() }
            await withCheckedContinuation { startWaiters.append($0) }
        }
        let id = UUID()
        var continuation: AsyncStream<BLEScanEvent>.Continuation!
        let stream = AsyncStream<BLEScanEvent> { continuation = $0 }
        continuations[id] = continuation
        return BLEScanSession(events: stream) { [weak self] in
            await self?.stop(id: id)
        }
    }

    func waitUntilStartIsSuspended() async {
        if !startWaiters.isEmpty { return }
        await withCheckedContinuation { startObservedWaiters.append($0) }
    }

    func resumeNextStart() {
        shouldSuspendStarts = false
        guard !startWaiters.isEmpty else { return }
        startWaiters.removeFirst().resume()
    }

    func waitUntilStartScanningCalled() async {
        if startCalled { return }
        await withCheckedContinuation { startCalledWaiters.append($0) }
    }

    func waitUntilStoppedOnce() async {
        if stopCount >= 1 { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }

    func waitUntilActiveSessionCountZero() async {
        if continuations.isEmpty { return }
        await withCheckedContinuation { emptySessionWaiters.append($0) }
    }

    private func stop(id: UUID) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        stopCount += 1
        let pendingStopWaiters = stopWaiters
        stopWaiters.removeAll()
        pendingStopWaiters.forEach { $0.resume() }
        if continuations.isEmpty {
            let pendingEmptySessionWaiters = emptySessionWaiters
            emptySessionWaiters.removeAll()
            pendingEmptySessionWaiters.forEach { $0.resume() }
        }
        continuation.finish()
    }
}

private actor TerminationTestGate {
    private var isOpen = false
    private var hasEntered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        hasEntered = true
        let pendingEntryWaiters = entryWaiters
        entryWaiters.removeAll()
        pendingEntryWaiters.forEach { $0.resume() }
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private final class TerminationBoolProbe {
    private(set) var values: [Bool] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record(_ value: Bool) {
        values.append(value)
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForFirstValue() async {
        if !values.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private func yieldWasEnqueued(
    _ result: AsyncStream<BLEScanEvent>.Continuation.YieldResult
) -> Bool {
    if case .enqueued = result { return true }
    return false
}

private func yieldDroppedBluetoothState(
    _ result: AsyncStream<BLEScanEvent>.Continuation.YieldResult,
    expected: BLEBluetoothState
) -> Bool {
    guard case .dropped(let event) = result,
          case .bluetoothStateChanged(let state) = event else {
        return false
    }
    return isBluetoothState(state, expected)
}

private func isBluetoothState(_ lhs: BLEBluetoothState, _ rhs: BLEBluetoothState) -> Bool {
    switch (lhs, rhs) {
    case (.unknown, .unknown),
         (.resetting, .resetting),
         (.unsupported, .unsupported),
         (.poweredOff, .poweredOff),
         (.poweredOn, .poweredOn),
         (.unauthorized, .unauthorized):
        true
    default:
        false
    }
}
