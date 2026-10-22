import Foundation
import Testing

@testable import WiFiLensCore

@Suite("Gateway evidence sampling")
struct WiFiGatewayEvidenceSamplingTests {
    @Test("A bound reply on an unchanged interface is attributed with valid latency")
    func attributedReply() async {
        let sampler = makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 23)
        )

        let sample = await sampler.sample()

        #expect(sample.attribution == .attributed)
        #expect(sample.latencyValidity == .valid)
        #expect(sample.latencyMilliseconds == 23)
        #expect(sample.reportedLatencyMilliseconds == 23)
        #expect(sample.outcome == .replied(milliseconds: 23))
        #expect(sample.interfaceBound)
        #expect(sample.attemptID != nil)
        #expect(sample.rejectionReason == nil)
        #expect(sample.before.snapshotCycleID != sample.after?.snapshotCycleID)
    }

    @Test("A bound no-reply attempt is attributed but has no latency")
    func attributedNoReply() async {
        let sampler = makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .noReply
        )

        let sample = await sampler.sample()

        #expect(sample.attribution == .attributed)
        #expect(sample.latencyValidity == .notApplicable)
        #expect(sample.latencyMilliseconds == nil)
        #expect(sample.outcome == .noReply)
        #expect(sample.rejectionReason == nil)
    }

    @Test("Execution failure and local timeout remain distinct attributed attempts")
    func attributedFailuresRemainDistinct() async {
        let execution = await makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .executionFailed
        ).sample()
        let timeout = await makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .localTimeout
        ).sample()

        #expect(execution.attribution == .attributed)
        #expect(execution.outcome == .executionFailed)
        #expect(timeout.attribution == .attributed)
        #expect(timeout.outcome == .localTimeout)
        #expect(execution.latencyMilliseconds == nil)
        #expect(timeout.latencyMilliseconds == nil)
    }

    @Test("An interface change during the probe invalidates attribution")
    func interfaceChanged() async {
        var after = SnapshotVariant.associated
        after.interfaceName = "en1"
        after.interfaceIndex = 5
        let sampler = makeSampler(
            variants: [.associated, after],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        )

        let sample = await sampler.sample()

        #expect(sample.attribution == .interfaceChanged)
        #expect(sample.rejectionReason == .interfaceChanged)
        #expect(sample.latencyValidity == .notApplicable)
        #expect(sample.latencyMilliseconds == nil)
    }

    @Test("A router or network identity change invalidates attribution")
    func targetChanged() async {
        var after = SnapshotVariant.associated
        after.router = "192.0.2.254"
        let routerChange = await makeSampler(
            variants: [.associated, after],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        var roaming = SnapshotVariant.associated
        roaming.bssid = "aa:bb:cc:dd:ee:01"
        let roamingChange = await makeSampler(
            variants: [.associated, roaming],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(routerChange.attribution == .targetChanged)
        #expect(routerChange.rejectionReason == .networkIdentityChanged)
        #expect(roamingChange.attribution == .targetChanged)
        #expect(roamingChange.rejectionReason == .networkIdentityChanged)
    }

    @Test("BSSID comparison is case-insensitive")
    func bssidComparisonIsCaseInsensitive() async {
        var after = SnapshotVariant.associated
        after.bssid = "aa:bb:cc:dd:ee:ff"
        let sample = await makeSampler(
            variants: [.associated, after],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .attributed)
    }

    @Test("A link epoch change during the probe invalidates attribution")
    func linkEpochChanged() async {
        let sample = await makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 8)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkEpochChanged)
        #expect(sample.rejectionReason == .linkEpochChanged)
    }

    @Test("Losing association during the probe invalidates attribution")
    func linkLostDuringAttempt() async {
        var after = SnapshotVariant.associated
        after.linkActive = false
        let sample = await makeSampler(
            variants: [.associated, after],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkLostDuringAttempt)
        #expect(sample.rejectionReason == .linkLostDuringAttempt)
    }

    @Test("No probe is attempted when the link is not associated")
    func linkNotAssociated() async {
        var before = SnapshotVariant.associated
        before.linkActive = false
        let sample = await makeSampler(
            variants: [before, .associated],
            links: [.disconnected(), .disconnected()],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkNotAssociated)
        #expect(sample.rejectionReason == .linkNotAssociated)
        #expect(sample.outcome == nil)
        #expect(sample.attemptID == nil)
        #expect(sample.after == nil)
    }

    @Test("No probe is attempted when no gateway target is available")
    func missingGatewayTarget() async {
        var before = SnapshotVariant.associated
        before.router = nil
        let sample = await makeSampler(
            variants: [before, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .targetUnavailable)
        #expect(sample.rejectionReason == .missingGatewayTarget)
        #expect(sample.outcome == nil)
    }

    @Test("A failed interface enumeration is reported as an unavailable snapshot")
    func snapshotUnavailable() async {
        var before = SnapshotVariant.associated
        before.enumerationSucceeded = false
        let sample = await makeSampler(
            variants: [before, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .targetUnavailable)
        #expect(sample.rejectionReason == .snapshotUnavailable)
        #expect(sample.outcome == nil)
    }

    @Test("A stale link snapshot keeps the probe result but drops attribution")
    func staleLinkEvidenceBeforeProbe() async {
        let sample = await makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7, age: 20), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkEvidenceStale)
        #expect(sample.rejectionReason == .linkEvidenceStale)
        #expect(sample.outcome == .replied(milliseconds: 12))
        #expect(sample.attemptID != nil)
        #expect(sample.reportedLatencyMilliseconds == 12)
        #expect(sample.latencyValidity == .notApplicable)
        #expect(sample.latencyMilliseconds == nil)
    }

    @Test("A fresh unassociated snapshot does not masquerade as stale evidence")
    func unassociatedLinkSnapshot() async {
        let sample = await makeSampler(
            variants: [.associated, .associated],
            links: [.disconnected(), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkEvidenceUnavailable)
        #expect(sample.rejectionReason == .linkSnapshotNotAssociated)
        #expect(sample.outcome == .replied(milliseconds: 12))
        #expect(sample.latencyMilliseconds == nil)
    }

    @Test("A failed after-probe enumeration is not reported as a target failure")
    func afterCaptureUnavailable() async {
        var after = SnapshotVariant.associated
        after.enumerationSucceeded = false
        let sample = await makeSampler(
            variants: [.associated, after],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .captureUnavailable)
        #expect(sample.rejectionReason == .snapshotUnavailable)
        #expect(sample.outcome == .replied(milliseconds: 12))
    }

    @Test("A stale confirmation snapshot keeps the probe result but drops attribution")
    func staleLinkEvidenceAfterProbe() async {
        let sample = await makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7, age: 20)],
            result: .replied(milliseconds: 12)
        ).sample()

        #expect(sample.attribution == .linkEvidenceStale)
        #expect(sample.rejectionReason == .linkEvidenceStale)
        #expect(sample.outcome == .replied(milliseconds: 12))
        #expect(sample.latencyValidity == .notApplicable)
        #expect(sample.latencyMilliseconds == nil)
        #expect(sample.reportedLatencyMilliseconds == 12)
    }

    @Test("A result without the target identity is not attributed")
    func resultUnattributed() async {
        let sampler = makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12),
            interfaceBound: false
        )

        let sample = await sampler.sample()

        #expect(sample.attribution == .resultUnattributed)
        #expect(sample.rejectionReason == .resultUnattributed)
        #expect(sample.latencyValidity == .notApplicable)
    }

    @Test("A replied result with inconsistent latency is attributed but invalid")
    func invalidLatency() async {
        let sampler = makeSampler(
            variants: [.associated, .associated],
            links: [.associated(epoch: 7), .associated(epoch: 7)],
            result: .replied(milliseconds: 12),
            reportedLatencyOverride: 18
        )

        let sample = await sampler.sample()

        #expect(sample.attribution == .attributed)
        #expect(sample.latencyValidity == .invalid)
        #expect(sample.latencyMilliseconds == nil)
        #expect(sample.reportedLatencyMilliseconds == 18)
        #expect(sample.rejectionReason == .invalidLatency)
    }

    @Test("The caller-owned cycle is preserved and the status-only seam never reads the link center")
    func callerOwnedCycleAndNoLinkCenterRead() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_500)
        let snapshot = Self.snapshot(from: .associated, cycleID: cycleID, capturedAt: capturedAt)
        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
        let linkReads = CallCounter()
        let sampler = SystemWiFiGatewayEvidenceSampler(
            linkSnapshot: {
                await linkReads.increment()
                return Self.linkSnapshot()
            },
            captureSnapshot: { cycleID, capturedAt in
                Self.snapshot(from: .associated, cycleID: cycleID, capturedAt: capturedAt)
            },
            currentStatus: { snapshot in
                await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
            },
            measure: { target in
                GatewayLatencyResult(
                    timestamp: target.capturedAt.addingTimeInterval(0.01),
                    routerIP: target.address,
                    latencyMs: 23,
                    probeOutcome: .replied(milliseconds: 23),
                    attemptID: UUID(),
                    cycleID: target.snapshotCycleID,
                    interfaceName: target.interfaceName,
                    interfaceBound: true
                )
            }
        )

        let sample = await sampler.sample(
            before: WiFiGatewayEvidenceBefore(
                cycleID: cycleID,
                snapshot: snapshot,
                status: status,
                linkSnapshot: nil,
                linkFetchedAt: nil,
                startedAt: capturedAt
            )
        )

        #expect(sample.before.snapshotCycleID == cycleID)
        #expect(sample.before.linkRunSessionID == nil)
        #expect(sample.before.linkEpoch == nil)
        #expect(sample.attribution == .attributed)
        #expect(sample.latencyMilliseconds == 23)
        #expect(sample.beforeLinkEvidenceFresh == nil)
        #expect(sample.afterLinkEvidenceFresh == nil)
        #expect(await linkReads.count() == 0)
    }

    @Test("The legacy mapping keeps attributed outcomes and rejects the rest")
    func legacyMapping() async {
        let replied = await mappedSample(result: .replied(milliseconds: 23))
        #expect(replied.probeOutcome == .replied(milliseconds: 23))
        #expect(replied.latencyMs == 23)
        #expect(replied.interfaceBound)

        let noReply = await mappedSample(result: .noReply)
        #expect(noReply.probeOutcome == .noReply)
        #expect(noReply.latencyMs == nil)
        #expect(noReply.error == .gatewayPingFailed("192.0.2.1"))

        let failed = await mappedSample(result: .executionFailed)
        #expect(failed.probeOutcome == .executionFailed)
        #expect(failed.error == .gatewayPingFailed("192.0.2.1"))

        let invalid = await mappedSample(
            result: .replied(milliseconds: 12),
            reportedLatencyOverride: 18
        )
        #expect(invalid.probeOutcome == .notTested)
        #expect(invalid.attemptID == nil)
        #expect(invalid.interfaceBound == false)

        var after = SnapshotVariant.associated
        after.interfaceName = "en1"
        after.interfaceIndex = 5
        let rejected = await mappedSample(result: .noReply, after: after)
        #expect(rejected.probeOutcome == .notTested)
        #expect(rejected.attemptID == nil)
        #expect(rejected.interfaceBound == false)
    }

    @Test("Cancellation returns a cancelled sample without an after capture")
    func cancellation() async {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_700)
        let snapshot = Self.snapshot(from: .associated, cycleID: cycleID, capturedAt: capturedAt)
        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
        let sampler = SystemWiFiGatewayEvidenceSampler(
            linkSnapshot: { Self.linkSnapshot() },
            captureSnapshot: { cycleID, capturedAt in
                Self.snapshot(from: .associated, cycleID: cycleID, capturedAt: capturedAt)
            },
            currentStatus: { snapshot in
                await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
            },
            measure: { target in
                try? await Task.sleep(for: .seconds(5))
                return GatewayLatencyResult(
                    timestamp: target.capturedAt.addingTimeInterval(0.01),
                    routerIP: target.address,
                    latencyMs: 12,
                    probeOutcome: .replied(milliseconds: 12),
                    attemptID: UUID(),
                    cycleID: target.snapshotCycleID,
                    interfaceName: target.interfaceName,
                    interfaceBound: true
                )
            }
        )
        let task = Task {
            await sampler.sample(
                before: WiFiGatewayEvidenceBefore(
                    cycleID: cycleID,
                    snapshot: snapshot,
                    status: status,
                    linkSnapshot: nil,
                    linkFetchedAt: nil,
                    startedAt: capturedAt
                )
            )
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let sample = await task.value

        #expect(sample.attribution == .cancelled)
        #expect(sample.outcome == .cancelled)
        #expect(sample.after == nil)
        #expect(sample.latencyValidity == .notApplicable)
    }

    // MARK: - Fixtures

    private func mappedSample(
        result: GatewayProbeOutcome,
        reportedLatencyOverride: Double? = nil,
        after: SnapshotVariant = .associated
    ) async -> GatewayLatencyResult {
        let cycleID = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_650)
        let snapshot = Self.snapshot(from: .associated, cycleID: cycleID, capturedAt: capturedAt)
        let status = await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
        let sampler = makeSampler(
            variants: [after],
            links: [.associated(epoch: 7)],
            result: result,
            reportedLatencyOverride: reportedLatencyOverride
        )
        let sample = await sampler.sample(
            before: WiFiGatewayEvidenceBefore(
                cycleID: cycleID,
                snapshot: snapshot,
                status: status,
                linkSnapshot: nil,
                linkFetchedAt: nil,
                startedAt: capturedAt
            )
        )
        return sample.gatewayLatencyResult(for: status)
    }

    private static func linkSnapshot() -> WiFiLinkStateSnapshot {
        let now = Date()
        return WiFiLinkStateSnapshot(
            runSessionID: UUID(),
            sequence: 1,
            linkEpoch: 1,
            interfaceName: "en0",
            interfaceIndex: 4,
            radio: .reportedOn,
            state: .associated,
            networkIdentity: WiFiNetworkIdentity(ssid: "Lab", bssid: "AA:BB:CC:DD:EE:FF"),
            reason: .stationMode,
            evidenceSourceIDs: [],
            sampledAt: now,
            publishedAt: now
        )
    }


    fileprivate enum LinkState {
        case associated(epoch: UInt64, age: TimeInterval = 0)
        case disconnected(age: TimeInterval = 0)

        var snapshot: (UInt64, UInt64, VerifiedWiFiLinkState, TimeInterval) {
            switch self {
            case .associated(let epoch, let age):
                return (7, epoch, .associated, age)
            case .disconnected(let age):
                return (7, 0, .disconnected, age)
            }
        }
    }

    fileprivate struct SnapshotVariant: Sendable {
        var interfaceName = "en0"
        var interfaceIndex: UInt32 = 4
        var router: String? = "192.0.2.1"
        var ssid: String? = "Lab"
        var bssid: String? = "AA:BB:CC:DD:EE:FF"
        var linkActive = true
        var enumerationSucceeded = true
        var wifiDiscoverySucceeded = true

        static let associated = SnapshotVariant()
    }

    private func makeSampler(
        variants: [SnapshotVariant],
        links: [LinkState],
        result: GatewayProbeOutcome,
        interfaceBound: Bool = true,
        reportedLatencyOverride: Double? = nil
    ) -> SystemWiFiGatewayEvidenceSampler {
        let variantSequence = VariantSequence(variants)
        let linkSequence = LinkSequence(links)
        let sessionID = UUID()
        return SystemWiFiGatewayEvidenceSampler(
            linkSnapshot: {
                let (sequence, epoch, state, age) = linkSequence.next().snapshot
                let publishedAt = Date().addingTimeInterval(-age)
                return WiFiLinkStateSnapshot(
                    runSessionID: sessionID,
                    sequence: sequence,
                    linkEpoch: epoch,
                    interfaceName: "en0",
                    interfaceIndex: 4,
                    radio: .reportedOn,
                    state: state,
                    networkIdentity: WiFiNetworkIdentity(ssid: "Lab", bssid: "AA:BB:CC:DD:EE:FF"),
                    reason: .stationMode,
                    evidenceSourceIDs: [],
                    sampledAt: publishedAt,
                    publishedAt: publishedAt
                )
            },
            captureSnapshot: { cycleID, capturedAt in
                Self.snapshot(from: variantSequence.next(), cycleID: cycleID, capturedAt: capturedAt)
            },
            currentStatus: { snapshot in
                await WiFiCurrentConnectionProvider().fetchCurrentStatus(from: snapshot)
            },
            measure: { target in
                let reportedLatency: Double?
                if case .replied(let milliseconds) = result {
                    reportedLatency = reportedLatencyOverride ?? milliseconds
                } else {
                    reportedLatency = nil
                }
                return GatewayLatencyResult(
                    timestamp: target.capturedAt.addingTimeInterval(0.001),
                    routerIP: target.address,
                    latencyMs: reportedLatency,
                    probeOutcome: result,
                    attemptID: UUID(),
                    cycleID: target.snapshotCycleID,
                    interfaceName: target.interfaceName,
                    interfaceBound: interfaceBound
                )
            }
        )
    }

    private static func snapshot(
        from variant: SnapshotVariant,
        cycleID: UUID,
        capturedAt: Date
    ) -> NetworkInterfaceSnapshot {
        let evidence = WiFiLinkRawEvidence(
            snapshotCycleID: cycleID,
            capturedAt: capturedAt,
            interfaceName: variant.interfaceName,
            mode: .station,
            radio: .reportedOn,
            linkActive: variant.linkActive,
            ssid: variant.ssid,
            bssid: variant.bssid,
            interfaceIndex: variant.interfaceIndex
        )
        let interface = NetworkInterfaceInfo(
            interfaceName: variant.interfaceName,
            interfaceIndex: variant.interfaceIndex,
            isWiFiInterface: true,
            wifiLinkEvidence: evidence,
            metricsAttribution: .verified,
            ipv4Addresses: ["192.0.2.2"],
            subnetMasks: ["255.255.255.0"],
            router: variant.router,
            dnsServers: ["192.0.2.1"],
            ssid: variant.ssid,
            bssid: variant.bssid,
            channel: 36,
            band: .band5GHz,
            rssi: -48,
            txRate: 866,
            phyMode: "ax",
            security: "WPA3"
        )
        return NetworkInterfaceSnapshot(
            cycleID: cycleID,
            capturedAt: capturedAt,
            interfaces: [interface],
            interfaceEnumerationSucceeded: variant.enumerationSucceeded,
            wifiInterfaceDiscoverySucceeded: variant.wifiDiscoverySucceeded
        )
    }
}

private final class VariantSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0
    private let variants: [WiFiGatewayEvidenceSamplingTests.SnapshotVariant]

    init(_ variants: [WiFiGatewayEvidenceSamplingTests.SnapshotVariant]) {
        self.variants = variants
    }

    func next() -> WiFiGatewayEvidenceSamplingTests.SnapshotVariant {
        lock.lock()
        defer { lock.unlock() }
        let variant = variants[min(index, variants.count - 1)]
        index += 1
        return variant
    }
}

private final class LinkSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0
    private let links: [WiFiGatewayEvidenceSamplingTests.LinkState]

    init(_ links: [WiFiGatewayEvidenceSamplingTests.LinkState]) {
        self.links = links
    }

    func next() -> WiFiGatewayEvidenceSamplingTests.LinkState {
        lock.lock()
        defer { lock.unlock() }
        let link = links[min(index, links.count - 1)]
        index += 1
        return link
    }
}

private actor CallCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}
