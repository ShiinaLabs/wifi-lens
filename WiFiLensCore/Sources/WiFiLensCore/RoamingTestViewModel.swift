import Foundation
import Observation
import CoreWLAN
import AppKit

public enum TestState: Equatable {
    case idle
    case ready
    case running
    case stopped
}

@MainActor
@Observable
public final class RoamingTestViewModel {

    // MARK: - Device

    public let isPortable = DeviceCapabilities.isPortable

    // MARK: - Init

    public init(
        roamingProvider: RoamingProbeProviding = RoamingProbeProvider(),
        latencyProvider: GatewayLatencyProviding = GatewayLatencyProvider(),
        onRoamingCompleted: @escaping @MainActor () -> Void = {}
    ) {
        self.roamingProvider = roamingProvider
        self.latencyProvider = latencyProvider
        self.onRoamingCompleted = onRoamingCompleted
    }

    // MARK: - State

    public var state: TestState = .idle
    public var errorMessage: String?

    // MARK: - Current connection

    public var currentSSID: String?
    public var currentBSSID: String?
    public var currentRSSI: Int = 0
    public var currentChannel: Int = 0
    public var currentTxRate: Double = 0
    public var currentPhyMode: String?
    public var routerIP: String?
    public var gatewayLatency: Double?

    // MARK: - Test data

    public var segments: [RoamingSegment] = []
    public var transitions: [APTransitionEvent] = []
    public var elapsedTime: TimeInterval = 0
    public var totalSamples: Int { segments.reduce(0) { $0 + $1.samples.count } }

    // MARK: - Providers

    let roamingProvider: RoamingProbeProviding
    let latencyProvider: GatewayLatencyProviding

    // MARK: - Guidance

    @ObservationIgnored private let onRoamingCompleted: @MainActor () -> Void

    // MARK: - Private

    private var timer: Timer?
    private var startDate: Date?
    private var lastRSSI: Int?
    private var lastChannel: Int?
    private var currentSegmentIndex: Int = -1
    private var previousVerifiedProbe: WiFiCurrentStatus?
    private var readinessGeneration = 0

    private static let maximumProbeContinuityGap: TimeInterval = 3

    /// Generation of the current test run. Incremented whenever a run
    /// starts or stops so in-flight tick continuations can detect that the
    /// session they captured no longer matches the current one.
    private var generation = 0

    /// True while a tick's probe fetch/measure cycle is in flight, so
    /// overlapping ticks never run concurrently and appended sample
    /// timestamps stay monotonic.
    private var isTickInFlight = false

    // MARK: - Computed

    public var canStart: Bool {
        state == .ready || state == .stopped
    }

    public var isRunning: Bool {
        state == .running
    }

    // MARK: - Actions

    public func checkReadiness() {
        readinessGeneration += 1
        let requestGeneration = readinessGeneration
        state = .idle
        errorMessage = nil

        Task {
            let status = await roamingProvider.fetchCurrentProbe()
            guard readinessGeneration == requestGeneration else { return }
            guard WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated else {
                errorMessage = String(localized: "roaming.error.no_connection", comment: "Error when trying to start roaming test without Wi-Fi")
                return
            }
            currentSSID = status.ssid
            currentBSSID = status.bssid
            currentRSSI = status.rssi ?? -100
            currentChannel = status.channel ?? 0
            currentTxRate = status.txRate ?? 0
            currentPhyMode = status.phyMode
            state = .ready
        }
    }

    public func handleWiFiPowerStateChange(_ powerState: WiFiPowerState) {
        switch powerState {
        case .poweredOn:
            if !isRunning {
                checkReadiness()
            }

        case .poweredOff, .interfaceUnavailable:
            // Power-off and interface-loss interruptions are never recorded as
            // useful roaming completions.
            stopTest(userInitiated: false)
            self.state = .idle
            errorMessage = nil

        case .unknown:
            break
        }
    }

    public func startTest() {
        guard canStart else { return }
        // Invalidate any tick still in flight from a previous run.
        generation += 1
        let startGeneration = generation

        Task {
            let status = await roamingProvider.fetchCurrentProbe()
            guard generation == startGeneration, canStart else { return }
            guard WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated,
                  let bssid = status.bssid else { return }

            segments = []
            transitions = []
            lastRSSI = status.rssi ?? -100
            lastChannel = status.channel ?? 0
            startDate = Date()
            elapsedTime = 0
            errorMessage = nil

            let segment = RoamingSegment(bssid: bssid, startTime: Date())
            segments = [segment]
            currentSegmentIndex = 0

            previousVerifiedProbe = status
            applyProbe(status)
            appendSample()

            state = .running
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    self.tick()
                }
            }
        }
    }

    public func stopTest(userInitiated: Bool = true) {
        // Invalidate any tick still awaiting a probe fetch or latency
        // measurement; its continuation must not append samples after stop.
        generation += 1
        readinessGeneration += 1
        let wasRunning = state == .running
        timer?.invalidate()
        timer = nil

        // Close current segment
        if currentSegmentIndex >= 0, currentSegmentIndex < segments.count {
            segments[currentSegmentIndex].endTime = Date()
        }

        refreshConnectionInfo(generation: generation)
        state = .stopped

        // A normal user-initiated stop of a live test is a useful roaming
        // completion; idle stops and power-off interruptions are not.
        if userInitiated, wasRunning {
            onRoamingCompleted()
        }
    }

    // MARK: - Tick

    private func tick() {
        guard state == .running else { return }
        // Skip this tick when the previous cycle is still awaiting a probe
        // fetch or latency measurement, so ticks never overlap and samples
        // are appended in strictly increasing order.
        guard !isTickInFlight else { return }
        isTickInFlight = true
        // Capture the generation of the run this tick belongs to. A
        // continuation that resumes after the run stopped or restarted must
        // bail out instead of mutating the (possibly reset) state.
        let tickGeneration = generation

        Task {
            defer { isTickInFlight = false }

            let status = await roamingProvider.fetchCurrentProbe()
            guard state == .running, generation == tickGeneration else { return }

            // Ping gateway asynchronously
            if let router = routerIP {
                let result = await latencyProvider.measure(routerIP: router)
                guard state == .running, generation == tickGeneration else { return }
                gatewayLatency = result.latencyMs
            }

            recordProbe(status)
        }
    }

    /// Applies one probe only when its public raw evidence validates as an
    /// associated link. Kept internal so deterministic tests exercise the same
    /// transition path as the timer.
    func recordProbe(_ status: WiFiCurrentStatus) {
        guard state == .running,
              WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated,
              let bssid = status.bssid,
              !bssid.isEmpty else {
            previousVerifiedProbe = nil
            return
        }

        let previous = previousVerifiedProbe
        let continuous = previous.map { Self.isContinuousAssociation(from: $0, to: status) } ?? false
        applyProbe(status)

        if continuous, let previous, let oldBSSID = previous.bssid, oldBSSID != bssid {
            let transitionTime = status.timestamp
            if currentSegmentIndex >= 0, currentSegmentIndex < segments.count {
                let finalSample = RoamingSample(
                    timestamp: transitionTime,
                    rssi: lastRSSI ?? 0,
                    channel: lastChannel ?? 0,
                    txRate: currentTxRate,
                    gatewayLatency: gatewayLatency
                )
                segments[currentSegmentIndex].samples.append(finalSample)
                segments[currentSegmentIndex].endTime = transitionTime
            }
            transitions.append(APTransitionEvent(
                timestamp: transitionTime,
                fromBSSID: oldBSSID,
                toBSSID: bssid,
                rssiBefore: lastRSSI ?? 0,
                rssiAfter: status.rssi ?? 0,
                channelBefore: lastChannel ?? 0,
                channelAfter: status.channel ?? 0
            ))
            segments.append(RoamingSegment(bssid: bssid, startTime: transitionTime))
            currentSegmentIndex = segments.count - 1
        } else if !continuous {
            // A gap, unknown interval, interface change, or network boundary
            // starts a fresh baseline without inventing an AP transition.
            segments.append(RoamingSegment(bssid: bssid, startTime: status.timestamp))
            currentSegmentIndex = segments.count - 1
        }

        previousVerifiedProbe = status
        lastRSSI = status.rssi ?? -100
        lastChannel = status.channel ?? 0
        appendSample()
    }

    private static func isContinuousAssociation(from previous: WiFiCurrentStatus, to current: WiFiCurrentStatus) -> Bool {
        guard WiFiLinkEvidenceValidator.assessment(for: previous)?.state == .associated,
              WiFiLinkEvidenceValidator.assessment(for: current)?.state == .associated,
              let oldInterface = previous.interfaceName, !oldInterface.isEmpty,
              oldInterface == current.interfaceName,
              let oldSSID = previous.ssid, !oldSSID.isEmpty,
              oldSSID == current.ssid,
              previous.bssid != nil, current.bssid != nil else { return false }
        if let previousIndex = previous.interfaceIndex, previousIndex != 0,
           let currentIndex = current.interfaceIndex, currentIndex != 0,
           previousIndex != currentIndex { return false }
        let gap = current.timestamp.timeIntervalSince(previous.timestamp)
        return gap > 0 && gap <= maximumProbeContinuityGap
    }

    // MARK: - Helpers

    private func refreshConnectionInfo(generation expectedGeneration: Int) {
        Task {
            let status = await roamingProvider.fetchCurrentProbe()
            guard generation == expectedGeneration else { return }
            applyProbe(status)
        }
    }

    private func applyProbe(_ status: WiFiCurrentStatus) {
        guard WiFiLinkEvidenceValidator.assessment(for: status)?.state == .associated else {
            currentSSID = nil
            currentBSSID = nil
            currentRSSI = 0
            currentChannel = 0
            currentTxRate = 0
            currentPhyMode = nil
            gatewayLatency = nil
            return
        }
        currentSSID = status.ssid
        currentBSSID = status.bssid
        currentRSSI = status.rssi ?? 0
        currentChannel = status.channel ?? 0
        currentTxRate = status.txRate ?? 0
        currentPhyMode = status.phyMode
        routerIP = status.routerIP ?? NetworkInfoService.fetch()?.router
    }

    private func appendSample() {
        guard currentSegmentIndex >= 0, currentSegmentIndex < segments.count else { return }
        let segment = segments[currentSegmentIndex]
        // First sample of a segment uses the segment's startTime,
        // so consecutive segments share the transition timestamp and
        // there is no visual gap on the time axis.
        let timestamp = segment.samples.isEmpty ? segment.startTime : Date()
        let sample = RoamingSample(
            timestamp: timestamp,
            rssi: currentRSSI,
            channel: currentChannel,
            txRate: currentTxRate,
            gatewayLatency: gatewayLatency
        )
        segments[currentSegmentIndex].samples.append(sample)

        if let start = startDate {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    // MARK: - Persistence

    public func saveSession() {
        guard !segments.isEmpty else { return }

        let record = RoamingSessionRecord(
            version: RoamingSessionRecord.currentVersion,
            savedAt: Date(),
            ssid: currentSSID ?? String(localized: "common.label.unknown", comment: "Generic unknown value label"),
            bssid: currentBSSID,
            phyMode: currentPhyMode,
            channel: currentChannel,
            duration: elapsedTime,
            segments: segments,
            transitions: transitions
        )

        let panel = NSSavePanel()
        panel.title = String(localized: "roaming.session.save_title", comment: "Save roaming session dialog title")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultFileName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(record)
            try data.write(to: url)
        } catch {
            errorMessage = String(localized: "roaming.error.save_failed", comment: "Error message when session save fails")
        }
    }

    public func loadSession() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "roaming.session.load_title", comment: "Load roaming session dialog title")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let record = try decoder.decode(RoamingSessionRecord.self, from: data)

            segments = record.segments
            transitions = record.transitions
            elapsedTime = record.duration
            currentSSID = record.ssid
            currentBSSID = record.bssid
            currentPhyMode = record.phyMode
            currentChannel = record.channel
            currentRSSI = record.segments.last?.samples.last?.rssi ?? -100
            currentTxRate = record.segments.last?.samples.last?.txRate ?? 0
            state = .stopped
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "roaming.error.load_failed", comment: "Error message when session load fails")
        }
    }

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    private var defaultFileName: String {
        let ssid = currentSSID ?? "WiFi"
        let ts = Self.fileNameFormatter.string(from: Date())
        return "\(ssid)_\(ts).wifi-roam"
    }
}
