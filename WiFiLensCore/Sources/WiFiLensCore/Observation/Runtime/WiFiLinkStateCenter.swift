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

public enum WiFiIdentityComparisonContinuity: String, Equatable, Sendable {
    case adjacentVerifiedObservations
    case separatedByUncertainEvidence
    case separatedByUnknownIdentity
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
    public let identityComparisonContinuity: WiFiIdentityComparisonContinuity?

    public init(
        id: UUID = UUID(), type: WiFiLinkStateEventType, runSessionID: UUID, sequence: UInt64,
        interfaceName: String?, interfaceIndex: UInt32?, linkEpoch: UInt64,
        previousEvidence: WiFiLinkRawEvidence?, currentEvidence: WiFiLinkRawEvidence?,
        lastConfirmedPreviousAt: Date?, firstConfirmedCurrentAt: Date?, confirmedAt: Date,
        identityComparisonContinuity: WiFiIdentityComparisonContinuity? = nil
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
        self.identityComparisonContinuity = identityComparisonContinuity
    }
}

public enum WiFiLinkChangeReason: String, Hashable, Sendable {
    case startup
    case systemConfiguration
    case coreWLAN
    case coreWLANPowerStateChanged
    case compensationSample
    case candidateReview
    case appBecameActive
    case interfaceChanged
    case willSleep
    case didWake
    case compensationSampleFailed
}

public protocol WiFiLinkReviewClock: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct ContinuousWiFiLinkReviewClock: WiFiLinkReviewClock {
    public init() {}
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
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
enum WiFiLinkDiagnosticEvidenceFields {
    static func make(from evidence: WiFiLinkRawEvidence) -> [String: Any] {
        let modeValue: String = switch evidence.mode {
        case .station: "station"
        case .none: "none"
        case .noneOrReadFailure: "noneOrReadFailure"
        case .other(let rawValue): "other(\(rawValue))"
        case .unavailable: "unavailable"
        }
        return [
            "mode": modeValue,
            "modeRaw": evidence.coreWLANModeRawValue as Any? ?? NSNull(),
            "modeInterpretation": evidence.mode == .noneOrReadFailure ? "noneOrReadFailure" : modeValue,
            "modeReadAmbiguous": evidence.mode == .noneOrReadFailure,
            "powerOnRaw": evidence.radioPowerOnRaw as Any? ?? NSNull(),
            "serviceActiveRaw": evidence.serviceActive as Any? ?? NSNull(),
            "scLinkActive": evidence.linkActive as Any? ?? NSNull(),
            "scLinkDetaching": evidence.linkDetaching as Any? ?? NSNull(),
            "interfaceUp": evidence.interfaceFlagsUp as Any? ?? NSNull(),
            "interfaceRunning": evidence.interfaceFlagsRunning as Any? ?? NSNull(),
            "scLinkKeyPresent": evidence.linkSource != nil,
            "cycleID": evidence.snapshotCycleID.uuidString,
            "interfaceIndex": evidence.interfaceIndex.map { String($0) } ?? "unknown",
            "readFailures": evidence.readFailures.keys.map(\.rawValue).sorted().joined(separator: ",")
        ]
    }
}

private enum WiFiLinkDiagnosticsLogger {
    private static let queue = DispatchQueue(label: "WiFiLens.WiFiLinkDiagnostics")
    private static let enabled = ProcessInfo.processInfo.environment["WIFILENS_LINK_DIAGNOSTICS"] == "1"
    private static let maximumFileSize = 4 * 1024 * 1024

    static var isEnabled: Bool { enabled }

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
                    let environment: [String: Any] = [
                        "schemaVersion": 1,
                        "source": "WiFi Lens DEBUG app",
                        "diagnosticsEnabled": true
                    ]
                    try JSONSerialization.data(withJSONObject: environment, options: [.sortedKeys, .prettyPrinted]).write(to: environmentURL, options: .atomic)
                    try Data().write(to: rootURL.appendingPathComponent("markers.jsonl"), options: .atomic)
                }
                var line = data
                line.append(0x0A)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
                    guard currentSize + line.count <= maximumFileSize else {
                        return
                    }
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                } else {
                    guard line.count <= maximumFileSize else { return }
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
    public private(set) var coreWLANRegistrationError: String?
    public var coreWLANRegistered: Bool { !registeredEvents.isEmpty && !isCoreWLANInterrupted }

    private var dynamicStore: SCDynamicStore?
    private var handler: (@Sendable (WiFiLinkChangeReason) -> Void)?
    private var sleepTokens: [NSObjectProtocol] = []
    private var monitoredInterfaceName: String?
    private let desiredEvents: [CWEventType] = [
        .powerDidChange, .linkDidChange, .ssidDidChange, .bssidDidChange, .modeDidChange
    ]
    private var registeredEvents = Set<CWEventType>()
    private var eventRegistrationErrors: [CWEventType: String] = [:]
    private var isCoreWLANInterrupted = false

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
        for event in registeredEvents {
            do { try client.stopMonitoringEvent(with: event) }
            catch {
                let message = "stop: \(error)"
                eventRegistrationErrors[event] = message
                #if DEBUG
                WiFiLinkDiagnosticsLogger.record("event", [
                    "eventType": "coreWLANEventUnregisterFailure",
                    "event": String(describing: event),
                    "error": message,
                    "source": "CoreWLAN"
                ])
                #endif
            }
        }
        registeredEvents.removeAll()
        if client.delegate === self {
            client.delegate = nil
        }
        handler = nil
        monitoredInterfaceName = nil
        coreWLANRegistrationError = eventRegistrationErrors.isEmpty
            ? nil
            : eventRegistrationErrors.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
        isCoreWLANInterrupted = false
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
        eventRegistrationErrors.removeAll()
        for event in desiredEvents where !registeredEvents.contains(event) {
            do {
                try client.startMonitoringEvent(with: event)
                registeredEvents.insert(event)
                eventRegistrationErrors.removeValue(forKey: event)
                #if DEBUG
                WiFiLinkDiagnosticsLogger.record("event", [
                    "eventType": "coreWLANEventRegistration",
                    "event": String(describing: event),
                    "success": true,
                    "source": "CoreWLAN"
                ])
                #endif
            } catch {
                eventRegistrationErrors[event] = String(describing: error)
                #if DEBUG
                WiFiLinkDiagnosticsLogger.record("event", [
                    "eventType": "coreWLANEventRegistration",
                    "event": String(describing: event),
                    "success": false,
                    "error": String(describing: error),
                    "source": "CoreWLAN"
                ])
                #endif
            }
        }
        isCoreWLANInterrupted = false
        coreWLANRegistrationError = eventRegistrationErrors.isEmpty
            ? nil
            : eventRegistrationErrors.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
    }

    nonisolated public func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        handleCoreWLANEvent(interfaceName: interfaceName, eventType: .powerDidChange, reason: .coreWLANPowerStateChanged)
    }

    nonisolated public func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        handleCoreWLANEvent(interfaceName: interfaceName, eventType: .linkDidChange, reason: .coreWLAN)
    }

    nonisolated public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        handleCoreWLANEvent(interfaceName: interfaceName, eventType: .ssidDidChange, reason: .coreWLAN)
    }

    nonisolated public func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        handleCoreWLANEvent(interfaceName: interfaceName, eventType: .bssidDidChange, reason: .coreWLAN)
    }

    nonisolated public func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        handleCoreWLANEvent(interfaceName: interfaceName, eventType: .modeDidChange, reason: .coreWLAN)
    }

    nonisolated public func clientConnectionInterrupted() {
        Task { @MainActor in
            guard handler != nil else { return }
            isCoreWLANInterrupted = true
            coreWLANRegistrationError = "CoreWLAN connection interrupted; automatic event recovery is pending."
            #if DEBUG
            WiFiLinkDiagnosticsLogger.record("event", ["eventType": "coreWLANConnectionInterrupted", "source": "CoreWLAN"])
            #endif
            handler?(.coreWLAN)
        }
    }

    nonisolated public func clientConnectionInvalidated() {
        Task { @MainActor in
            guard handler != nil else { return }
            registeredEvents.removeAll()
            isCoreWLANInterrupted = false
            coreWLANRegistrationError = "CoreWLAN client connection invalidated."
            #if DEBUG
            WiFiLinkDiagnosticsLogger.record("event", ["eventType": "coreWLANConnectionInvalidated", "source": "CoreWLAN"])
            #endif
            handler?(.coreWLAN)
        }
    }

    nonisolated private func handleCoreWLANEvent(
        interfaceName: String, eventType: CWEventType, reason: WiFiLinkChangeReason
    ) {
        Task { @MainActor in
            guard handler != nil,
                  monitoredInterfaceName == nil || monitoredInterfaceName == interfaceName else { return }
            isCoreWLANInterrupted = false
            if eventRegistrationErrors.isEmpty { coreWLANRegistrationError = nil }
            #if DEBUG
            WiFiLinkDiagnosticsLogger.record("event", [
                "eventType": String(describing: eventType), "interfaceName": interfaceName,
                "source": "CoreWLAN", "success": true,
                "listenerInterrupted": isCoreWLANInterrupted,
                "time": ISO8601DateFormatter().string(from: Date()),
                "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
            ])
            #endif
            handler?(reason)
        }
    }
}

public actor WiFiLinkStateCenter {
    public static let shared = WiFiLinkStateCenter()
    public static let minimumReviewInterval: Duration = .milliseconds(100)
    public static let maximumReviewInterval: Duration = .seconds(10)

    private let collector: any WiFiLinkEvidenceCollecting
    private let allowsUnvalidatedDisconnectConfirmation: Bool
    private let pollingInterval: Duration
    private let pollingClock: any WiFiLinkReviewClock
    private let reviewInterval: Duration
    private let reviewClock: any WiFiLinkReviewClock
    private var trigger: (any WiFiLinkChangeTriggering)?
    private var runSessionID = UUID()
    private var sequence: UInt64 = 0
    private var linkEpoch: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var isRunning = false
    private var activeSampleID: UUID?
    private var pendingSampleReasons: Set<WiFiLinkChangeReason> = []
    private var pollingTask: Task<Void, Never>?
    private var triggerOperationTail: Task<Void, Never>?
    private var candidateReviewTask: Task<Void, Never>?
    private var candidateReviewID: UUID?
    private var currentSnapshot: WiFiLinkStateSnapshot
    private var previousEvidence: WiFiLinkRawEvidence?
    private struct TrustedAssociation: Sendable {
        let evidence: WiFiLinkRawEvidence
        let identity: WiFiNetworkIdentity?
        let confirmedAt: Date
    }
    private struct TrustedIdentityField: Sendable {
        let value: String
        let evidence: WiFiLinkRawEvidence
        let confirmedAt: Date
    }
    private enum TrustedIdentityDifference: Equatable {
        case sameComparableFields
        case ssidChanged
        case bssidChanged
        case insufficientEvidence
    }
    private var lastVerifiedAssociation: TrustedAssociation?
    private var lastComparableIdentityAssociation: TrustedAssociation?
    private var trustedSSID: TrustedIdentityField?
    private var trustedBSSID: TrustedIdentityField?
    private var hasAssociationEvidenceGap = false
    private var hasIdentityEvidenceGap = false
    private var identityBoundaryEpochAdvancedForGap = false
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
        pollingClock: any WiFiLinkReviewClock = ContinuousWiFiLinkReviewClock(),
        reviewInterval: Duration = .seconds(1),
        reviewClock: any WiFiLinkReviewClock = ContinuousWiFiLinkReviewClock(),
        allowsUnvalidatedDisconnectConfirmation: Bool = false
    ) {
        self.collector = collector
        self.trigger = trigger
        self.pollingInterval = pollingInterval
        self.pollingClock = pollingClock
        self.reviewInterval = min(max(reviewInterval, Self.minimumReviewInterval), Self.maximumReviewInterval)
        self.reviewClock = reviewClock
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

    public func refresh() async {
        guard isRunning else { return }
        await requestSample(reason: .compensationSample, sessionID: runSessionID)
    }

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
            #if DEBUG
            WiFiLinkDiagnosticsLogger.record("event", [
                "eventType": "centerStartSkipped",
                "reason": "unitTestHost",
                "time": Self.utcTimestamp(Date()),
                "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
            ])
            #endif
            return
        }
        isRunning = true
        runSessionID = UUID()
        lifecycleGeneration &+= 1
        let sessionID = runSessionID
        let generation = lifecycleGeneration
        sequence = 0
        linkEpoch = 0
        previousEvidence = nil
        clearTrustedAssociations()
        confirmedState = .unknown
        disconnectTransitionEmitted = false
        lastConfirmedStateAt = nil
        disconnectCandidates.removeAll()
        pendingSampleReasons.removeAll()
        activeSampleID = nil
        currentContinuityValid = true
        currentSnapshot = makeSnapshot(
            state: .unknown, evidence: nil, reason: .samplingContinuityLost,
            sources: [], identity: nil, radio: .unavailable
        )
        publishCurrent()
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "centerStarted",
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "diagnosticsEnabled": WiFiLinkDiagnosticsLogger.isEnabled,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
        await startTrigger(interfaceName: nil, sessionID: sessionID)
        guard isRunning, runSessionID == sessionID else { return }
        pollingTask = Task { [weak self, pollingInterval, pollingClock] in
            while !Task.isCancelled {
                do { try await pollingClock.sleep(for: pollingInterval) }
                catch { break }
                guard !Task.isCancelled else { break }
                await self?.compensationTick(sessionID: sessionID)
            }
        }
        // Listener registration and compensation sampling must not depend on
        // the first evidence capture completing.
        await requestSample(reason: .startup, sessionID: sessionID)
        guard isRunning, runSessionID == sessionID else { return }
        if let interfaceName = currentSnapshot.interfaceName {
            await updateTriggerInterface(interfaceName, sessionID: sessionID)
        }
    }

    public func stop() async {
        guard isRunning else { return }
        let stoppedSessionID = runSessionID
        let previousEvidence = previousEvidence
        let previousConfirmationTime = lastConfirmedStateAt
        isRunning = false
        lifecycleGeneration &+= 1
        pollingTask?.cancel()
        pollingTask = nil
        cancelCandidateReview(reason: "monitoringStopped")
        activeSampleID = nil
        pendingSampleReasons.removeAll()
        linkEpoch &+= 1
        hasAssociationEvidenceGap = true
        identityBoundaryEpochAdvancedForGap = true
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
        clearTrustedAssociations()
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "centerStopped",
            "runSessionID": stoppedSessionID.uuidString,
            "lifecycleGeneration": lifecycleGeneration,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
        await stopTrigger()
    }

    public func applicationBecameActive() async {
        guard isRunning else { return }
        // AppKit may deliver scene activation once per window. Gaining focus
        // requests fresh evidence but does not invalidate link continuity.
        await requestSample(reason: .appBecameActive, sessionID: runSessionID)
    }

    private func requestSample(reason: WiFiLinkChangeReason, sessionID expectedSessionID: UUID) async {
        guard isRunning, runSessionID == expectedSessionID else { return }
        if activeSampleID != nil {
            pendingSampleReasons.insert(reason)
            return
        }

        var nextReason = reason
        while isRunning, runSessionID == expectedSessionID {
            let expectedGeneration = lifecycleGeneration
            let sampleID = UUID()
            activeSampleID = sampleID
            let sampleStartedAt = Date()
            let sampleStartMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
            let evidence = await collector.capture()
            let sampleEndedAt = Date()
            let sampleEndMonotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
            guard isCurrent(sessionID: expectedSessionID, generation: expectedGeneration),
                  activeSampleID == sampleID else {
                logDiscardedSample(
                    sampleID: sampleID, sessionID: expectedSessionID,
                    startedAt: sampleStartedAt, endedAt: sampleEndedAt,
                    startMonotonic: sampleStartMonotonicNanoseconds,
                    endMonotonic: sampleEndMonotonicNanoseconds,
                    reason: "sessionOrLifecycleChanged"
                )
                return
            }
            activeSampleID = nil
            process(
                evidence,
                reason: nextReason,
                sampleID: sampleID,
                sampleStartedAt: sampleStartedAt,
                sampleEndedAt: sampleEndedAt,
                sampleStartMonotonicNanoseconds: sampleStartMonotonicNanoseconds,
                sampleEndMonotonicNanoseconds: sampleEndMonotonicNanoseconds,
                sessionID: expectedSessionID,
                generation: expectedGeneration
            )
            guard isRunning, runSessionID == expectedSessionID else { return }
            guard let pendingReason = takePendingSampleReason() else { return }
            nextReason = pendingReason
        }
    }

    private func process(
        _ evidence: WiFiLinkRawEvidence?,
        reason: WiFiLinkChangeReason,
        sampleID: UUID,
        sampleStartedAt: Date,
        sampleEndedAt: Date,
        sampleStartMonotonicNanoseconds: UInt64,
        sampleEndMonotonicNanoseconds: UInt64,
        sessionID: UUID,
        generation: UInt64
    ) {
        guard let evidence else {
            cancelCandidateReview(reason: "sampleFailed")
            hasAssociationEvidenceGap = true
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
                sources: [], identity: nil,
                radio: currentSnapshot.radio == .reportedOff && reason != .coreWLANPowerStateChanged
                    ? .reportedOff
                    : .unavailable
            )
            publishCurrent()
            logSampleFailure(
                sampleID: sampleID, reason: reason, sessionID: sessionID,
                generation: generation, startedAt: sampleStartedAt, endedAt: sampleEndedAt,
                startMonotonic: sampleStartMonotonicNanoseconds,
                endMonotonic: sampleEndMonotonicNanoseconds,
                failureReason: "interfaceDiscoveryUnavailable",
                resultingState: .unknown
            )
            return
        }

        if let previousEvidence,
           previousEvidence.interfaceName != evidence.interfaceName || previousEvidence.interfaceIndex != evidence.interfaceIndex {
            cancelCandidateReview(reason: "interfaceChanged")
            resetContinuityWithoutAwaiting(reason: .interfaceChanged, previous: previousEvidence, current: evidence)
            clearTrustedAssociations()
        }
        if let comparableEvidence = lastComparableIdentityAssociation?.evidence,
           (comparableEvidence.interfaceName != evidence.interfaceName || comparableEvidence.interfaceIndex != evidence.interfaceIndex) {
            clearTrustedAssociations()
        }

        let assessment = WiFiLinkInterpreter.evaluate(
            evidence,
            expectedCycleID: evidence.snapshotCycleID,
            expectedCapturedAt: evidence.capturedAt
        )
        let previousConfirmationTime = lastConfirmedStateAt
        var state = assessment.state
        var assessmentReason = assessment.reason
        if evidence.readFailures[.mode] == .interfaceNotFound,
           evidence.readFailures[.radio] == .interfaceNotFound {
            assessmentReason = .interfaceUnavailable
        }
        var eventType: WiFiLinkStateEventType?
        var firstCurrentAt: Date?
        var continuityReset = false
        var identityEventPrevious: WiFiLinkRawEvidence?
        var identityEventPreviousAt: Date?
        var identityContinuity: WiFiIdentityComparisonContinuity?

        if state == .associated {
            if reason != .candidateReview {
                cancelCandidateReview(reason: "associationRestored")
            }
            disconnectCandidates.removeAll()
            let associationGap = hasAssociationEvidenceGap
            let identityGap = hasIdentityEvidenceGap
            let newIdentity = Self.trustedIdentity(evidence)
            let difference = Self.compareIdentity(
                previous: WiFiNetworkIdentity(ssid: trustedSSID?.value, bssid: trustedBSSID?.value),
                current: newIdentity
            )
            if difference == .ssidChanged || difference == .bssidChanged {
                eventType = .networkIdentityChanged
                firstCurrentAt = evidence.capturedAt
                identityEventPrevious = difference == .ssidChanged ? trustedSSID?.evidence : trustedBSSID?.evidence
                identityEventPreviousAt = difference == .ssidChanged ? trustedSSID?.confirmedAt : trustedBSSID?.confirmedAt
                identityContinuity = associationGap
                    ? .separatedByUncertainEvidence
                    : (identityGap ? .separatedByUnknownIdentity : .adjacentVerifiedObservations)
                if difference == .ssidChanged {
                    if confirmedState != .disconnected, !identityBoundaryEpochAdvancedForGap { linkEpoch &+= 1 }
                    // A different SSID starts a distinct logical network scope.
                    trustedBSSID = nil
                }
                identityBoundaryEpochAdvancedForGap = false
            }
            currentContinuityValid = true
            if confirmedState == .disconnected {
                if disconnectTransitionEmitted {
                    linkEpoch &+= 1
                    eventType = .associated
                    firstCurrentAt = evidence.capturedAt
                }
            }
            if confirmedState != .associated, confirmedState == .unknown { lastConfirmedStateAt = evidence.capturedAt }
            confirmedState = .associated
            disconnectTransitionEmitted = false
            lastVerifiedAssociation = TrustedAssociation(evidence: evidence, identity: newIdentity, confirmedAt: evidence.capturedAt)
            if let ssid = evidence.ssid {
                trustedSSID = TrustedIdentityField(value: ssid, evidence: evidence, confirmedAt: evidence.capturedAt)
            } else {
                hasIdentityEvidenceGap = true
            }
            if let bssid = evidence.bssid {
                trustedBSSID = TrustedIdentityField(value: bssid, evidence: evidence, confirmedAt: evidence.capturedAt)
            } else {
                hasIdentityEvidenceGap = true
            }
            if newIdentity?.isKnown == true {
                lastComparableIdentityAssociation = TrustedAssociation(evidence: evidence, identity: newIdentity, confirmedAt: evidence.capturedAt)
            }
            if difference != .insufficientEvidence {
                hasAssociationEvidenceGap = false
                hasIdentityEvidenceGap = evidence.ssid == nil || evidence.bssid == nil
                if difference == .sameComparableFields { identityBoundaryEpochAdvancedForGap = false }
            }
        } else if assessment.candidateState == .disconnected {
            hasAssociationEvidenceGap = true
            if !currentContinuityValid {
                disconnectCandidates.removeAll()
                currentContinuityValid = true
            }
            let wasFirstCandidate = disconnectCandidates.isEmpty
            let candidateWasAccepted = appendCandidate(evidence)
            if candidateWasAccepted, wasFirstCandidate {
                logCandidateEvent("candidateCycleStarted", evidence: evidence, sessionID: sessionID, generation: generation)
            } else if !candidateWasAccepted {
                cancelCandidateReview(reason: "candidateSequenceInvalid")
            }
            if allowsUnvalidatedDisconnectConfirmation, disconnectCandidates.count >= 2 {
                if reason != .candidateReview {
                    cancelCandidateReview(reason: "disconnectConfirmed")
                }
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
                assessmentReason = disconnectCandidates.isEmpty
                    ? .conflictingLinkEvidence
                    : (allowsUnvalidatedDisconnectConfirmation ? .disconnectCandidate : .disconnectEvidenceNotValidated)
                if wasFirstCandidate, !disconnectCandidates.isEmpty {
                    scheduleCandidateReview(sessionID: sessionID)
                }
            }
        } else {
            if reason != .candidateReview {
                cancelCandidateReview(reason: "candidateInvalidated")
            }
            disconnectCandidates.removeAll()
            hasAssociationEvidenceGap = true
            if state == .unknown {
                if currentContinuityValid || confirmedState != .unknown {
                    linkEpoch &+= 1
                    continuityReset = true
                    identityBoundaryEpochAdvancedForGap = true
                }
                currentContinuityValid = false
                confirmedState = .unknown
                lastConfirmedStateAt = nil
                disconnectTransitionEmitted = false
            }
        }

        let identity = state == .associated ? Self.trustedIdentity(evidence) : nil
        let oldRadio = currentSnapshot.radio
        let sampleRadio: WiFiRadioEvidence
        if Self.confirmsRadioOff(evidence, reason: reason) {
            sampleRadio = .reportedOff
        } else if evidence.radio == .reportedOn {
            sampleRadio = .reportedOn
        } else if reason == .coreWLANPowerStateChanged {
            // A new power transition with incomplete evidence invalidates the
            // prior radio conclusion; do not keep presenting Wi-Fi as off.
            sampleRadio = evidence.radio
        } else if oldRadio == .reportedOff {
            // Keep the explicit power-off confirmation through ambiguous
            // compensation samples until a fresh positive radio read arrives.
            sampleRadio = .reportedOff
        } else {
            sampleRadio = evidence.radio
        }
        currentSnapshot = makeSnapshot(
            state: state, evidence: evidence, reason: assessmentReason,
            sources: [evidence.snapshotCycleID], identity: identity, radio: sampleRadio
        )
        publishCurrent()
        #if DEBUG
        let triggerValue: String = switch reason {
        case .startup: "startup"
        case .compensationSample: "timer"
        case .candidateReview: "notification"
        case .systemConfiguration, .coreWLAN, .coreWLANPowerStateChanged, .interfaceChanged: "notification"
        case .appBecameActive, .didWake, .willSleep: "startup"
        case .compensationSampleFailed: "notification"
        }
        var fields = WiFiLinkDiagnosticEvidenceFields.make(from: evidence)
        fields.merge([
            "schemaVersion": 1,
            "time": Self.utcTimestamp(sampleEndedAt),
            "sampleStartedAt": Self.utcTimestamp(sampleStartedAt),
            "sampleEndedAt": Self.utcTimestamp(sampleEndedAt),
            "monotonicNanoseconds": sampleEndMonotonicNanoseconds,
            "sampleStartMonotonicNanoseconds": sampleStartMonotonicNanoseconds,
            "trigger": triggerValue,
            "sampleReason": reason.rawValue,
            "sampleID": sampleID.uuidString,
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "interfaceName": evidence.interfaceName,
            "assessment": assessmentReason.rawValue,
            "state": state.rawValue,
            "reason": assessmentReason.rawValue,
            "captureStartedAt": Self.utcTimestamp(evidence.captureStartedAt),
            "captureEndedAt": Self.utcTimestamp(evidence.captureEndedAt)
        ]) { _, new in new }
        WiFiLinkDiagnosticsLogger.record("sample", fields, fileName: "observations.jsonl")
        #endif
        if reason == .candidateReview, let reviewID = candidateReviewID {
            logCandidateEvent(
                "candidateReviewCompleted",
                evidence: evidence, sessionID: sessionID, generation: generation,
                extra: [
                    "reviewID": reviewID.uuidString,
                    "result": state.rawValue,
                    "reason": assessmentReason.rawValue,
                    "candidateSampleCount": disconnectCandidates.count
                ]
            )
            candidateReviewID = nil
        }
        if oldRadio != sampleRadio, oldRadio != .unavailable {
            publishEvent(.radioChanged, previous: previousEvidence, current: evidence, firstAt: evidence.capturedAt, previousAt: previousConfirmationTime)
        }
        if let eventType {
            publishEvent(
                eventType,
                previous: eventType == .networkIdentityChanged ? identityEventPrevious : previousEvidence,
                current: evidence,
                firstAt: firstCurrentAt,
                previousAt: eventType == .networkIdentityChanged ? identityEventPreviousAt : previousConfirmationTime,
                identityComparisonContinuity: identityContinuity
            )
            lastConfirmedStateAt = evidence.capturedAt
        }
        if continuityReset {
            publishEvent(.continuityReset, previous: previousEvidence, current: evidence, firstAt: nil, previousAt: previousConfirmationTime)
        }
        previousEvidence = evidence
        if trigger != nil {
            Task { await updateTriggerInterface(evidence.interfaceName, sessionID: sessionID) }
        }
    }

    private func appendCandidate(_ evidence: WiFiLinkRawEvidence) -> Bool {
        guard evidence.mode == .none || evidence.mode == .noneOrReadFailure,
              evidence.coreWLANModeRawValue == nil || evidence.coreWLANModeRawValue == 0,
              evidence.radio == .reportedOn,
              evidence.radioPowerOnRaw != false,
              evidence.linkActive == false,
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

    private static func confirmsRadioOff(_ evidence: WiFiLinkRawEvidence, reason: WiFiLinkChangeReason) -> Bool {
        reason == .coreWLANPowerStateChanged
            && evidence.radioPowerOnRaw == false
            && evidence.radio == .reportedOffOrReadFailure
            && evidence.linkActive == false
            && evidence.linkSource == .systemConfiguration
            && evidence.readFailures[.linkActive] == nil
            && evidence.readFailures[.radio] == nil
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
        lifecycleGeneration &+= 1
        activeSampleID = nil
        pendingSampleReasons.remove(.candidateReview)
        cancelCandidateReview(reason: reason.rawValue)
        linkEpoch &+= 1
        hasAssociationEvidenceGap = true
        identityBoundaryEpochAdvancedForGap = true
        currentContinuityValid = false
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

    private func isCurrent(sessionID: UUID, generation: UInt64) -> Bool {
        isRunning && runSessionID == sessionID && lifecycleGeneration == generation
    }

    private func compensationTick(sessionID: UUID) async {
        guard isRunning, runSessionID == sessionID else { return }
        await requestSample(reason: .compensationSample, sessionID: sessionID)
    }

    private func takePendingSampleReason() -> WiFiLinkChangeReason? {
        let priority: [WiFiLinkChangeReason] = [
            .candidateReview, .appBecameActive, .systemConfiguration, .coreWLANPowerStateChanged, .coreWLAN,
            .interfaceChanged, .didWake, .willSleep, .compensationSample, .startup
        ]
        guard let reason = priority.first(where: pendingSampleReasons.contains) else { return nil }
        pendingSampleReasons.remove(reason)
        return reason
    }

    private func scheduleCandidateReview(sessionID: UUID) {
        guard isRunning, runSessionID == sessionID,
              candidateReviewID == nil, candidateReviewTask == nil,
              !pendingSampleReasons.contains(.candidateReview),
              !disconnectCandidates.isEmpty else { return }
        let reviewID = UUID()
        let generation = lifecycleGeneration
        candidateReviewID = reviewID
        candidateReviewTask = Task { [weak self, reviewClock, reviewInterval] in
            do {
                try await reviewClock.sleep(for: reviewInterval)
            } catch {
                return
            }
            await self?.candidateReviewFired(
                reviewID: reviewID, sessionID: sessionID, generation: generation
            )
        }
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "candidateReviewScheduled",
            "reviewID": reviewID.uuidString,
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "reviewIntervalMilliseconds": reviewIntervalMilliseconds,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
    }

    private func candidateReviewFired(reviewID: UUID, sessionID: UUID, generation: UInt64) async {
        guard candidateReviewID == reviewID,
              isCurrent(sessionID: sessionID, generation: generation) else { return }
        candidateReviewTask = nil
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "candidateReviewStarted",
            "reviewID": reviewID.uuidString,
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
        await requestSample(reason: .candidateReview, sessionID: sessionID)
    }

    private func cancelCandidateReview(reason: String) {
        pendingSampleReasons.remove(.candidateReview)
        guard let reviewID = candidateReviewID else { return }
        candidateReviewTask?.cancel()
        candidateReviewTask = nil
        candidateReviewID = nil
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("event", [
            "eventType": "candidateReviewCancelled",
            "reviewID": reviewID.uuidString,
            "runSessionID": runSessionID.uuidString,
            "lifecycleGeneration": lifecycleGeneration,
            "reason": reason,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
        #endif
    }

    private var reviewIntervalMilliseconds: Int64 {
        let components = reviewInterval.components
        return components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
    }

    private func logCandidateEvent(
        _ eventType: String,
        evidence: WiFiLinkRawEvidence,
        sessionID: UUID,
        generation: UInt64,
        extra: [String: Any] = [:]
    ) {
        #if DEBUG
        var fields: [String: Any] = [
            "eventType": eventType,
            "source": "WiFiLinkStateCenter",
            "cycleID": evidence.snapshotCycleID.uuidString,
            "interfaceIndex": evidence.interfaceIndex.map { String($0) } ?? "unknown",
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "sampleTime": Self.utcTimestamp(evidence.capturedAt),
            "linkEpoch": linkEpoch,
            "time": Self.utcTimestamp(Date()),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ]
        fields.merge(extra) { _, new in new }
        WiFiLinkDiagnosticsLogger.record("event", fields)
        #endif
    }

    private func logDiscardedSample(
        sampleID: UUID, sessionID: UUID, startedAt: Date, endedAt: Date,
        startMonotonic: UInt64, endMonotonic: UInt64, reason: String
    ) {
        #if DEBUG
        WiFiLinkDiagnosticsLogger.record("sample", [
            "schemaVersion": 1,
            "kind": "sample",
            "time": Self.utcTimestamp(endedAt),
            "sampleStartedAt": Self.utcTimestamp(startedAt),
            "sampleEndedAt": Self.utcTimestamp(endedAt),
            "monotonicNanoseconds": endMonotonic,
            "sampleStartMonotonicNanoseconds": startMonotonic,
            "trigger": "notification",
            "sampleReason": "discarded",
            "sampleID": sampleID.uuidString,
            "runSessionID": sessionID.uuidString,
            "state": "unknown",
            "reason": reason,
            "resultingStateImpact": "discardedWithoutPublication"
        ], fileName: "observations.jsonl")
        #endif
    }

    private func logSampleFailure(
        sampleID: UUID, reason: WiFiLinkChangeReason, sessionID: UUID, generation: UInt64,
        startedAt: Date, endedAt: Date, startMonotonic: UInt64, endMonotonic: UInt64,
        failureReason: String, resultingState: VerifiedWiFiLinkState
    ) {
        #if DEBUG
        let triggerValue = reason == .startup || reason == .appBecameActive || reason == .didWake || reason == .willSleep
            ? "startup"
            : "notification"
        WiFiLinkDiagnosticsLogger.record("sample", [
            "schemaVersion": 1,
            "kind": "sample",
            "time": Self.utcTimestamp(endedAt),
            "sampleStartedAt": Self.utcTimestamp(startedAt),
            "sampleEndedAt": Self.utcTimestamp(endedAt),
            "monotonicNanoseconds": endMonotonic,
            "sampleStartMonotonicNanoseconds": startMonotonic,
            "trigger": triggerValue,
            "sampleReason": reason.rawValue,
            "sampleID": sampleID.uuidString,
            "runSessionID": sessionID.uuidString,
            "lifecycleGeneration": generation,
            "mode": "unavailable",
            "modeRaw": NSNull(),
            "modeInterpretation": "unavailable",
            "modeReadAmbiguous": false,
            "state": resultingState.rawValue,
            "reason": failureReason,
            "failureReason": failureReason,
            "resultingStateImpact": "currentEvidenceInvalidated"
        ], fileName: "observations.jsonl")
        #endif
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
        previous: WiFiLinkRawEvidence?, current: WiFiLinkRawEvidence?, firstAt: Date?, previousAt: Date? = nil,
        identityComparisonContinuity: WiFiIdentityComparisonContinuity? = nil
    ) {
        sequence &+= 1
        let event = WiFiLinkStateEvent(
            type: type, runSessionID: runSessionID, sequence: sequence,
            interfaceName: current?.interfaceName ?? previous?.interfaceName,
            interfaceIndex: current?.interfaceIndex ?? previous?.interfaceIndex,
            linkEpoch: linkEpoch, previousEvidence: previous, currentEvidence: current,
            lastConfirmedPreviousAt: previousAt ?? lastConfirmedStateAt, firstConfirmedCurrentAt: firstAt,
            confirmedAt: Date(), identityComparisonContinuity: identityComparisonContinuity
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
            "identityComparisonContinuity": event.identityComparisonContinuity?.rawValue ?? NSNull() as Any,
            "time": ISO8601DateFormatter().string(from: event.confirmedAt),
            "monotonicNanoseconds": DispatchTime.now().uptimeNanoseconds
        ])
#endif
        eventSubscribers.values.forEach { $0.yield(event) }
    }

    /// Serialize listener registration and removal across reentrant start/stop
    /// calls so a late registration cannot outlive a stop or replace a new run.
    private func performTriggerOperation(
        _ operation: @escaping @MainActor @Sendable () -> Void
    ) async {
        let previous = triggerOperationTail
        let operationTask = Task { @MainActor in
            await previous?.value
            operation()
        }
        triggerOperationTail = operationTask
        await operationTask.value
    }

    private func startTrigger(interfaceName: String?, sessionID: UUID) async {
        guard isRunning, runSessionID == sessionID else { return }
        let trigger: any WiFiLinkChangeTriggering
        if let existing = self.trigger {
            trigger = existing
        } else {
            trigger = await MainActor.run { WiFiLinkChangeTrigger() }
            guard isRunning, runSessionID == sessionID else { return }
            self.trigger = trigger
        }
        await performTriggerOperation { [weak self] in
            trigger.start(interfaceName: interfaceName) { [weak self] reason in
                Task { await self?.triggered(reason, sessionID: sessionID) }
            }
        }
    }

    private func stopTrigger() async {
        guard let trigger else { return }
        await performTriggerOperation { trigger.stop() }
    }

    private func triggered(_ reason: WiFiLinkChangeReason, sessionID: UUID) async {
        guard isRunning, runSessionID == sessionID else { return }
        switch reason {
        case .willSleep, .didWake, .interfaceChanged:
            await resetContinuity(reason: reason)
            clearTrustedAssociations()
        default:
            break
        }
        await requestSample(reason: reason, sessionID: sessionID)
    }

    private func updateTriggerInterface(_ name: String, sessionID: UUID) async {
        guard isRunning, runSessionID == sessionID, let trigger else { return }
        await MainActor.run { trigger.updateInterface(name) }
    }

    private func removeCurrentSubscriber(_ id: UUID) { currentSubscribers.removeValue(forKey: id) }
    private func removeEventSubscriber(_ id: UUID) { eventSubscribers.removeValue(forKey: id) }

    private static func trustedIdentity(_ evidence: WiFiLinkRawEvidence) -> WiFiNetworkIdentity? {
        let identity = WiFiNetworkIdentity(ssid: evidence.ssid, bssid: evidence.bssid)
        return identity.isKnown ? identity : nil
    }

    private static func compareIdentity(
        previous: WiFiNetworkIdentity?, current: WiFiNetworkIdentity?
    ) -> TrustedIdentityDifference {
        guard let previous, let current else { return .insufficientEvidence }
        if let old = previous.ssid, let new = current.ssid, old != new { return .ssidChanged }
        if let old = previous.bssid, let new = current.bssid, old != new { return .bssidChanged }
        guard previous.ssid != nil, current.ssid != nil,
              previous.bssid != nil, current.bssid != nil else { return .insufficientEvidence }
        return .sameComparableFields
    }

    private func clearTrustedAssociations() {
        lastVerifiedAssociation = nil
        lastComparableIdentityAssociation = nil
        trustedSSID = nil
        trustedBSSID = nil
        hasAssociationEvidenceGap = false
        hasIdentityEvidenceGap = false
        identityBoundaryEpochAdvancedForGap = false
    }

    private static var isUnitTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    private static func utcTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
