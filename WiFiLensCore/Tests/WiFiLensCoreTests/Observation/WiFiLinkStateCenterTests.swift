import Foundation
import Testing
@testable import WiFiLensCore

@Suite("WiFi link evidence interpretation")
struct WiFiLinkEvidenceInterpreterTests {
    @Test("A same-cycle station link-active sample confirms association without SSID")
    func associationDoesNotRequireNetworkIdentity() {
        let sample = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let result = WiFiLinkInterpreter.evaluate(sample, expectedCycleID: sample.snapshotCycleID, expectedCapturedAt: sample.capturedAt)
        #expect(result.state == .associated)
        #expect(result.reason == .stationMode)
    }

    @Test("A single explicit negative sample is only a candidate")
    func disconnectCandidateRemainsUnknown() {
        let sample = evidence(
            mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false,
            serviceActive: true, modeRawValue: 0, radioPowerOnRaw: true,
            interfaceFlagsUp: true, interfaceFlagsRunning: true
        )
        let result = WiFiLinkInterpreter.evaluate(sample, expectedCycleID: sample.snapshotCycleID)
        #expect(result.state == .unknown)
        #expect(result.candidateState == .disconnected)
    }

    @Test("Contradictory, stale, and cross-cycle evidence stays unknown")
    func contradictoryEvidenceIsUnknown() {
        let sample = evidence(mode: .station, radio: .reportedOn, linkActive: false)
        #expect(WiFiLinkInterpreter.evaluate(sample, expectedCycleID: sample.snapshotCycleID).state == .unknown)
        #expect(WiFiLinkInterpreter.evaluate(sample, expectedCycleID: UUID()).reason == .cycleMismatch)
        #expect(WiFiLinkInterpreter.evaluate(sample, expectedCycleID: sample.snapshotCycleID, expectedCapturedAt: sample.capturedAt.addingTimeInterval(1)).reason == .captureTimestampMismatch)
    }

    @Test("Reported-off ambiguity and failed reads do not become a confirmed radio or link failure")
    func ambiguousPowerAndModeRemainUnknown() {
        let off = WiFiLinkRawEvidence(
            snapshotCycleID: UUID(), capturedAt: Date(), interfaceName: "en0",
            mode: .station, radio: .reportedOffOrReadFailure, linkActive: false,
            radioPowerOnRaw: false
        )
        let unavailable = evidence(mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false)
        #expect(off.radioPowerOnRaw == false)
        #expect(unavailable.radioPowerOnRaw == nil)
        #expect(WiFiLinkInterpreter.evaluate(off, expectedCycleID: off.snapshotCycleID).state == .unknown)
        #expect(WiFiLinkInterpreter.evaluate(unavailable, expectedCycleID: unavailable.snapshotCycleID).state == .unknown)
    }

    @Test("Invalid collection timing is not trusted")
    func invalidCaptureWindowIsUnknown() {
        let at = Date(timeIntervalSince1970: 100)
        let sample = WiFiLinkRawEvidence(
            snapshotCycleID: UUID(), capturedAt: at, interfaceName: "en0", mode: .station,
            radio: .reportedOn, linkActive: true, captureStartedAt: at.addingTimeInterval(1), captureEndedAt: at
        )
        #expect(WiFiLinkInterpreter.evaluate(sample, expectedCycleID: sample.snapshotCycleID).state == .unknown)
    }

    #if DEBUG
    @Test("Debug diagnostic evidence preserves raw none mode and omits network identity")
    func diagnosticEvidenceFieldsPreserveModeWithoutIdentity() {
        let sample = evidence(
            mode: .noneOrReadFailure,
            radio: .reportedOn,
            linkActive: false,
            ssid: "Private SSID",
            bssid: "02:11:22:33:44:55",
            modeRawValue: 0,
            radioPowerOnRaw: true
        )
        let fields = WiFiLinkDiagnosticEvidenceFields.make(from: sample)

        #expect(fields["modeRaw"] as? Int == 0)
        #expect(fields["mode"] as? String == "noneOrReadFailure")
        #expect(fields["modeReadAmbiguous"] as? Bool == true)
        #expect(!fields.keys.contains { $0.localizedCaseInsensitiveContains("ssid") })
        #expect(!fields.keys.contains { $0.localizedCaseInsensitiveContains("bssid") })
        #expect(!fields.values.contains { ($0 as? String) == "Private SSID" })
        #expect(!fields.values.contains { ($0 as? String) == "02:11:22:33:44:55" })
    }
    #endif
}

@Suite("WiFi link state center")
@MainActor
struct WiFiLinkStateCenterTests {
    @Test("Startup association establishes a baseline and missing identity remains associated")
    func startupBaselineAndUnknownSSID() async {
        let sample = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let collector = SequenceCollector([sample])
        let trigger = FakeLinkTrigger()
        let center = WiFiLinkStateCenter(collector: collector, trigger: trigger, pollingInterval: .seconds(3_600))
        await center.start()
        let state = await center.snapshot()
        #expect(state.state == .associated)
        #expect(state.networkIdentity == nil)
        #expect(state.linkEpoch == 0)
        await center.stop()
        #expect(trigger.startCount == 1)
        #expect(trigger.stopCount == 1)
    }

    @Test("Observed AP-loss evidence enters candidate review without confirming disconnect")
    func observedAPLossStartsActiveReviewAndStaysUnknown() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate1 = observedAPLoss(offset: 1)
        let candidate2 = observedAPLoss(offset: 2)
        let collector = SequenceCollector([baseline, candidate1, candidate2])
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector,
            trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600),
            reviewInterval: .seconds(1),
            reviewClock: clock
        )

        await center.start()
        await center.refresh()
        #expect((await center.snapshot()).state == .unknown)
        #expect((await center.snapshot()).reason == .disconnectEvidenceNotValidated)
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await collector.waitForCaptureCount(3)
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)

        #expect(await clock.releasedCount() == 1)
        #expect(await clock.pendingCount() == 0)
        #expect((await center.snapshot()).state == .unknown)
        #expect((await center.snapshot()).reason == .disconnectEvidenceNotValidated)
        await center.stop()
    }

    @Test("A transient association loss gets one review and recovers without transition events")
    func transientAssociationLossHasBoundedReview() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate1 = observedAPLoss(offset: 1)
        let candidate2 = observedAPLoss(offset: 2)
        let recovered = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 3)
        let collector = SequenceCollector([baseline, candidate1, candidate2, recovered])
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        let recorder = LinkEventRecorder()
        let stream = await center.events()
        let eventTask = Task { for await event in stream { await recorder.append(event) } }

        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await collector.waitForCaptureCount(3)
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)

        #expect(await clock.pendingCount() == 0)
        #expect((await center.snapshot()).state == .unknown)
        await center.refresh()
        #expect((await center.snapshot()).state == .associated)
        #expect((await center.snapshot()).linkEpoch == 0)

        await center.stop()
        await recorder.waitForCount(1)
        eventTask.cancel()
        await eventTask.value
        #expect(await recorder.events().map(\.type) == [.continuityReset])
    }

    @Test("Dozens of continuous candidate samples do not restart active review or advance the epoch")
    func sustainedCandidateCycleStaysBounded() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidates = (1...40).map { observedAPLoss(offset: TimeInterval($0)) }
        let collector = SequenceCollector([baseline] + candidates)
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        let recorder = LinkEventRecorder()
        let stream = await center.events()
        let eventTask = Task { for await event in stream { await recorder.append(event) } }

        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await collector.waitForCaptureCount(3)
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)
        for _ in 0..<38 { await center.refresh() }

        let snapshot = await center.snapshot()
        #expect(snapshot.state == .unknown)
        #expect(snapshot.reason == .disconnectEvidenceNotValidated)
        #expect(snapshot.linkEpoch == 0)
        #expect(await collector.captureCount() == 41)
        #expect(await clock.pendingCount() == 0)

        await center.stop()
        await recorder.waitForCount(1)
        eventTask.cancel()
        await eventTask.value
        #expect(await recorder.events().map(\.type) == [.continuityReset])
    }

    @Test("A failed review sample invalidates the candidate cycle without link transitions")
    func failedReviewSampleResetsCandidateCycle() async {
        let collector = SequenceCollector([
            evidence(mode: .station, radio: .reportedOn, linkActive: true),
            observedAPLoss(offset: 1),
            nil
        ])
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        let recorder = LinkEventRecorder()
        let stream = await center.events()
        let eventTask = Task { for await event in stream { await recorder.append(event) } }

        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await collector.waitForCaptureCount(3)
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)

        #expect((await center.snapshot()).state == .unknown)
        #expect((await center.snapshot()).reason == .interfaceDiscoveryUnavailable)
        await clock.waitUntilNoPendingSleep()
        #expect(await clock.pendingCount() == 0)
        await center.stop()
        await recorder.waitForCount(2)
        eventTask.cancel()
        await eventTask.value
        #expect(await recorder.events().map(\.type) == [.continuityReset, .continuityReset])
    }

    @Test("Sleep invalidates the active candidate review and produces no link transition")
    func sleepDuringReviewResetsWithoutTransitions() async {
        let trigger = FakeLinkTrigger()
        let collector = SequenceCollector([
            evidence(mode: .station, radio: .reportedOn, linkActive: true),
            observedAPLoss(offset: 1),
            nil
        ])
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: trigger,
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        let recorder = LinkEventRecorder()
        let stream = await center.events()
        let eventTask = Task { for await event in stream { await recorder.append(event) } }

        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        let sequenceBeforeSleep = (await center.snapshot()).sequence
        trigger.emit(.willSleep)
        await collector.waitForCaptureCount(3)
        await waitForSnapshotReason(center, .interfaceDiscoveryUnavailable, after: sequenceBeforeSleep)

        #expect((await center.snapshot()).state == .unknown)
        await clock.waitUntilNoPendingSleep()
        #expect(await clock.pendingCount() == 0)
        await center.stop()
        await recorder.waitForCount(3)
        eventTask.cancel()
        await eventTask.value
        #expect(await recorder.events().allSatisfy { $0.type == .continuityReset })
    }

    @Test("A first observation of an unassociated interface does not emit disconnect or recovery")
    func initialUnassociatedStateDoesNotEmitTransitions() async {
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([observedAPLoss(offset: 1), observedAPLoss(offset: 2)]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600), reviewClock: clock,
            allowsUnvalidatedDisconnectConfirmation: true
        )
        let recorder = LinkEventRecorder()
        let stream = await center.events()
        let eventTask = Task { for await event in stream { await recorder.append(event) } }

        await center.start()
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)

        #expect((await center.snapshot()).state == .disconnected)
        #expect((await center.snapshot()).linkEpoch == 0)
        await center.stop()
        await recorder.waitForCount(1)
        eventTask.cancel()
        await eventTask.value
        #expect(await recorder.events().map(\.type) == [.continuityReset])
    }

    @Test("The scan compatibility subscriber moves from powered-on to unknown on ambiguous radio evidence")
    func powerMonitorDoesNotRetainOldPowerState() async {
        let on = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let ambiguousOff = evidence(
            mode: .station, radio: .reportedOffOrReadFailure, linkActive: false,
            radioPowerOnRaw: false, offset: 1
        )
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([on, ambiguousOff]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600)
        )
        let monitor = WiFiPowerMonitor(center: center)
        monitor.startMonitoring()
        await waitForMonitorState(monitor, .poweredOn)

        monitor.refreshState()
        await waitForMonitorState(monitor, .unknown)

        #expect(monitor.currentState == .unknown)
        monitor.stopMonitoring()
        await center.stop()
    }

    @Test("Repeated notifications do not create parallel candidate review tasks")
    func notificationsShareOneCandidateReview() async {
        let trigger = FakeLinkTrigger()
        let clock = ManualReviewClock()
        let collector = SequenceCollector([
            evidence(mode: .station, radio: .reportedOn, linkActive: true),
            observedAPLoss(offset: 1), observedAPLoss(offset: 2),
            observedAPLoss(offset: 3), observedAPLoss(offset: 4), observedAPLoss(offset: 5)
        ])
        let center = WiFiLinkStateCenter(
            collector: collector,
            trigger: trigger,
            pollingInterval: .seconds(3_600),
            reviewClock: clock
        )
        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()

        for _ in 0..<4 { trigger.emit(.systemConfiguration) }
        await collector.waitForCaptureCount(3)

        #expect(await clock.pendingCount() == 1)
        await center.stop()
    }

    @Test("An association found before the scheduled review cancels that review")
    func associationCancelsScheduledReview() async {
        let clock = ManualReviewClock()
        let collector = SequenceCollector([
            evidence(mode: .station, radio: .reportedOn, linkActive: true),
            observedAPLoss(offset: 1),
            evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 2)
        ])
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        await center.refresh()

        #expect((await center.snapshot()).state == .associated)
        await clock.waitUntilNoPendingSleep()
        #expect(await collector.captureCount() == 3)
        await center.stop()
    }

    @Test("An interface change during active review establishes a fresh baseline")
    func interfaceChangeDuringReviewInvalidatesOldEvidence() async {
        let clock = ManualReviewClock()
        let collector = SequenceCollector([
            evidence(mode: .station, radio: .reportedOn, linkActive: true),
            observedAPLoss(offset: 1),
            evidence(mode: .station, radio: .reportedOn, linkActive: true, interfaceName: "en1", offset: 2)
        ])
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        await clock.releaseNext()
        await collector.waitForCaptureCount(3)

        let snapshot = await center.snapshot()
        #expect(snapshot.state == .associated)
        #expect(snapshot.interfaceName == "en1")
        #expect(snapshot.linkEpoch > 0)
        await center.stop()
    }

    @Test("Stopping while a candidate review capture is suspended discards its result")
    func stopDuringSuspendedReviewDiscardsResult() async {
        let collector = PausingCollector()
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), reviewClock: clock
        )
        let startTask = Task { await center.start() }
        await collector.waitForPendingCount(1)
        await collector.resolve(await collector.pendingIDs()[0], with: evidence(mode: .station, radio: .reportedOn, linkActive: true))
        await startTask.value

        let candidateTask = Task { await center.refresh() }
        await collector.waitForPendingCount(2)
        await collector.resolve(await collector.pendingIDs()[1], with: observedAPLoss(offset: 1))
        await candidateTask.value
        await clock.waitForPendingSleep()
        await clock.releaseNext()
        await collector.waitForPendingCount(3)
        let reviewRequest = await collector.pendingIDs()[2]
        let oldSessionID = await center.snapshot().runSessionID

        await center.stop()
        await collector.resolve(reviewRequest, with: observedAPLoss(offset: 2))
        for _ in 0..<10 { await Task.yield() }

        #expect((await center.snapshot()).runSessionID == oldSessionID)
        #expect((await center.snapshot()).state == .unknown)
    }

    @Test("A suspended startup sample cannot publish after stop or overwrite a restarted session")
    func suspendedCaptureIsDiscardedAcrossStopAndRestart() async {
        let collector = PausingCollector()
        let trigger = FakeLinkTrigger()
        let center = WiFiLinkStateCenter(
            collector: collector, trigger: trigger, pollingInterval: .seconds(3_600)
        )
        let firstStart = Task { await center.start() }
        await collector.waitForPendingCount(1)
        let firstRequest = await collector.pendingIDs()[0]

        await center.stop()
        let secondStart = Task { await center.start() }
        await collector.waitForPendingCount(2)
        let secondRequest = await collector.pendingIDs()[1]
        let newSessionID = await center.snapshot().runSessionID

        await collector.resolve(firstRequest, with: evidence(mode: .station, radio: .reportedOn, linkActive: true))
        await firstStart.value
        #expect((await center.snapshot()).runSessionID == newSessionID)
        #expect((await center.snapshot()).state == .unknown)

        await collector.resolve(secondRequest, with: evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 1))
        await secondStart.value
        #expect((await center.snapshot()).runSessionID == newSessionID)
        #expect((await center.snapshot()).state == .associated)
        #expect(trigger.startCount == 1)
        await center.stop()
    }

    @Test("A callback retained by a stopped trigger cannot request another sample")
    func staleTriggerCallbackIsIgnoredAfterStop() async {
        let collector = SequenceCollector([evidence(mode: .station, radio: .reportedOn, linkActive: true)])
        let trigger = FakeLinkTrigger()
        let center = WiFiLinkStateCenter(collector: collector, trigger: trigger, pollingInterval: .seconds(3_600))
        await center.start()
        let callback = trigger.savedHandler
        await center.stop()
        let countAfterStop = await collector.captureCount()

        callback?(.systemConfiguration)
        await Task.yield()
        await Task.yield()

        #expect(await collector.captureCount() == countAfterStop)
    }

    @Test("A BSSID change is emitted when both observations share a trusted SSID")
    func bssidChangeWithStableSSIDIsReported() async {
        let first = evidence(mode: .station, radio: .reportedOn, linkActive: true, ssid: "Lab", bssid: "00:00:00:00:00:01")
        let second = evidence(mode: .station, radio: .reportedOn, linkActive: true, ssid: "Lab", bssid: "00:00:00:00:00:02", offset: 1)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([first, second]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600)
        )
        let stream = await center.events()
        var iterator = stream.makeAsyncIterator()

        await center.start()
        await center.refresh()

        #expect(await iterator.next()?.type == .networkIdentityChanged)
        await center.stop()
    }

    @Test("Default production policy does not promote unvalidated disconnect evidence")
    func defaultDisconnectPolicyStaysUnknown() async {
        let first = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let second = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 2)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([first, second]), trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600)
        )
        await center.start()
        await center.refresh()
        let state = await center.snapshot()
        #expect(state.state == .unknown)
        #expect(state.reason == .disconnectEvidenceNotValidated)
        await center.stop()
    }

    @Test("Strict test policy emits one disconnect and one recovery from anonymized real evidence")
    func strictTransitionsAndLinkEpoch() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate1 = observedAPLoss(offset: 1)
        let candidate2 = observedAPLoss(offset: 2)
        let candidate3 = observedAPLoss(offset: 3)
        let recovered = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 4)
        let stillAssociated = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 5)
        let clock = ManualReviewClock()
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([baseline, candidate1, candidate2, candidate3, recovered, stillAssociated]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600), reviewClock: clock,
            allowsUnvalidatedDisconnectConfirmation: true
        )
        let recorder = LinkEventRecorder()
        let events = await center.events()
        let eventTask = Task { for await event in events { await recorder.append(event) } }
        await center.start()
        await center.refresh()
        await clock.waitForPendingSleep()
        let sequenceBeforeReview = (await center.snapshot()).sequence
        await clock.releaseNext()
        await waitForSnapshotSequence(center, after: sequenceBeforeReview)
        let disconnected = await center.snapshot()
        #expect(disconnected.state == .disconnected)
        #expect(disconnected.linkEpoch == 1)
        await center.refresh()
        #expect((await center.snapshot()).state == .disconnected)
        await center.refresh()
        let associated = await center.snapshot()
        #expect(associated.state == .associated)
        #expect(associated.linkEpoch == 2)
        await center.refresh()
        await center.stop()
        await recorder.waitForCount(3)
        eventTask.cancel()
        await eventTask.value
        let recordedEvents = await recorder.events()
        let transitions = recordedEvents.filter { $0.type == .disconnected || $0.type == .associated }
        #expect(transitions.count == 2)
        let disconnectEvent = transitions[0]
        let recoveryEvent = transitions[1]
        #expect(disconnectEvent.type == .disconnected)
        #expect(recoveryEvent.type == .associated)
        #expect(disconnectEvent.id != recoveryEvent.id)
        #expect(disconnectEvent.linkEpoch == 1)
        #expect(recoveryEvent.linkEpoch == 2)
        #expect(disconnectEvent.lastConfirmedPreviousAt == baseline.capturedAt)
        #expect(disconnectEvent.firstConfirmedCurrentAt == candidate1.capturedAt)
        #expect(disconnectEvent.confirmedAt != candidate1.capturedAt)
        #expect(disconnectEvent.currentEvidence?.ssid == nil)
        #expect(disconnectEvent.currentEvidence?.bssid == nil)
        #expect(recoveryEvent.firstConfirmedCurrentAt == recovered.capturedAt)
        #expect(recordedEvents.last?.type == .continuityReset)
    }

    @Test("Current-state subscribers are independent, cancellation is local, and event history remains ordered")
    func independentSubscribers() async {
        let first = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let second = evidence(mode: .station, radio: .reportedOn, linkActive: true, ssid: "Office", bssid: "02:00:00:00:00:02", offset: 1)
        let center = WiFiLinkStateCenter(collector: SequenceCollector([first, second]), trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600))
        let streamA = await center.currentStates()
        let streamB = await center.currentStates()
        var a = streamA.makeAsyncIterator()
        var b = streamB.makeAsyncIterator()
        await center.start()
        _ = await a.next()
        _ = await b.next()
        await center.refresh()
        let latestA = await a.next()
        let latestB = await b.next()
        #expect(latestA?.sequence == latestB?.sequence)
        #expect(latestB?.networkIdentity?.ssid == "Office")
        await center.stop()
    }

    @Test("Interface change and app resume reset continuity without synthesizing disconnect")
    func continuityResets() async {
        let initial = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let changed = evidence(mode: .station, radio: .reportedOn, linkActive: true, interfaceName: "en1", offset: 1)
        let resumed = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 2)
        let center = WiFiLinkStateCenter(collector: SequenceCollector([initial, changed, resumed]), trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600))
        let events = await center.events()
        var iterator = events.makeAsyncIterator()
        await center.start()
        await center.refresh()
        #expect((await iterator.next())?.type == .continuityReset)
        #expect((await center.snapshot()).state == .associated)
        await center.applicationBecameActive()
        #expect((await iterator.next())?.type == .continuityReset)
        await center.stop()
    }

    @Test("Repeated start and stop are idempotent and injected trigger can report registration failure")
    func lifecycleIsIdempotent() async {
        let trigger = FakeLinkTrigger(systemConfigurationRegistered: false, coreWLANRegistrationError: "denied")
        let center = WiFiLinkStateCenter(collector: SequenceCollector([evidence(mode: .station, radio: .reportedOn, linkActive: true)]), trigger: trigger, pollingInterval: .seconds(3_600))
        await center.start()
        await center.start()
        let listenerStatus = await center.listenerStatus()
        await center.stop()
        await center.stop()
        #expect(trigger.startCount == 1)
        #expect(trigger.stopCount == 1)
        #expect(listenerStatus.isRunning)
        #expect(!listenerStatus.systemConfigurationRegistered)
        #expect(!listenerStatus.coreWLANRegistered)
        #expect(listenerStatus.coreWLANRegistrationError == "denied")
    }

    @Test("A system-backed center in the unit-test host does not start system listeners")
    func testHostDoesNotStartRealMonitoring() async {
        let trigger = FakeLinkTrigger()
        let center = WiFiLinkStateCenter(
            collector: SystemWiFiLinkEvidenceCollector(), trigger: trigger, pollingInterval: .seconds(3_600)
        )
        await center.start()
        #expect(trigger.startCount == 0)
        #expect((await center.snapshot()).state == .unknown)
        await center.stop()
    }

    @Test("Candidate review rejects reused IDs and time that moves backwards")
    func invalidCandidateSequenceDoesNotDisconnect() async {
        let id = UUID()
        let first = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 2, cycleID: id)
        let repeated = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 3, cycleID: id)
        let backwards = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([first, repeated, backwards]), trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), allowsUnvalidatedDisconnectConfirmation: true
        )
        await center.start()
        await center.refresh()
        await center.refresh()
        #expect((await center.snapshot()).state == .unknown)
        await center.stop()
    }

    @Test("Candidate review rejects sampling times that move backwards")
    func backwardsCandidateTimeDoesNotDisconnect() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let later = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 2)
        let earlier = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([baseline, later, earlier]), trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), allowsUnvalidatedDisconnectConfirmation: true
        )
        await center.start()
        await center.refresh()
        await center.refresh()
        #expect((await center.snapshot()).state == .unknown)
        await center.stop()
    }

    @Test("A trusted association during candidate review cancels the pending disconnect")
    func associationCancelsDisconnectReview() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let recovered = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 2)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([baseline, candidate, recovered]), trigger: FakeLinkTrigger(),
            pollingInterval: .seconds(3_600), allowsUnvalidatedDisconnectConfirmation: true
        )
        await center.start()
        await center.refresh()
        await center.refresh()
        #expect((await center.snapshot()).state == .associated)
        #expect((await center.snapshot()).linkEpoch == 0)
        await center.stop()
    }

    @Test("A continuity gap prevents duplicate disconnect and synthetic recovery events")
    func continuityGapDoesNotRepeatTransitions() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate1 = evidence(mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let candidate2 = evidence(mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 2)
        let unknown = evidence(mode: .station, radio: .reportedOn, linkActive: nil, offset: 3)
        let candidate3 = evidence(mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 4)
        let candidate4 = evidence(mode: .noneOrReadFailure, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 5)
        let associated = evidence(mode: .station, radio: .reportedOn, linkActive: true, offset: 6)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([baseline, candidate1, candidate2, unknown, candidate3, candidate4, associated]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600),
            allowsUnvalidatedDisconnectConfirmation: true
        )
        let stream = await center.events()
        var iterator = stream.makeAsyncIterator()
        await center.start()
        for _ in 0..<6 { await center.refresh() }
        #expect((await center.snapshot()).state == .associated)
        await center.stop()
        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        #expect(first?.type == .disconnected)
        #expect(second?.type == .continuityReset)
        #expect(third?.type == .continuityReset)
    }
}

private actor SequenceCollector: WiFiLinkEvidenceCollecting {
    private var samples: [WiFiLinkRawEvidence?]
    private var count = 0

    init(_ samples: [WiFiLinkRawEvidence?]) { self.samples = samples }

    func capture() async -> WiFiLinkRawEvidence? {
        count += 1
        guard !samples.isEmpty else { return nil }
        return samples.removeFirst()
    }

    func captureCount() -> Int { count }

    func waitForCaptureCount(_ expected: Int) async {
        for _ in 0..<1_000 {
            if count >= expected { return }
            await Task.yield()
        }
    }
}

private actor LinkEventRecorder {
    private var recordedEvents: [WiFiLinkStateEvent] = []

    func append(_ event: WiFiLinkStateEvent) {
        recordedEvents.append(event)
    }

    func events() -> [WiFiLinkStateEvent] { recordedEvents }

    func waitForCount(_ expected: Int) async {
        for _ in 0..<1_000 {
            if recordedEvents.count >= expected { return }
            await Task.yield()
        }
    }
}

private actor PausingCollector: WiFiLinkEvidenceCollecting {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<WiFiLinkRawEvidence?, Never>] = [:]
    private var pendingIDsValue: [Int] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func capture() async -> WiFiLinkRawEvidence? {
        await withCheckedContinuation { continuation in
            nextID += 1
            continuations[nextID] = continuation
            pendingIDsValue.append(nextID)
            resumeWaitersIfReady()
        }
    }

    func pendingIDs() -> [Int] { pendingIDsValue }

    func waitForPendingCount(_ expected: Int) async {
        if pendingIDsValue.count >= expected { return }
        await withCheckedContinuation { waiters.append((expected, $0)) }
    }

    func resolve(_ id: Int, with value: WiFiLinkRawEvidence?) {
        continuations.removeValue(forKey: id)?.resume(returning: value)
    }

    private func resumeWaitersIfReady() {
        let ready = waiters.filter { pendingIDsValue.count >= $0.0 }
        waiters.removeAll { pendingIDsValue.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}

private actor ManualReviewClock: WiFiLinkReviewClock {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var pendingIDsValue: [Int] = []
    private var pendingWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = 0

    func sleep(for duration: Duration) async throws {
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[id] = continuation
                pendingIDsValue.append(id)
                let waiters = pendingWaiters
                pendingWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func waitForPendingSleep() async {
        if !pendingIDsValue.isEmpty { return }
        await withCheckedContinuation { pendingWaiters.append($0) }
    }

    func pendingCount() -> Int { pendingIDsValue.count }

    func waitUntilNoPendingSleep() async {
        for _ in 0..<1_000 {
            if pendingIDsValue.isEmpty { return }
            await Task.yield()
        }
    }

    func releaseNext() {
        guard let id = pendingIDsValue.first else { return }
        pendingIDsValue.removeFirst()
        continuations.removeValue(forKey: id)?.resume()
        released += 1
    }

    func releasedCount() -> Int { released }

    private func cancel(_ id: Int) {
        pendingIDsValue.removeAll { $0 == id }
        continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class FakeLinkTrigger: WiFiLinkChangeTriggering {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let systemConfigurationRegistered: Bool
    let coreWLANRegistered: Bool
    let coreWLANRegistrationError: String?
    private(set) var savedHandler: (@Sendable (WiFiLinkChangeReason) -> Void)?

    init(systemConfigurationRegistered: Bool = false, coreWLANRegistered: Bool = false, coreWLANRegistrationError: String? = nil) {
        self.systemConfigurationRegistered = systemConfigurationRegistered
        self.coreWLANRegistered = coreWLANRegistered
        self.coreWLANRegistrationError = coreWLANRegistrationError
    }

    func start(interfaceName: String?, handler: @escaping @Sendable (WiFiLinkChangeReason) -> Void) {
        startCount += 1
        savedHandler = handler
    }
    func emit(_ reason: WiFiLinkChangeReason) { savedHandler?(reason) }
    func updateInterface(_ name: String?) {}
    func stop() { stopCount += 1 }
}

private func evidence(
    mode: WiFiModeEvidence,
    radio: WiFiRadioEvidence,
    linkActive: Bool?,
    serviceActive: Bool? = nil,
    ssid: String? = nil,
    bssid: String? = nil,
    modeRawValue: Int? = nil,
    radioPowerOnRaw: Bool? = nil,
    interfaceFlagsUp: Bool? = true,
    interfaceFlagsRunning: Bool? = nil,
    interfaceName: String = "en0",
    offset: TimeInterval = 0,
    cycleID: UUID = UUID()
) -> WiFiLinkRawEvidence {
    let capturedAt = Date(timeIntervalSince1970: 1_800_000_000 + offset)
    return WiFiLinkRawEvidence(
        snapshotCycleID: cycleID, capturedAt: capturedAt, interfaceName: interfaceName,
        mode: mode, coreWLANModeRawValue: modeRawValue, radio: radio, linkActive: linkActive, ssid: ssid, bssid: bssid,
        interfaceIndex: interfaceName == "en0" ? 4 : 5,
        radioPowerOnRaw: radioPowerOnRaw,
        serviceActive: serviceActive, interfaceFlagsUp: interfaceFlagsUp,
        interfaceFlagsRunning: interfaceFlagsRunning ?? linkActive,
        captureStartedAt: capturedAt, captureEndedAt: capturedAt.addingTimeInterval(0.1)
    )
}

private func observedAPLoss(offset: TimeInterval) -> WiFiLinkRawEvidence {
    evidence(
        mode: .noneOrReadFailure,
        radio: .reportedOn,
        linkActive: false,
        serviceActive: true,
        modeRawValue: 0,
        radioPowerOnRaw: true,
        interfaceFlagsUp: true,
        interfaceFlagsRunning: true,
        offset: offset
    )
}

@MainActor
private func waitForMonitorState(_ monitor: WiFiPowerMonitor, _ expected: WiFiPowerState) async {
    for _ in 0..<1_000 {
        if monitor.currentState == expected { return }
        await Task.yield()
    }
}

@MainActor
private func waitForSnapshotSequence(_ center: WiFiLinkStateCenter, after sequence: UInt64) async {
    for _ in 0..<1_000 {
        if await center.snapshot().sequence > sequence { return }
        await Task.yield()
    }
}

@MainActor
private func waitForSnapshotReason(
    _ center: WiFiLinkStateCenter,
    _ reason: WiFiLinkEvidenceReason,
    after sequence: UInt64
) async {
    for _ in 0..<1_000 {
        let snapshot = await center.snapshot()
        if snapshot.sequence > sequence, snapshot.reason == reason { return }
        await Task.yield()
    }
}
