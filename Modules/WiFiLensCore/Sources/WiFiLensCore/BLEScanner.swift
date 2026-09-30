import CoreBluetooth
import Foundation

// MARK: - Public event types

public enum BLEBluetoothState: Sendable, Equatable {
    case unknown, resetting, unsupported, poweredOff, poweredOn, unauthorized

    public var label: String {
        switch self {
        case .unknown:      String(localized: "common.label.unknown", comment: "Generic unknown value label")
        case .resetting:    String(localized: "ble.state.resetting", comment: "BLE state: adapter is resetting")
        case .unsupported:  String(localized: "ble.state.unsupported", comment: "BLE state: hardware does not support BLE")
        case .poweredOff:   String(localized: "ble.state.bluetooth_off", comment: "BLE state: Bluetooth is off")
        case .poweredOn:    String(localized: "common.label.ready", comment: "Ready state indicator")
        case .unauthorized: String(localized: "ble.state.permission_denied", comment: "BLE state: permission was denied")
        }
    }
}

public enum BLEScanEvent: Sendable {
    case deviceBatch([UUID: [BLEAdvertisementEvent]])
    case bluetoothStateChanged(BLEBluetoothState)
    case failure(String)
}

/// A single BLE scan generation. Its stop operation only terminates the
/// stream paired with this session, so stale callers cannot stop a newer scan.
public struct BLEScanSession: Sendable {
    public let events: AsyncStream<BLEScanEvent>
    private let stopOperation: @Sendable () async -> Void

    public init(
        events: AsyncStream<BLEScanEvent>,
        stop: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.stopOperation = stop
    }

    public func stop() async {
        await stopOperation()
    }
}

public protocol BLEScanning: Sendable {
    func startScanning() async -> BLEScanSession
}

/// Creates the sole buffer between CoreBluetooth callbacks and the UI consumer.
/// Two slots cover four seconds of the normal batched scan cadence. When the UI
/// is stalled, newer observation snapshots replace stale ones; session finish
/// remains an out-of-band continuation lifecycle signal and is never dropped.
enum BLEScanEventStreamFactory {
    static func make() -> (
        events: AsyncStream<BLEScanEvent>,
        continuation: AsyncStream<BLEScanEvent>.Continuation
    ) {
        let channel = AsyncStream<BLEScanEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(2)
        )
        return (channel.stream, channel.continuation)
    }
}

// MARK: - Scanner actor

public actor BLEScanner: BLEScanning {
    private var delegate: BLEScannerDelegate?
    private var currentState = BLEBluetoothState.unknown
    private var activeSessionID: UUID?
    private var activeContinuation: AsyncStream<BLEScanEvent>.Continuation?

    var bluetoothState: BLEBluetoothState { currentState }

    public init() {}

    public func startScanning() async -> BLEScanSession {
        await startScanning(batchInterval: .seconds(2))
    }

    private func startScanning(batchInterval: Duration) async -> BLEScanSession {
        stopActiveSession()
        let sessionID = UUID()
        let queue = DispatchQueue(label: "com.wifilens.blescanner", qos: .utility)
        let del = BLEScannerDelegate(queue: queue)
        delegate = del

        let channel = BLEScanEventStreamFactory.make()
        let continuation = channel.continuation
        activeSessionID = sessionID
        activeContinuation = continuation
        del.setHandlers(
            onStateChange: { [weak self] state in
                Task { [weak self] in
                    await self?.setState(state)
                    continuation.yield(.bluetoothStateChanged(state))
                }
            },
            onDiscover: { [weak del] event in
                del?.accumulate(event)
            },
            onReady: { [weak del] in
                del?.startScan()
                del?.beginActivity()
            }
        )

        // Start the central manager (triggers onReady when powered on)
        del.start()

        // Batch flush + scan restart loop
        let streamTask = Task {
            let restartInterval: TimeInterval = 30
            var lastRestart = Date()

            while !Task.isCancelled {
                try? await Task.sleep(for: batchInterval)

                if Task.isCancelled { break }

                // Restart scan every 30s to prevent macOS callback decay
                if Date().timeIntervalSince(lastRestart) > restartInterval {
                    del.restartScan()
                    lastRestart = Date()
                }

                // Drain accumulated events and yield directly
                let accum = del.drainAccumulator()
                if !accum.isEmpty {
                    continuation.yield(.deviceBatch(accum))
                }
            }
        }

        continuation.onTermination = { _ in
            streamTask.cancel()
            del.clearHandlers()
            del.stopScan()
            del.endActivity()
            del.stop()
            Task {
                await self.clearSessionIfCurrent(sessionID)
            }
        }
        return BLEScanSession(events: channel.events) { [weak self] in
            await self?.stopScanning(sessionID: sessionID)
        }
    }

    private func stopScanning(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        stopActiveSession()
    }

    private func stopActiveSession() {
        let continuation = activeContinuation
        activeContinuation = nil
        activeSessionID = nil
        delegate?.stopScan()
        delegate?.endActivity()
        delegate = nil
        continuation?.finish()
    }

    private func clearSessionIfCurrent(_ sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        activeSessionID = nil
        activeContinuation = nil
        delegate = nil
    }

    // MARK: - Private

    private func setState(_ state: BLEBluetoothState) {
        currentState = state
    }
}

// MARK: - Delegate bridge

// `@unchecked Sendable` is required because CoreBluetooth delivers delegate
// callbacks on an arbitrary queue while `onTermination` may run on any thread.
// All mutable closure properties below are guarded by `delegateLock` so that
// writes (start / onTermination) and reads (delegate callbacks) are
// synchronized; closures are copied out under the lock and invoked outside it.
private final class BLEScannerDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let queue: DispatchQueue
    private var centralManager: CBCentralManager?
    private var accumulator: [UUID: [BLEAdvertisementEvent]] = [:]
    private let accumulatorLock = NSLock()
    private let delegateLock = NSLock()
    private var started = false
    private var activityToken: NSObjectProtocol?

    var onStateChange: ((BLEBluetoothState) -> Void)?
    var onDiscover: ((BLEAdvertisementEvent) -> Void)?
    var onReady: (() -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
    }

    // MARK: - Handler configuration

    func setHandlers(
        onStateChange: ((BLEBluetoothState) -> Void)?,
        onDiscover: ((BLEAdvertisementEvent) -> Void)?,
        onReady: (() -> Void)?
    ) {
        delegateLock.lock()
        self.onStateChange = onStateChange
        self.onDiscover = onDiscover
        self.onReady = onReady
        delegateLock.unlock()
    }

    func clearHandlers() {
        delegateLock.lock()
        onStateChange = nil
        onDiscover = nil
        onReady = nil
        delegateLock.unlock()
    }

    func start() {
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    func stop() {
        centralManager?.delegate = nil
        centralManager = nil
    }

    func startScan() {
        guard !started else { return }
        guard centralManager?.state == .poweredOn else { return }
        started = true
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]
        // Defer to next main-queue iteration — CBCentralManager may report
        // .poweredOn in its delegate callback before its internal state is
        // fully ready. Calling scanForPeripherals synchronously triggers:
        // "API MISUSE: can only accept this command while in the powered on state"
        DispatchQueue.main.async { [weak self] in
            guard self?.started == true else { return }
            self?.centralManager?.scanForPeripherals(withServices: nil, options: options)
        }
    }

    func stopScan() {
        started = false
        centralManager?.stopScan()
    }

    func beginActivity() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: String(localized: "ble.scan.description", comment: "Description of BLE scanning feature")
        )
    }

    func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    func restartScan() {
        stopScan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startScan()
        }
    }

    func accumulate(_ event: BLEAdvertisementEvent) {
        accumulatorLock.lock()
        var events = accumulator[event.peripheralIdentifier] ?? []
        if events.count < 50 {
            events.append(event)
            accumulator[event.peripheralIdentifier] = events
        }
        accumulatorLock.unlock()
    }

    func drainAccumulator() -> [UUID: [BLEAdvertisementEvent]] {
        accumulatorLock.lock()
        let result = accumulator
        accumulator = [:]
        accumulatorLock.unlock()
        return result
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: BLEBluetoothState = switch central.state {
        case .unknown:      .unknown
        case .resetting:    .resetting
        case .unsupported:  .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff:   .poweredOff
        case .poweredOn:    .poweredOn
        @unknown default:   .unknown
        }

        delegateLock.lock()
        let onStateChangeHandler = onStateChange
        delegateLock.unlock()
        onStateChangeHandler?(state)

        if central.state == .poweredOn, !started {
            delegateLock.lock()
            let onReadyHandler = onReady
            delegateLock.unlock()
            onReadyHandler?()
        }

        if central.state != .poweredOn {
            stopScan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let event = BLEAdvertisementEvent(
            timestamp: Date(),
            peripheralIdentifier: peripheral.identifier,
            localName: (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name,
            rssi: RSSI.intValue,
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString),
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        )
        delegateLock.lock()
        let onDiscoverHandler = onDiscover
        delegateLock.unlock()
        onDiscoverHandler?(event)
    }
}
