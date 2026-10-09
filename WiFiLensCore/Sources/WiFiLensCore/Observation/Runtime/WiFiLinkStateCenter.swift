import CoreWLAN
import Foundation
import AppKit
import SystemConfiguration

public protocol WiFiLinkEvidenceCollecting: Sendable {
    func capture() async -> WiFiLinkRawEvidence?
}

public struct SystemWiFiLinkEvidenceCollector: WiFiLinkEvidenceCollecting {
    public init() {}

    @concurrent
    public func capture() async -> WiFiLinkRawEvidence? {
        let cycleID = UUID()
        let capturedAt = Date()
        return NetworkInfoService.captureWiFiLinkEvidence(cycleID: cycleID, capturedAt: capturedAt)
    }
}

public struct WiFiNetworkIdentity: Equatable, Sendable {
    public let ssid: String?
    public let bssid: String?

    public init(ssid: String?, bssid: String?) {
        self.ssid = ssid
        self.bssid = bssid
    }

    public var isKnown: Bool { ssid != nil || bssid != nil }
}

public struct WiFiLinkStateSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let runSessionID: UUID
    public let sequence: UInt64
    public let linkEpoch: UInt64
    public let interfaceName: String?
    public let interfaceIndex: UInt32?
    public let radio: WiFiRadioEvidence
    public let state: VerifiedWiFiLinkState
    public let networkIdentity: WiFiNetworkIdentity?
    public let reason: WiFiLinkEvidenceReason
    public let evidenceSourceIDs: [UUID]
    public let sampledAt: Date?
    public let publishedAt: Date

    public init(
        id: UUID = UUID(), runSessionID: UUID, sequence: UInt64, linkEpoch: UInt64,
        interfaceName: String?, interfaceIndex: UInt32?, radio: WiFiRadioEvidence,
        state: VerifiedWiFiLinkState, networkIdentity: WiFiNetworkIdentity?,
        reason: WiFiLinkEvidenceReason, evidenceSourceIDs: [UUID], sampledAt: Date?, publishedAt: Date
    ) {
        self.id = id
        self.runSessionID = runSessionID
        self.sequence = sequence
        self.linkEpoch = linkEpoch
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.radio = radio
        self.state = state
        self.networkIdentity = networkIdentity
        self.reason = reason
        self.evidenceSourceIDs = evidenceSourceIDs
        self.sampledAt = sampledAt
        self.publishedAt = publishedAt
    }

    public func isFresh(at date: Date = Date(), maximumAge: TimeInterval = 15) -> Bool {
        guard let sampledAt, sampledAt <= date else { return false }
        return date.timeIntervalSince(sampledAt) <= maximumAge
    }
}

public enum WiFiLinkStateEventType: String, Equatable, Sendable {
    case disconnected
    case associated
    case networkIdentityChanged
    case radioChanged
    case continuityReset
}

public struct WiFiLinkStateEvent: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let type: WiFiLinkStateEventType
    public let runSessionID: UUID
    public let sequence: UInt64
    public let interfaceName: String?
    public let interfaceIndex: UInt32?
    public let linkEpoch: UInt64
    public let previousEvidence: WiFiLinkRawEvidence?
    public let currentEvidence: WiFiLinkRawEvidence?
    public let lastConfirmedPreviousAt: Date?
    public let firstConfirmedCurrentAt: Date?
    public let confirmedAt: Date

    public init(
        id: UUID = UUID(), type: WiFiLinkStateEventType, runSessionID: UUID, sequence: UInt64,
        interfaceName: String?, interfaceIndex: UInt32?, linkEpoch: UInt64,
        previousEvidence: WiFiLinkRawEvidence?, currentEvidence: WiFiLinkRawEvidence?,
        lastConfirmedPreviousAt: Date?, firstConfirmedCurrentAt: Date?, confirmedAt: Date
    ) {
        self.id = id
        self.type = type
        self.runSessionID = runSessionID
        self.sequence = sequence
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.linkEpoch = linkEpoch
        self.previousEvidence = previousEvidence
        self.currentEvidence = currentEvidence
        self.lastConfirmedPreviousAt = lastConfirmedPreviousAt
        self.firstConfirmedCurrentAt = firstConfirmedCurrentAt
        self.confirmedAt = confirmedAt
    }
}

public enum WiFiLinkChangeReason: String, Sendable {
    case systemConfiguration
    case coreWLAN
    case compensationSample
    case appBecameActive
    case interfaceChanged
    case willSleep
    case didWake
    case compensationSampleFailed
}

public struct WiFiLinkListenerStatus: Equatable, Sendable {
    public let isRunning: Bool
    public let systemConfigurationRegistered: Bool
    public let coreWLANRegistered: Bool
    public let coreWLANRegistrationError: String?

    public init(isRunning: Bool, systemConfigurationRegistered: Bool, coreWLANRegistered: Bool, coreWLANRegistrationError: String?) {
        self.isRunning = isRunning
        self.systemConfigurationRegistered = systemConfigurationRegistered
        self.coreWLANRegistered = coreWLANRegistered
        self.coreWLANRegistrationError = coreWLANRegistrationError
    }
}

#if DEBUG
private enum WiFiLinkDiagnosticsLogger {
    private static let queue = DispatchQueue(label: "WiFiLens.WiFiLinkDiagnostics")
    private static let enabled = ProcessInfo.processInfo.environment["WIFILENS_LINK_DIAGNOSTICS"] == "1"

    static var logURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WiFiLens/Diagnostics/WiFiLinkState.jsonl")
    }

    static func record(_ kind: String, _ values: [String: Any] = [:], fileName: String = "events.jsonl") {
        guard enabled, let rootURL = logURL?.deletingLastPathComponent() else { return }
        let fileURL = rootURL.appendingPathComponent(fileName)
        var record = values
        record["kind"] = kind
        record["recordedAt"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .fragmentsAllowed]) else { return }
        queue.async {
            do {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                let environmentURL = rootURL.appendingPathComponent("environment.json")
                if !FileManager.default.fileExists(atPath: environmentURL.path) {
                    let environment: [String: Any] = ["schemaVersion": 1, "source": "WiFi Lens DEBUG app"]
                    try JSONSerialization.data(withJSONObject: environment, options: [.sortedKeys, .prettyPrinted]).write(to: environmentURL, options: .atomic)
                    try Data().write(to: rootURL.appendingPathComponent("markers.jsonl"), options: .atomic)
                }
                var line = data
                line.append(0x0A)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                } else {
                    try line.write(to: fileURL, options: .atomic)
                }
            } catch {
                // Diagnostics must never interfere with link monitoring.
            }
        }
    }
}
#endif

@MainActor
public protocol WiFiLinkChangeTriggering: AnyObject, Sendable {
    var systemConfigurationRegistered: Bool { get }
    var coreWLANRegistered: Bool { get }
    var coreWLANRegistrationError: String? { get }
    func start(interfaceName: String?, handler: @escaping @Sendable (WiFiLinkChangeReason) -> Void)
    func updateInterface(_ name: String?)
    func stop()
}

@MainActor
public final class WiFiLinkChangeTrigger: NSObject, CWEventDelegate, WiFiLinkChangeTriggering {
    public private(set) var systemConfigurationRegistered = false
    public private(set) var coreWLANRegistered = false
    public private(set) var coreWLANRegistrationError: String?

    private var dynamicStore: SCDynamicStore?
    private var handler: (@Sendable (WiFiLinkChangeReason) -> Void)?
    private var sleepTokens: [NSObjectProtocol] = []
    private var monitoredInterfaceName: String?

    public func start(interfaceName: String?, handler: @escaping @Sendable (WiFiLinkChangeReason) -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        monitoredInterfaceName = interfaceName
        registerSystemConfiguration(interfaceName: interfaceName)
        registerCoreWLAN()
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "systemConfigurationRegistration",
            "source": "SystemConfiguration",
            "success": systemConfigurationRegistered,
            "time": ISO8601DateFormatter().string(from: Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": coreWLANRegistered ? "coreWLANRegistrationSuccess" : "coreWLANRegistrationFailure",
            "source": "CoreWLAN",
            "success": coreWLANRegistered,
            "error": coreWLANRegistrationError ?? "none",
            "time": ISO8601DateFormatter().string(from: Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        sleepTokens = [
            workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handler?(.willSleep) }
            },
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handler?(.didWake) }
            }
        ]
    }

    public func updateInterface(_ name: String?) {
        guard monitoredInterfaceName != name, let handler else { return }
        stopSystemConfiguration()
        monitoredInterfaceName = name
        registerSystemConfiguration(interfaceName: name)
        _ = handler
    }

    public func stop() {
        guard handler != nil else { return }
        stopSystemConfiguration()
        let center = NSWorkspace.shared.notificationCenter
        sleepTokens.forEach(center.removeObserver)
        sleepTokens.removeAll()
        let client = CWWiFiClient.shared()
        if client.delegate === self {
            client.delegate = nil
            try? client.stopMonitoringEvent(with: .powerDidChange)
        }
        handler = nil
        monitoredInterfaceName = nil
        coreWLANRegistered = false
    }

    private func registerSystemConfiguration(interfaceName: String?) {
        let context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let trigger = Unmanaged<WiFiLinkChangeTrigger>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                #if DEBUG
                WiFiLinkDiagnosticsLogger.record("event", ["eventType": "dynamicStoreChanged", "source": "SystemConfiguration", "time": ISO8601DateFormatter().string(from: Date()), "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds])
                #endif
                trigger.handler?(.systemConfiguration)
            }
        }
        var storeContext = context
        guard let store = SCDynamicStoreCreate(nil, "WiFiLens.LinkStateCenter" as CFString, callback, &storeContext) else {
            systemConfigurationRegistered = false
            return
        }
        let keys = interfaceName.map { ["State:/Network/Interface/\($0)/Link" as CFString] as CFArray } ?? [] as CFArray
        let patterns = ["State:/Network/Service/.*/IPv4" as CFString] as CFArray
        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main) else {
            dynamicStore = nil
            systemConfigurationRegistered = false
            return
        }
        dynamicStore = store
        systemConfigurationRegistered = true
    }

    private func stopSystemConfiguration() {
        if let dynamicStore { SCDynamicStoreSetDispatchQueue(dynamicStore, nil) }
        dynamicStore = nil
        systemConfigurationRegistered = false
    }

    private func registerCoreWLAN() {
        let client = CWWiFiClient.shared()
        guard client.delegate == nil || client.delegate === self else {
            coreWLANRegistrationError = "A different CoreWLAN delegate already owns the shared client."
            return
        }
        client.delegate = self
        do {
            try client.startMonitoringEvent(with: .powerDidChange)
            coreWLANRegistered = true
            coreWLANRegistrationError = nil
        } catch {
            if client.delegate === self { client.delegate = nil }
            coreWLANRegistered = false
            coreWLANRegistrationError = String(describing: error)
        }
    }

    nonisolated public func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            #if DEBUG
            WiFiLinkDiagnosticsLogger.record("event", ["eventType": "powerDidChange", "source": "CoreWLAN", "success": true, "time": ISO8601DateFormatter().string(from: Date()), "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds])
            #endif
            handler?(.coreWLAN)
        }
    }
}

public actor WiFiLinkStateCenter {
    public static let shared = WiFiLinkStateCenter()

    private let collector: any WiFiLinkEvidenceCollecting
    private let allowsUnvalidatedDisconnectConfirmation: Bool
    private let pollingInterval: Duration
    private var trigger: (any WiFiLinkChangeTriggering)?
    private var runSessionID = UUID()
    private var sequence: UInt64 = 0
    private var linkEpoch: UInt64 = 0
    private var isRunning = false
    private var isSampling = false
    private var sampleRequestedWhileBusy = false
    private var pollingTask: Task<Void, Never>?
    private var currentSnapshot: WiFiLinkStateSnapshot
    private var previousEvidence: WiFiLinkRawEvidence?
    private var confirmedState: VerifiedWiFiLinkState = .unknown
    private var disconnectTransitionEmitted = false
    private var lastConfirmedStateAt: Date?
    private var disconnectCandidates: [WiFiLinkRawEvidence] = []
    private var currentContinuityValid = true
    private var currentSubscribers: [UUID: AsyncStream<WiFiLinkStateSnapshot>.Continuation] = [:]
    private var eventSubscribers: [UUID: AsyncStream<WiFiLinkStateEvent>.Continuation] = [:]

    public init(
        collector: any WiFiLinkEvidenceCollecting = SystemWiFiLinkEvidenceCollector(),
        trigger: (any WiFiLinkChangeTriggering)? = nil,
        pollingInterval: Duration = .seconds(5),
        allowsUnvalidatedDisconnectConfirmation: Bool = false
    ) {
        self.collector = collector
        self.trigger = trigger
        self.pollingInterval = pollingInterval
        self.allowsUnvalidatedDisconnectConfirmation = allowsUnvalidatedDisconnectConfirmation
        let initialSessionID = UUID()
        runSessionID = initialSessionID
        currentSnapshot = WiFiLinkStateSnapshot(
            runSessionID: initialSessionID, sequence: 0, linkEpoch: 0, interfaceName: nil,
            interfaceIndex: nil, radio: .unavailable, state: .unknown, networkIdentity: nil,
            reason: .modeUnavailable, evidenceSourceIDs: [], sampledAt: nil, publishedAt: Date()
        )
    }

    public func snapshot() -> WiFiLinkStateSnapshot { currentSnapshot }

    public func listenerStatus() async -> WiFiLinkListenerStatus {
        guard let trigger else {
            return WiFiLinkListenerStatus(
                isRunning: isRunning, systemConfigurationRegistered: false,
                coreWLANRegistered: false, coreWLANRegistrationError: nil
            )
        }
        let running = isRunning
        return await MainActor.run {
            WiFiLinkListenerStatus(
                isRunning: running,
                systemConfigurationRegistered: trigger.systemConfigurationRegistered,
                coreWLANRegistered: trigger.coreWLANRegistered,
                coreWLANRegistrationError: trigger.coreWLANRegistrationError
            )
        }
    }

    public func refresh() async { await requestSample(reason: .compensationSample) }

    public func currentStates() -> AsyncStream<WiFiLinkStateSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            currentSubscribers[id] = continuation
            continuation.yield(currentSnapshot)
            continuation.onTermination = { [weak self] _ in Task { await self?.removeCurrentSubscriber(id) } }
        }
    }

    /// Transition events use an unbounded per-subscriber queue. State transitions
    /// are rare, and retaining order avoids silently losing a disconnect event.
    public func events() -> AsyncStream<WiFiLinkStateEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventSubscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in Task { await self?.removeEventSubscriber(id) } }
        }
    }

    public func start() async {
        guard !isRunning else { return }
        if Self.isUnitTestHost, collector is SystemWiFiLinkEvidenceCollector {
            currentContinuityValid = false
            currentSnapshot = makeSnapshot(
                state: .unknown, evidence: nil, reason: .samplingContinuityLost,
                sources: [], identity: nil, radio: .unavailable
            )
            publishCurrent()
            return
        }
        isRunning = true
        runSessionID = UUID()
        sequence = 0
        linkEpoch = 0
        previousEvidence = nil
        confirmedState = .unknown
        disconnectTransitionEmitted = false
        lastConfirmedStateAt = nil
        disconnectCandidates.removeAll()
        currentContinuityValid = true
        currentSnapshot = makeSnapshot(
            state: .unknown, evidence: nil, reason: .samplingContinuityLost,
            sources: [], identity: nil, radio: .unavailable
        )
        publishCurrent()
        await requestSample(reason: .compensationSample)
        await startTrigger(interfaceName: currentSnapshot.interfaceName)
        pollingTask = Task { [weak self, pollingInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollingInterval)
                guard !Task.isCancelled else { break }
                await self?.requestSample(reason: .compensationSample)
            }
        }
    }

    public func stop() async {
        guard isRunning else { return }
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        await stopTrigger()
        let previousEvidence = previousEvidence
        let previousConfirmationTime = lastConfirmedStateAt
        linkEpoch &+= 1
        currentContinuityValid = false
        confirmedState = .unknown
        disconnectTransitionEmitted = false
        lastConfirmedStateAt = nil
        disconnectCandidates.removeAll()
        currentSnapshot = makeSnapshot(
            state: .unknown, evidence: nil, reason: .samplingContinuityLost,
            sources: [], identity: nil, radio: currentSnapshot.radio
        )
        publishCurrent()
        publishEvent(.continuityReset, previous: previousEvidence, current: nil, firstAt: nil, previousAt: previousConfirmationTime)
        self.previousEvidence = nil
    }

    public func applicationBecameActive() async {
        guard isRunning else { return }
        await resetContinuity(reason: .appBecameActive)
        await requestSample(reason: .appBecameActive)
    }

    private func requestSample(reason: WiFiLinkChangeReason) async {
        guard isRunning else { return }
        guard !isSampling else { sampleRequestedWhileBusy = true; return }
        isSampling = true
        repeat {
            sampleRequestedWhileBusy = false
            let evidence = await collector.capture()
            process(evidence, reason: reason)
        } while sampleRequestedWhileBusy && isRunning
        isSampling = false
    }

    private func process(_ evidence: WiFiLinkRawEvidence?, reason: WiFiLinkChangeReason) {
        guard let evidence else {
            if currentContinuityValid || confirmedState != .unknown {
                resetContinuityWithoutAwaiting(reason: .compensationSampleFailed, previous: previousEvidence, current: nil)
            }
            confirmedState = .unknown
            lastConfirmedStateAt = nil
            previousEvidence = nil
            currentContinuityValid = false
            disconnectCandidates.removeAll()
            currentSnapshot = makeSnapshot(
                state: .unknown, evidence: nil, reason: .interfaceDiscoveryUnavailable,
                sources: [], identity: nil, radio: .unavailable
            )
            publishCurrent()
            return
        }

        if let previousEvidence,
           previousEvidence.interfaceName != evidence.interfaceName || previousEvidence.interfaceIndex != evidence.interfaceIndex {
            resetContinuityWithoutAwaiting(reason: .interfaceChanged, previous: previousEvidence, current: evidence)
        }

        let assessment = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: evidence.snapshotCycleID,
            expectedCapturedAt: evidence.capturedAt
        )
        let previousConfirmationTime = lastConfirmedStateAt
        var state = assessment.state
        var assessmentReason = assessment.reason
        var eventType: WiFiLinkStateEventType?
        var firstCurrentAt: Date?
        var continuityReset = false

        if state == .associated {
            disconnectCandidates.removeAll()
            currentContinuityValid = true
            if confirmedState == .disconnected {
                if disconnectTransitionEmitted {
                    linkEpoch &+= 1
                    eventType = .associated
                    firstCurrentAt = evidence.capturedAt
                }
            } else if confirmedState == .associated,
                      let previousEvidence,
                      Self.didChangeTrustedIdentity(from: previousEvidence, to: evidence) {
                eventType = .networkIdentityChanged
                firstCurrentAt = evidence.capturedAt
            }
            if confirmedState != .associated, confirmedState == .unknown { lastConfirmedStateAt = evidence.capturedAt }
            confirmedState = .associated
            disconnectTransitionEmitted = false
        } else if assessment.candidateState == .disconnected {
            if !currentContinuityValid {
                disconnectCandidates.removeAll()
                currentContinuityValid = true
            }
            if allowsUnvalidatedDisconnectConfirmation,
               appendCandidate(evidence),
               disconnectCandidates.count >= 2 {
                state = .disconnected
                assessmentReason = .disconnectCandidate
                if confirmedState == .associated, !disconnectTransitionEmitted {
                    linkEpoch &+= 1
                    eventType = .disconnected
                    firstCurrentAt = disconnectCandidates.first?.capturedAt
                    disconnectTransitionEmitted = true
                }
                if confirmedState == .unknown { lastConfirmedStateAt = evidence.capturedAt }
                confirmedState = .disconnected
            } else {
                state = .unknown
                assessmentReason = allowsUnvalidatedDisconnectConfirmation ? .disconnectCandidate : .disconnectEvidenceNotValidated
            }
        } else {
            disconnectCandidates.removeAll()
            if state == .unknown {
                if currentContinuityValid || confirmedState != .unknown {
                    linkEpoch &+= 1
                    continuityReset = true
                }
                currentContinuityValid = false
                confirmedState = .unknown
                lastConfirmedStateAt = nil
                disconnectTransitionEmitted = false
            }
        }

        let identity = state == .associated ? Self.trustedIdentity(evidence) : nil
        let oldRadio = currentSnapshot.radio
        currentSnapshot = makeSnapshot(
            state: state, evidence: evidence, reason: assessmentReason,
            sources: [evidence.snapshotCycleID], identity: identity, radio: evidence.radio
        )
        publishCurrent()
        #if DEBUG
        let modeValue: String? = switch evidence.mode {
        case .station: "station"
        case .none: "none"
        case .noneOrReadFailure, .other, .unavailable: nil
        }
        let powerValue = evidence.radioPowerOnRaw
        let sampleStart = DispatchTime.now().uptimeNanoseconds
        let triggerValue: String = switch reason {
        case .compensationSample: "timer"
        case .systemConfiguration, .coreWLAN, .interfaceChanged: "notification"
        case .appBecameActive, .didWake, .willSleep: "startup"
        case .compensationSampleFailed: "notification"
        }
        WiFiLinkDiagnosticsLogger.record("sample", [
            "schemaVersion": 1,
            "time": ISO8601DateFormatter().string(from: evidence.capturedAt),
            "sampleStartedAt": ISO8601DateFormatter().string(from: evidence.captureStartedAt),
            "sampleEndedAt": ISO8601DateFormatter().string(from: evidence.captureEndedAt),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds,
            "sampleStartMonotonicNanoseconds": sampleStart,
            "trigger": triggerValue,
            "mode": modeValue as Any? ?? NSNull(),
            "powerOnRaw": powerValue as Any? ?? NSNull(),
            "serviceActiveRaw": evidence.serviceActive as Any? ?? NSNull(),
            "scLinkActive": evidence.linkActive as Any? ?? NSNull(),
            "scLinkDetaching": evidence.linkDetaching as Any? ?? NSNull(),
            "interfaceUp": evidence.interfaceFlagsUp as Any? ?? NSNull(),
            "interfaceRunning": evidence.interfaceFlagsRunning as Any? ?? NSNull(),
            "scLinkKeyPresent": evidence.linkSource != nil,
            "cycleID": evidence.snapshotCycleID.uuidString,
            "interfaceIndex": evidence.interfaceIndex.map { String($0) } ?? "unknown",
            "readFailures": evidence.readFailures.keys.map(\.rawValue).sorted().joined(separator: ","),
            "assessment": assessmentReason.rawValue,
            "state": state.rawValue,
            "reason": assessmentReason.rawValue,
            "captureStartedAt": ISO8601DateFormatter().string(from: evidence.captureStartedAt),
            "captureEndedAt": ISO8601DateFormatter().string(from: evidence.captureEndedAt)
        ], fileName: "observations.jsonl")
        #endif
        if oldRadio != evidence.radio, oldRadio != .unavailable {
            publishEvent(.radioChanged, previous: previousEvidence, current: evidence, firstAt: evidence.capturedAt, previousAt: previousConfirmationTime)
        }
        if let eventType {
            publishEvent(eventType, previous: previousEvidence, current: evidence, firstAt: firstCurrentAt, previousAt: previousConfirmationTime)
            lastConfirmedStateAt = evidence.capturedAt
        }
        if continuityReset {
            publishEvent(.continuityReset, previous: previousEvidence, current: evidence, firstAt: nil, previousAt: previousConfirmationTime)
        }
        previousEvidence = evidence
        if let trigger {
            Task { @MainActor in trigger.updateInterface(evidence.interfaceName) }
        }
    }

    private func appendCandidate(_ evidence: WiFiLinkRawEvidence) -> Bool {
        guard evidence.mode == .none || evidence.mode == .noneOrReadFailure,
              evidence.radio == .reportedOn,
              evidence.linkActive == false,
              evidence.serviceActive == false || evidence.interfaceFlagsRunning == false,
              evidence.captureStartedAt <= evidence.capturedAt,
              evidence.capturedAt <= evidence.captureEndedAt else {
            disconnectCandidates.removeAll()
            return false
        }
        if let previous = disconnectCandidates.last {
            guard previous.snapshotCycleID != evidence.snapshotCycleID,
                  previous.interfaceName == evidence.interfaceName,
                  previous.interfaceIndex == evidence.interfaceIndex,
                  previous.capturedAt < evidence.capturedAt else {
                disconnectCandidates.removeAll()
                return false
            }
        }
        disconnectCandidates.append(evidence)
        if disconnectCandidates.count > 2 { disconnectCandidates.removeFirst() }
        return true
    }

    private func resetContinuity(reason: WiFiLinkChangeReason) async {
        resetContinuityWithoutAwaiting(reason: reason, previous: previousEvidence, current: nil)
    }

    private func resetContinuityWithoutAwaiting(
        reason: WiFiLinkChangeReason,
        previous: WiFiLinkRawEvidence?,
        current: WiFiLinkRawEvidence?
    ) {
        let previousConfirmationTime = lastConfirmedStateAt
        linkEpoch &+= 1
        currentContinuityValid = true
        disconnectCandidates.removeAll()
        confirmedState = .unknown
        disconnectTransitionEmitted = false
        lastConfirmedStateAt = nil
        currentSnapshot = makeSnapshot(
            state: .unknown, evidence: current, reason: .samplingContinuityLost,
            sources: current.map { [$0.snapshotCycleID] } ?? [], identity: nil,
            radio: current?.radio ?? currentSnapshot.radio
        )
        publishCurrent()
        publishEvent(.continuityReset, previous: previous, current: current, firstAt: nil, previousAt: previousConfirmationTime)
    }

    private func makeSnapshot(
        state: VerifiedWiFiLinkState, evidence: WiFiLinkRawEvidence?, reason: WiFiLinkEvidenceReason,
        sources: [UUID], identity: WiFiNetworkIdentity?, radio: WiFiRadioEvidence
    ) -> WiFiLinkStateSnapshot {
        sequence &+= 1
        return WiFiLinkStateSnapshot(
            runSessionID: runSessionID, sequence: sequence, linkEpoch: linkEpoch,
            interfaceName: evidence?.interfaceName, interfaceIndex: evidence?.interfaceIndex,
            radio: radio, state: state, networkIdentity: identity, reason: reason,
            evidenceSourceIDs: sources, sampledAt: evidence?.capturedAt, publishedAt: Date()
        )
    }

    private func publishCurrent() {
        currentSubscribers.values.forEach { $0.yield(currentSnapshot) }
    }

    private func publishEvent(
        _ type: WiFiLinkStateEventType,
        previous: WiFiLinkRawEvidence?, current: WiFiLinkRawEvidence?, firstAt: Date?, previousAt: Date? = nil
    ) {
        sequence &+= 1
        let event = WiFiLinkStateEvent(
            type: type, runSessionID: runSessionID, sequence: sequence,
            interfaceName: current?.interfaceName ?? previous?.interfaceName,
            interfaceIndex: current?.interfaceIndex ?? previous?.interfaceIndex,
            linkEpoch: linkEpoch, previousEvidence: previous, currentEvidence: current,
            lastConfirmedPreviousAt: previousAt ?? lastConfirmedStateAt, firstConfirmedCurrentAt: firstAt,
            confirmedAt: Date()
        )
#if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": type.rawValue,
            "source": "WiFiLinkStateCenter",
            "eventID": event.id.uuidString,
            "sequence": event.sequence,
            "linkEpoch": event.linkEpoch,
            "previousStateTime": event.lastConfirmedPreviousAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() as Any,
            "currentStateTime": event.firstConfirmedCurrentAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull() as Any,
            "time": ISO8601DateFormatter().string(from: event.confirmedAt),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
#endif
        eventSubscribers.values.forEach { $0.yield(event) }
    }

    private func startTrigger(interfaceName: String?) async {
        let trigger: any WiFiLinkChangeTriggering
        if let existing = self.trigger {
            trigger = existing
        } else {
            trigger = await MainActor.run { WiFiLinkChangeTrigger() }
            self.trigger = trigger
        }
        await MainActor.run { [weak self] in
            trigger.start(interfaceName: interfaceName) { [weak self] reason in
                Task { await self?.triggered(reason) }
            }
        }
    }

    private func stopTrigger() async {
        guard let trigger else { return }
        await MainActor.run { trigger.stop() }
    }

    private func triggered(_ reason: WiFiLinkChangeReason) async {
        switch reason {
        case .willSleep, .didWake, .interfaceChanged:
            await resetContinuity(reason: reason)
        default:
            break
        }
        await requestSample(reason: reason)
    }

    private func removeCurrentSubscriber(_ id: UUID) { currentSubscribers.removeValue(forKey: id) }
    private func removeEventSubscriber(_ id: UUID) { eventSubscribers.removeValue(forKey: id) }

    private static func trustedIdentity(_ evidence: WiFiLinkRawEvidence) -> WiFiNetworkIdentity? {
        let identity = WiFiNetworkIdentity(ssid: evidence.ssid, bssid: evidence.bssid)
        return identity.isKnown ? identity : nil
    }

    private static func didChangeTrustedIdentity(from previous: WiFiLinkRawEvidence, to current: WiFiLinkRawEvidence) -> Bool {
        if let previousSSID = previous.ssid, let currentSSID = current.ssid {
            if previousSSID != currentSSID { return true }
        }
        if let previousBSSID = previous.bssid, let currentBSSID = current.bssid {
            if previousBSSID != currentBSSID { return true }
        }
        return false
    }

    private static var isUnitTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
