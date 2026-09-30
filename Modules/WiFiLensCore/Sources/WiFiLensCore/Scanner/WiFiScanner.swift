import CoreWLAN
import Foundation
import OSLog

public enum WiFiScanEvent: Sendable {
    case networks([WiFiNetwork])
    case failure(String)
}

public protocol WiFiScanStreaming: Sendable {
    func startScanning(
        interval: Duration,
        onEvent: @escaping @Sendable (WiFiScanEvent) async -> Void
    ) async
    func stopScanning() async
    func interfaceName() async -> String?
    func supportedBands() async -> Set<ChannelBand>
    func supportedChannels() async -> [(ChannelBand, Int)]
    func supportedWLANChannelsRaw() async -> [(Int, Int)]
    func devicePHYCapabilities() async -> DevicePHYCapabilities
    func cadenceDiagnostics() async -> WiFiScanCadenceDiagnostics
}

extension WiFiScanStreaming {
    func cadenceDiagnostics() async -> WiFiScanCadenceDiagnostics {
        WiFiScanCadenceDiagnostics(skippedSlotCount: 0)
    }
}

protocol WiFiScanClock: Sendable {
    func now() async -> Duration
    func sleep(for duration: Duration) async throws
}

struct SystemWiFiScanClock: WiFiScanClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

struct WiFiScanCadence: Sendable {
    let interval: Duration
    private var nextTarget: Duration

    init(interval: Duration, startedAt: Duration) {
        precondition(interval > .zero)
        self.interval = interval
        nextTarget = startedAt + interval
    }

    mutating func waitForNextScan(using clock: any WiFiScanClock) async throws -> UInt64 {
        let now = await clock.now()
        var skippedSlotCount: UInt64 = 0
        while nextTarget < now {
            nextTarget += interval
            skippedSlotCount &+= 1
        }
        let remaining = nextTarget - now
        nextTarget += interval
        if remaining > .zero {
            try await clock.sleep(for: remaining)
        }
        return skippedSlotCount
    }
}

public struct WiFiScanCadenceDiagnostics: Equatable, Sendable {
    public let skippedSlotCount: UInt64
    public init(skippedSlotCount: UInt64) { self.skippedSlotCount = skippedSlotCount }
}

public actor WiFiScanner: WiFiScanStreaming {
    private static let logger = Logger(subsystem: "com.kaoru.wifi-lens", category: "scanner")
    private let client = CWWiFiClient.shared()
    private let clock: any WiFiScanClock
    private var shouldStop = false
    private var scanTask: Task<Void, Never>?
    private var skippedSlotCount: UInt64 = 0

    public init() { self.clock = SystemWiFiScanClock() }

    init(clock: any WiFiScanClock) {
        self.clock = clock
    }

    /// Emits scan results or failures at the configured interval.
    /// Scans are scheduled at wall-clock intervals (every `interval` seconds from the
    /// first scan), so scan duration does not push the next scan later.
    /// On scan failure, retries up to 3 times with exponential backoff (1s → 2s → 4s).
    public func startScanning(
        interval: Duration = .seconds(3),
        onEvent: @escaping @Sendable (WiFiScanEvent) async -> Void
    ) {
        shouldStop = false
        Self.logger.debug("startScanning() — reset stop flag")
        scanTask?.cancel()
        scanTask = Task {
            let startedAt = await clock.now()
            var cadence = WiFiScanCadence(interval: interval, startedAt: startedAt)
            while !shouldStop && !Task.isCancelled {
                let scanResult = await scanWithRetry()
                switch scanResult {
                case .success(let networks):
                    await onEvent(.networks(networks))
                case .failure(let error):
                    let msg = String(describing: error)
                    Self.logger.error("scan exhausted retries: \(msg)")
                    await onEvent(.failure(msg))
                }

                do {
                    let skipped = try await cadence.waitForNextScan(using: clock)
                    skippedSlotCount &+= skipped
                    if skipped > 0 {
                        Self.logger.warning(
                            "scan cadence skipped \(skipped) missed wall-clock slot(s)"
                        )
                    }
                } catch {
                    break
                }
            }
        }
    }

    private enum ScanError: Error { case exhausted(String) }

    private func scanWithRetry() async -> Result<[WiFiNetwork], ScanError> {
        for attempt in 1...3 {
            do {
                let networks = try client.interface()?.scanForNetworks(withSSID: nil) ?? []
                let wrapped = networks.compactMap { WiFiNetwork(from: $0) }
                return .success(wrapped)
            } catch {
                let msg = String(describing: error)
                if attempt < 3 {
                    let backoff = Duration.seconds(1 << (attempt - 1))
                    Self.logger.warning("scan attempt \(attempt) failed, retrying in \(backoff): \(msg)")
                    do { try await Task.sleep(for: backoff) }
                    catch { return .failure(.exhausted("cancelled during retry")) }
                } else {
                    return .failure(.exhausted(msg))
                }
            }
        }
        return .failure(.exhausted("unknown error"))
    }

    public func stopScanning() async {
        shouldStop = true
        let task = scanTask
        scanTask = nil
        task?.cancel()
        await task?.value
    }

    public func cadenceDiagnostics() async -> WiFiScanCadenceDiagnostics {
        WiFiScanCadenceDiagnostics(skippedSlotCount: skippedSlotCount)
    }

    public func interfaceName() -> String? {
        client.interface()?.interfaceName
    }

    public func supportedBands() -> Set<ChannelBand> {
        guard let channels = client.interface()?.supportedWLANChannels() else {
            return Set(ChannelBand.allCases)
        }
        var bands = Set<ChannelBand>()
        for channel in channels {
            if let band = ChannelBand(rawValue: channel.channelBand.rawValue) {
                bands.insert(band)
            }
        }
        return bands
    }

    /// Returns the full set of (band, channel) tuples the hardware can use.
    /// This reflects the OS regulatory database + driver capabilities.
    public func supportedChannels() -> [(ChannelBand, Int)] {
        guard let channels = client.interface()?.supportedWLANChannels() else {
            return []
        }
        return channels.compactMap { cw in
            guard let band = ChannelBand(rawValue: cw.channelBand.rawValue) else { return nil }
            return (band, cw.channelNumber)
        }
    }

    /// Returns raw (band raw value, channel number) pairs for region fingerprinting.
    /// These are Sendable, unlike CWChannel.
    public func supportedWLANChannelsRaw() -> [(Int, Int)] {
        guard let channels = client.interface()?.supportedWLANChannels() else { return [] }
        return channels.map { (Int($0.channelBand.rawValue), $0.channelNumber) }
    }

    /// Derives device PHY capabilities from the active interface.
    public func devicePHYCapabilities() -> DevicePHYCapabilities {
        guard let iface = client.interface() else {
            return .default
        }
        let phy = iface.activePHYMode()
        let allChannels = supportedChannels()
        let is6Ghz = allChannels.contains(where: { $0.0 == .band6GHz })
        let channelNumbers = Set(allChannels.map(\.1))
        let dfsChannelSet: Set<Int> = [
            52, 56, 60, 64, 100, 104, 108, 112, 116,
            120, 124, 128, 132, 136, 140, 144,
        ]
        let supportsDFS = !channelNumbers.intersection(dfsChannelSet).isEmpty
        return DevicePHYCapabilities(
            supportsAX: phy.rawValue >= 6,
            supportsAC: phy.rawValue >= 5,
            supportsN: phy.rawValue >= 4,
            supportsBE: phy.rawValue >= 7,
            supports6GHz: is6Ghz,
            supportsDFS: supportsDFS,
            supports160MHz: false
        )
    }
}
