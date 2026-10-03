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
    @ObservationIgnored var fallbackRouterProvider: @MainActor () -> String? = {
        NetworkInfoService.fetch()?.router
    }

    // MARK: - Guidance

    @ObservationIgnored private let onRoamingCompleted: @MainActor () -> Void

    // MARK: - Private

    private var timer: Timer?
    private var startDate: Date?
    private var lastBSSID: String?
    private var lastRSSI: Int?
    private var lastChannel: Int?
    private var currentSegmentIndex: Int = -1
    private var previousProbe: WiFiCurrentStatus?

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
        state = .idle
        errorMessage = nil

        Task {
            let status = await roamingProvider.fetchCurrentProbe()
            guard status.isConnected, let ssid = status.ssid else {
                errorMessage = String(localized: "roaming.error.no_connection", comment: "Error when trying to start roaming test without Wi-Fi")
                return
            }
            currentSSID = ssid
            currentBSSID = status.bssid
            currentRSSI = status.rssi ?? -100
            currentChannel = status.channel ?? 0
            currentTxRate = status.txRate ?? 0
            currentPhyMode = status.phyMode
            previousProbe = status
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
            guard let bssid = status.bssid else { return }

            segments = []
            transitions = []
            lastBSSID = bssid
            lastRSSI = status.rssi ?? -100
            lastChannel = status.channel ?? 0
            startDate = Date()
            elapsedTime = 0
            errorMessage = nil

            let segment = RoamingSegment(bssid: bssid, startTime: Date())
            segments = [segment]
            currentSegmentIndex = 0

            previousProbe = status
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
        let wasRunning = state == .running
        timer?.invalidate()
        timer = nil

        // Close current segment
        if currentSegmentIndex >= 0, currentSegmentIndex < segments.count {
            segments[currentSegmentIndex].endTime = Date()
        }

        refreshConnectionInfo()
        state = .stopped

        // A normal user-initiated stop of a live test is a useful roaming
        // completion; idle stops and power-off interruptions are not.
        if userInitiated, wasRunning {
            onRoamingCompleted()
        }
    }

    // MARK: - Tick

    func tick() {
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
            let previousGatewayLatency = gatewayLatency

            // Resolve the gateway against this tick's connection snapshot. A
            // gateway captured from an earlier AP can otherwise be charted as
            // latency for the newly joined network.
            routerIP = status.isConnected
                ? (status.routerIP ?? fallbackRouterProvider())
                : nil

            // Ping gateway asynchronously
            if let router = routerIP {
                let result = await latencyProvider.measure(routerIP: router)
                guard state == .running, generation == tickGeneration else { return }
                gatewayLatency = result.latencyMs
            } else {
                gatewayLatency = nil
            }

            guard status.isConnected, let newBSSID = status.bssid else {
                // Connection gaps are not AP samples. Keep the last confirmed
                // identity and signal metadata so the next AP can still form
                // a handoff against the preceding connected sample.
                applyProbe(status)
                return
            }

            let newRSSI = status.rssi ?? -100
            let newChannel = status.channel ?? 0

            // Detect AP transition
            if let lastBSSID, newBSSID != lastBSSID {
                let transitionTime = Date()

                // Append final sample to old segment at the exact transition time
                if currentSegmentIndex >= 0, currentSegmentIndex < segments.count {
                    let finalSample = RoamingSample(
                        timestamp: transitionTime,
                        rssi: lastRSSI ?? 0,
                        channel: lastChannel ?? 0,
                        txRate: currentTxRate,
                        gatewayLatency: previousGatewayLatency
                    )
                    segments[currentSegmentIndex].samples.append(finalSample)
                    segments[currentSegmentIndex].endTime = transitionTime
                }

                // Record transition
                let event = APTransitionEvent(
                    timestamp: transitionTime,
                    fromBSSID: lastBSSID,
                    toBSSID: newBSSID,
                    rssiBefore: lastRSSI ?? 0,
                    rssiAfter: newRSSI,
                    channelBefore: lastChannel ?? 0,
                    channelAfter: newChannel
                )
                transitions.append(event)

                // Start new segment at the same timestamp
                let segment = RoamingSegment(bssid: newBSSID, startTime: transitionTime)
                segments.append(segment)
                currentSegmentIndex = segments.count - 1
            }

            // Keep the last known AP identity across a transient disconnect
            // probe so the next connected sample can still form a handoff.
            self.lastBSSID = newBSSID
            self.lastRSSI = newRSSI
            self.lastChannel = newChannel

            applyProbe(status)
            appendSample()
        }
    }

    // MARK: - Helpers

    private func refreshConnectionInfo() {
        Task {
            let status = await roamingProvider.fetchCurrentProbe()
            applyProbe(status)
        }
    }

    private func applyProbe(_ status: WiFiCurrentStatus) {
        currentSSID = status.ssid
        currentBSSID = status.bssid
        currentRSSI = status.rssi ?? -100
        currentChannel = status.channel ?? 0
        currentTxRate = status.txRate ?? 0
        currentPhyMode = status.phyMode
        routerIP = status.isConnected
            ? (status.routerIP ?? fallbackRouterProvider())
            : nil
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
