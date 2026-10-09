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
        let sample = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false)
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

    @Test("Strict review requires distinct samples and emits one disconnect and one recovery")
    func strictTransitionsAndLinkEpoch() async {
        let baseline = evidence(mode: .station, radio: .reportedOn, linkActive: true)
        let candidate1 = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 1)
        let candidate2 = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 2)
        let candidate3 = evidence(mode: .none, radio: .reportedOn, linkActive: false, serviceActive: false, offset: 3)
        let recovered = evidence(mode: .station, radio: .reportedOn, linkActive: true, ssid: "New", bssid: "02:00:00:00:00:01", offset: 4)
        let center = WiFiLinkStateCenter(
            collector: SequenceCollector([baseline, candidate1, candidate2, candidate3, recovered]),
            trigger: FakeLinkTrigger(), pollingInterval: .seconds(3_600),
            allowsUnvalidatedDisconnectConfirmation: true
        )
        let events = await center.events()
        var iterator = events.makeAsyncIterator()
        await center.start()
        await center.refresh()
        await center.refresh()
        let disconnected = await center.snapshot()
        #expect(disconnected.state == .disconnected)
        #expect(disconnected.linkEpoch == 1)
        await center.refresh()
        #expect((await center.snapshot()).state == .disconnected)
        await center.refresh()
        let associated = await center.snapshot()
        #expect(associated.state == .associated)
        #expect(associated.linkEpoch == 2)
        let disconnectEvent = await iterator.next()
        let recoveryEvent = await iterator.next()
        #expect(disconnectEvent?.type == .disconnected)
        #expect(disconnectEvent?.id != nil)
        #expect(recoveryEvent?.type == .associated)
        #expect((disconnectEvent?.sequence ?? 0) < (recoveryEvent?.sequence ?? 0))
        await center.stop()
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

    init(_ samples: [WiFiLinkRawEvidence?]) { self.samples = samples }

    func capture() async -> WiFiLinkRawEvidence? {
        guard !samples.isEmpty else { return nil }
        return samples.removeFirst()
    }
}

@MainActor
private final class FakeLinkTrigger: WiFiLinkChangeTriggering {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    let systemConfigurationRegistered: Bool
    let coreWLANRegistered: Bool
    let coreWLANRegistrationError: String?

    init(systemConfigurationRegistered: Bool = false, coreWLANRegistered: Bool = false, coreWLANRegistrationError: String? = nil) {
        self.systemConfigurationRegistered = systemConfigurationRegistered
        self.coreWLANRegistered = coreWLANRegistered
        self.coreWLANRegistrationError = coreWLANRegistrationError
    }

    func start(interfaceName: String?, handler: @escaping @Sendable (WiFiLinkChangeReason) -> Void) { startCount += 1 }
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
    interfaceName: String = "en0",
    offset: TimeInterval = 0,
    cycleID: UUID = UUID()
) -> WiFiLinkRawEvidence {
    let capturedAt = Date(timeIntervalSince1970: 1_800_000_000 + offset)
    return WiFiLinkRawEvidence(
        snapshotCycleID: cycleID, capturedAt: capturedAt, interfaceName: interfaceName,
        mode: mode, radio: radio, linkActive: linkActive, ssid: ssid, bssid: bssid,
        interfaceIndex: interfaceName == "en0" ? 4 : 5,
        serviceActive: serviceActive, interfaceFlagsUp: true, interfaceFlagsRunning: linkActive,
        captureStartedAt: capturedAt, captureEndedAt: capturedAt.addingTimeInterval(0.1)
    )
}
